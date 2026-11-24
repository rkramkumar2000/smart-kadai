import 'dart:math' as math;

import '../catalogue/product.dart';
import '../core/units.dart';
import 'fuzzy.dart';
import 'phonetic.dart';
import 'utterance_parser.dart';

/// A name a product can be recognised by: English, Tamil, Tanglish, or an
/// alias learned from the owner's corrections.
class _NameEntry {
  _NameEntry(this.product, this.words)
    : outline = [for (final w in words) consonantOutline(w)];
  final Product product;
  final List<String> words;
  final List<String> outline;
}

class ProductCandidate {
  ProductCandidate(this.product, this.score);
  final Product product;
  final double score;
}

/// Result of matching one spoken item.
class VoiceMatch {
  VoiceMatch({
    required this.spoken,
    required this.candidates,
    required this.product,
    required this.variant,
    required this.count,
    required this.needsConfirmation,
  });

  final SpokenItem spoken;

  /// Best products first, at most 3.
  final List<ProductCandidate> candidates;

  /// Chosen product, or null when nothing came close.
  final Product? product;

  /// Chosen selling unit. Null for a loose sale of [Product.stockUnit].
  final ProductVariant? variant;

  /// How many of [variant] (or how much of the stock unit when loose).
  final double count;

  /// True when the match is unsure and the owner must pick before adding.
  final bool needsConfirmation;

  double get score => candidates.isEmpty ? 0 : candidates.first.score;
}

/// Matches spoken items to the shop's catalogue.
///
/// Everything happens in memory on the PC, so a match takes well under a
/// millisecond for a 300-product shop and voice billing never waits on the
/// internet for this step.
class ProductMatcher {
  ProductMatcher(
    List<Product> products, {
    Map<String, String> learnedAliases = const {},
  }) {
    final byId = {for (final p in products) p.id: p};
    for (final p in products) {
      if (p.status != ProductStatus.active) continue;
      for (final name in [p.nameEn, p.nameTa, p.nameTanglish]) {
        final words = phraseKey(name).split(' ').where((w) => w.isNotEmpty);
        if (words.isNotEmpty) _entries.add(_NameEntry(p, words.toList()));
      }
    }
    learnedAliases.forEach((phrase, productId) {
      final p = byId[productId];
      if (p != null && p.status == ProductStatus.active) {
        _learned[phrase] = p;
      }
    });
  }

  final List<_NameEntry> _entries = [];
  final Map<String, Product> _learned = {};

  /// Score at or above which a clear winner is added without asking.
  static const sureScore = 0.88;

  /// The winner must beat the runner-up by this much to be added directly.
  static const sureGap = 0.05;

  /// Below this, the product is treated as not found.
  static const minScore = 0.6;

  /// Remembers that [spokenWords] meant [product], so the next time it is a
  /// sure match.
  void learn(List<String> spokenWords, Product product) {
    _learned[spokenWords.join(' ')] = product;
  }

  List<ProductCandidate> rank(List<String> spokenWords) {
    final best = <String, ProductCandidate>{};
    final learned = _learned[spokenWords.join(' ')];
    if (learned != null) {
      best[learned.id] = ProductCandidate(learned, 1.0);
    }
    final spokenOutline = [for (final w in spokenWords) consonantOutline(w)];
    // Outlines of very short words ("egg" = k) match too much to trust.
    final useOutline =
        spokenWords.join().length >= 4 && spokenOutline.join().length >= 2;
    for (final e in _entries) {
      var s = phraseSimilarity(spokenWords, e.words);
      if (useOutline && e.outline.join().length >= 2) {
        s = math.max(s, phraseSimilarity(spokenOutline, e.outline) * 0.96);
      }
      final cur = best[e.product.id];
      if (cur == null || s > cur.score) {
        best[e.product.id] = ProductCandidate(e.product, s);
      }
    }
    final list = best.values.where((c) => c.score >= minScore).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list.take(3).toList();
  }

  VoiceMatch match(SpokenItem item) {
    final ranked = rank(item.nameWords);
    if (ranked.isEmpty) {
      return VoiceMatch(
        spoken: item,
        candidates: const [],
        product: null,
        variant: null,
        count: item.quantity ?? 1,
        needsConfirmation: true,
      );
    }
    final top = ranked.first;
    final second = ranked.length > 1 ? ranked[1].score : 0.0;
    final sure = top.score >= sureScore && top.score - second >= sureGap;
    final pick = pickVariant(top.product, item.quantity, item.unit);
    return VoiceMatch(
      spoken: item,
      candidates: ranked,
      product: top.product,
      variant: pick.variant,
      count: pick.count,
      needsConfirmation: !sure,
    );
  }

  /// Picks the selling unit and count for a spoken amount.
  ///
  /// * "anju chocolate" (no unit): 5 of the default variant.
  /// * "two packet chocolate": 2 of the PACKET variant.
  /// * "arai kilo kadalai": the 500 GRAM variant, count 1.
  /// * "rendu kilo kadalai" with a 1 KG variant: 1 KG, count 2.
  /// * "750 gram kadalai" with no fitting variant: loose 0.75 KG at the
  ///   product's per-KG price.
  static ({ProductVariant? variant, double count}) pickVariant(
    Product p,
    double? quantity,
    Unit? unit,
  ) {
    final qty = quantity ?? 1;
    final variants = p.variants;
    if (unit == null) {
      return (variant: p.defaultVariant, count: qty);
    }
    if (unit.family == UnitFamily.pack || unit == Unit.piece) {
      final same = variants.where((v) => v.unit == unit).toList()
        ..sort((a, b) => a.quantity.compareTo(b.quantity));
      if (same.isNotEmpty) return (variant: same.first, count: qty);
      if (unit == Unit.piece) return (variant: p.defaultVariant, count: qty);
    }
    // Measured amount: work in the smallest unit of its family.
    final base = switch (unit.family) {
      UnitFamily.mass => Unit.gram,
      UnitFamily.volume => Unit.ml,
      UnitFamily.count => Unit.piece,
      UnitFamily.pack => unit,
    };
    final amount = unit.convert(qty, base);
    if (amount == null) return (variant: p.defaultVariant, count: qty);

    final sized = <(ProductVariant, double)>[];
    for (final v in variants) {
      final s = v.sizeIn(base);
      if (s != null && s > 0) sized.add((v, s));
    }
    // Exact size: "arai kilo" -> the 500 GRAM variant.
    for (final (v, s) in sized) {
      if ((s - amount).abs() < 0.0001) return (variant: v, count: 1);
    }
    // Whole multiple of a size, largest size first: 2 KG -> 1 KG x 2.
    sized.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (v, s) in sized) {
      final n = amount / s;
      if (n >= 1 && (n - n.roundToDouble()).abs() < 0.0001) {
        return (variant: v, count: n.roundToDouble());
      }
    }
    // Loose quantity in the stock unit.
    final loose = unit.convert(qty, p.stockUnit);
    if (loose != null) return (variant: null, count: loose);
    return (variant: p.defaultVariant, count: qty);
  }
}
