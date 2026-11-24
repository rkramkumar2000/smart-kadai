import '../core/units.dart';
import 'phonetic.dart';
import 'vocabulary.dart';

/// One item heard in a spoken order, before it is matched to a product.
class SpokenItem {
  SpokenItem({
    required this.text,
    required this.nameWords,
    this.quantity,
    this.unit,
  });

  /// The words that made up this item, as heard.
  final String text;

  /// Sound keys of the product-name words, numbers and units removed.
  final List<String> nameWords;

  /// Spoken amount, for example 2 or 0.5. Null when no number was said.
  final double? quantity;

  /// Spoken unit, for example KG. Null when none was said.
  final Unit? unit;

  @override
  String toString() =>
      'SpokenItem(${nameWords.join(' ')}, qty: $quantity, unit: ${unit?.code})';
}

/// Splits one spoken order such as
/// "rendu kadalai mittai, oru kilo kadalai apram anju chocolate"
/// into separate items. Works on the text from any speech-to-text service.
///
/// Both orders are understood: "rendu kadalai mittai" and
/// "kadalai mittai rendu". A new number after a finished item starts the
/// next item, so the owner can keep talking without pauses.
class UtteranceParser {
  UtteranceParser([Vocabulary? vocab]) : _v = vocab ?? Vocabulary.instance;

  final Vocabulary _v;

  List<SpokenItem> parse(String utterance) {
    final items = <SpokenItem>[];
    var b = _Builder();

    void close() {
      final item = b.build();
      if (item != null) items.add(item);
      b = _Builder();
    }

    final raw = splitWords(utterance);
    for (var i = 0; i < raw.length; i++) {
      final word = raw[i];
      final key = word == ',' ? ',' : wordKey(word);
      if (key.isEmpty) continue;

      if (_v.joins.contains(key)) {
        close();
        continue;
      }
      if (_v.fillers.contains(key)) {
        b.raw.add(word);
        continue;
      }

      final fraction = _v.fractions[key];
      final number = fraction ?? _v.number(key);
      final unit = _v.unit(word, key);

      if (number != null) {
        // "oru kilo" / "250 gram": number followed by a unit stays together.
        // A number after a finished item starts a new one.
        if (b.quantity != null || (b.words.isNotEmpty && b.qtyAfterWords)) {
          close();
        }
        if (b.quantity == null) {
          b.quantity = number;
          b.qtyAfterWords = b.words.isNotEmpty;
        } else {
          b.quantity = b.quantity! * number;
        }
        b.raw.add(word);
        continue;
      }
      if (unit != null) {
        if (b.unit != null && b.words.isNotEmpty) close();
        b.unit = unit;
        b.quantity ??= 1;
        b.raw.add(word);
        continue;
      }

      // A product word. If the current item already has its name and its
      // quantity came after the name ("kadalai rendu"), this word starts the
      // next item.
      if (b.words.isNotEmpty && b.quantity != null && b.qtyAfterWords) {
        close();
      }
      b.words.add(key);
      b.raw.add(word);
    }
    close();
    return items;
  }
}

class _Builder {
  final List<String> words = [];
  final List<String> raw = [];
  double? quantity;
  Unit? unit;
  bool qtyAfterWords = false;

  SpokenItem? build() {
    if (words.isEmpty) return null;
    return SpokenItem(
      text: raw.join(' '),
      nameWords: List.of(words),
      quantity: quantity == null ? null : roundQty(quantity!),
      unit: unit,
    );
  }
}
