import 'dart:async';

import 'package:flutter/foundation.dart';

import 'billing/bill.dart';
import 'catalogue/product.dart';
import 'data/shop_repository.dart';
import 'voice/product_matcher.dart';
import 'voice/speech_service.dart';
import 'voice/utterance_parser.dart';

/// Everything the screens share: the catalogue, the bill being made and the
/// voice matches waiting for the owner to confirm.
class AppState extends ChangeNotifier {
  AppState(this.repo, {SpeechService? speech})
    : speech = speech ?? NoSpeechService() {
    _reload();
    _sub = this.speech.results.listen(_onSpeech);
  }

  final ShopRepository repo;
  final SpeechService speech;
  final UtteranceParser _parser = UtteranceParser();
  late StreamSubscription<SpeechResult> _sub;

  List<Product> products = [];
  late ProductMatcher _matcher;
  Bill bill = Bill();

  /// Matches the owner must confirm before they go on the bill.
  final List<VoiceMatch> pending = [];

  /// Last words heard or typed, shown on screen.
  String heard = '';
  bool listening = false;
  ({int bills, double total}) today = (bills: 0, total: 0);

  List<Product> get activeProducts =>
      products.where((p) => p.status == ProductStatus.active).toList();

  void _reload() {
    products = repo.loadProducts();
    _matcher = ProductMatcher(products, learnedAliases: repo.loadAliases());
    today = repo.todaySummary();
  }

  // ------------------------------------------------------------ catalogue

  void saveProduct(Product p) {
    repo.saveProduct(p);
    _reload();
    notifyListeners();
  }

  void adjustStock(Product p, double delta, String reason) {
    repo.adjustStock(p.id, delta, reason);
    _reload();
    notifyListeners();
  }

  // ---------------------------------------------------------------- voice

  Future<void> toggleListening() async {
    if (!speech.isAvailable) return;
    listening = !listening;
    notifyListeners();
    listening ? await speech.start() : await speech.stop();
  }

  void _onSpeech(SpeechResult r) {
    heard = r.text;
    if (r.isFinal) {
      handleSpoken(r.text, EntryMethod.voice);
    } else {
      notifyListeners();
    }
  }

  /// Turns spoken (or typed) words into bill lines. Sure matches go straight
  /// on the bill; unsure ones wait in [pending] for the owner to pick.
  void handleSpoken(String text, EntryMethod method) {
    heard = text;
    for (final item in _parser.parse(text)) {
      final m = _matcher.match(item);
      if (!m.needsConfirmation && m.product != null) {
        bill.add(
          BillLine(
            product: m.product!,
            variant: m.variant,
            count: m.count,
            enteredBy: method,
            spokenText: item.text,
          ),
        );
      } else {
        pending.add(m);
      }
    }
    notifyListeners();
  }

  /// The search box: a barcode adds that item, anything else is read like
  /// speech ("2 hamam soap").
  void handleTyped(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final byCode = findByBarcode(t);
    if (byCode != null) {
      bill.add(
        BillLine(
          product: byCode.$1,
          variant: byCode.$2,
          count: 1,
          enteredBy: EntryMethod.scan,
        ),
      );
      heard = '';
      notifyListeners();
      return;
    }
    handleSpoken(t, EntryMethod.typed);
  }

  (Product, ProductVariant?)? findByBarcode(String code) {
    for (final p in activeProducts) {
      for (final v in p.variants) {
        if (v.barcode == code) return (p, v);
      }
      if (p.barcode == code) return (p, p.defaultVariant);
    }
    return null;
  }

  /// The owner picked [product] for an unsure match. The spoken words are
  /// remembered so next time they match straight away.
  void confirm(VoiceMatch m, Product product) {
    pending.remove(m);
    repo.saveAlias(m.spoken.nameWords.join(' '), product.id);
    _matcher.learn(m.spoken.nameWords, product);
    final pick = ProductMatcher.pickVariant(
      product,
      m.spoken.quantity,
      m.spoken.unit,
    );
    bill.add(
      BillLine(
        product: product,
        variant: pick.variant,
        count: pick.count,
        enteredBy: EntryMethod.voice,
        spokenText: m.spoken.text,
      ),
    );
    notifyListeners();
  }

  void dismiss(VoiceMatch m) {
    pending.remove(m);
    notifyListeners();
  }

  // ----------------------------------------------------------------- bill

  void addTap(Product p, [ProductVariant? v]) {
    bill.add(
      BillLine(
        product: p,
        variant: v ?? p.defaultVariant,
        count: 1,
        enteredBy: EntryMethod.tap,
      ),
    );
    notifyListeners();
  }

  void setCount(int index, double count) {
    if (count <= 0) {
      bill.lines.removeAt(index);
    } else {
      bill.lines[index] = bill.lines[index].withCount(count);
    }
    notifyListeners();
  }

  void setVariant(int index, ProductVariant? v) {
    bill.lines[index] = bill.lines[index].withVariant(v);
    notifyListeners();
  }

  void removeLine(int index) {
    bill.lines.removeAt(index);
    notifyListeners();
  }

  void clearBill() {
    bill = Bill();
    pending.clear();
    heard = '';
    notifyListeners();
  }

  /// Saves the bill, lowers stock and starts a new bill. Returns the number.
  int? completeBill(PaymentMode mode) {
    if (bill.lines.isEmpty) return null;
    final no = repo.saveSale(bill, mode);
    bill = Bill();
    pending.clear();
    heard = '';
    _reload();
    notifyListeners();
    return no;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
