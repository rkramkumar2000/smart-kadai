import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth/auth.dart';
import 'billing/bill.dart';
import 'catalogue/product.dart';
import 'catalogue/product_import.dart';
import 'core/units.dart';
import 'customers/customers.dart';
import 'data/shop_repository.dart';
import 'purchases/purchases.dart';
import 'reports/reports.dart';
import 'voice/phonetic.dart';
import 'voice/product_matcher.dart';
import 'voice/speech_service.dart';
import 'voice/utterance_parser.dart';
import 'voice/voice_commands.dart';

/// Everything the screens share: the catalogue, the bill being made and the
/// voice matches waiting for the owner to confirm.
class AppState extends ChangeNotifier {
  AppState(this.repo, {SpeechService? speech})
    : speech = speech ?? NoSpeechService(),
      auth = AuthRepository(repo.dbHandle),
      purchases = PurchaseRepository(repo),
      reports = ReportRepository(repo),
      customers = CustomerRepository(repo),
      expenses = ExpenseRepository(repo) {
    _reload();
    _sub = this.speech.results.listen(_onSpeech);
    _changeSub = this.speech.changes.listen((_) => notifyListeners());
  }

  final ShopRepository repo;
  final SpeechService speech;
  final AuthRepository auth;
  final PurchaseRepository purchases;
  final ReportRepository reports;
  final CustomerRepository customers;
  final ExpenseRepository expenses;

  /// Save commands said by voice ("bill podu", "UPI", "கடன்"). The billing
  /// screen runs them so UPI and credit bills show their usual dialogs.
  final _commands = StreamController<PaymentMode>.broadcast();
  Stream<PaymentMode> get voiceSaves => _commands.stream;

  /// Whether the app answers aloud ("2 கடலை மிட்டாய்", "மொத்தம் 150 ரூபாய்").
  bool get voiceReplies => repo.setting('voice_reply', '1') == '1';

  /// Bills put on hold while another customer is served.
  final List<Bill> held = [];

  /// Who is logged in. Null shows the login screen.
  AppUser? user;

  /// The last saved bill, for printing.
  SavedBill? lastBill;
  final UtteranceParser _parser = UtteranceParser();
  late StreamSubscription<SpeechResult> _sub;
  late StreamSubscription<void> _changeSub;

  List<Product> products = [];
  late ProductMatcher _matcher;
  Bill bill = Bill();

  /// Matches the owner must confirm before they go on the bill.
  final List<VoiceMatch> pending = [];

  /// Last words heard or typed, shown on screen.
  String heard = '';

  /// True while the microphone is on.
  bool get listening => speech.isListening;

  /// True when the voice helper is connected and ready.
  bool get voiceReady => speech.isAvailable;

  /// Why voice is not working, in plain words, or null.
  String? get voiceProblem => speech.problem;
  ({int bills, double total}) today = (bills: 0, total: 0);

  List<Product> get activeProducts =>
      products.where((p) => p.status == ProductStatus.active).toList();

  /// Selling products below their minimum stock.
  List<Product> get lowStock =>
      activeProducts.where((p) => p.isLowStock).toList()..sort(
        (a, b) => (a.stockQty / (a.minStock == 0 ? 1 : a.minStock)).compareTo(
          b.stockQty / (b.minStock == 0 ? 1 : b.minStock),
        ),
      );

  String get shopName => repo.setting('shop_name', 'Smart Kadai');

  // ---------------------------------------------------------------- login

  /// Logs in and opens the voice window, so it never covers the PIN screen.
  void login(AppUser u) {
    user = u;
    notifyListeners();
    if (!speech.isAvailable) speech.open();
  }

  /// Locks the app; the bill being made is kept for the next login.
  void lock() {
    user = null;
    notifyListeners();
  }

  /// Call after settings, suppliers or users change.
  void refresh() {
    _reload();
    notifyListeners();
  }

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

  /// Reads a product sheet (CSV or Excel) against the current catalogue.
  ImportResult readProductSheet(List<List<String>> rows) {
    var n = int.parse(repo.nextProductCode().substring(1));
    return buildImport(
      rows,
      repo.loadProducts(),
      newId: repo.newId,
      nextCode: () => 'P${(n++).toString().padLeft(4, '0')}',
    );
  }

  /// Saves imported products. Stock given for a product already in the shop
  /// is recorded as an "Opening stock" correction. With [hideOthers], the
  /// products not in the sheet (such as the starter samples) stop selling.
  void importProducts(ImportResult r, {bool hideOthers = false}) {
    final before = {for (final p in repo.loadProducts()) p.id: p};
    repo.transaction(() {
      for (final p in r.products) {
        repo.saveProduct(p);
        final old = before[p.id];
        if (old != null) {
          final delta = roundQty(p.stockQty - old.stockQty);
          if (delta != 0) {
            repo.moveStock(
              p.id,
              delta,
              'CORRECTION',
              null,
              note: 'Opening stock',
              userId: user?.id,
            );
          }
        }
      }
      if (hideOthers) {
        final keep = {for (final p in r.products) p.id};
        for (final p in before.values) {
          if (!keep.contains(p.id) && p.status == ProductStatus.active) {
            repo.saveProduct(p.copyWith(status: ProductStatus.inactive));
          }
        }
      }
    });
    _reload();
    notifyListeners();
  }

  void adjustStock(Product p, double delta, String reason) {
    repo.adjustStock(p.id, delta, reason, userId: user?.id);
    _reload();
    notifyListeners();
  }

  // ---------------------------------------------------------------- voice

  /// Mic button and F2: opens the voice window if it is not connected yet,
  /// otherwise turns listening on or off.
  Future<void> toggleListening() async {
    if (!speech.isAvailable) {
      // Chrome: opens the helper window, which connects a moment later.
      // Phone: asks for the mic, then listening can start straight away.
      await speech.open();
      if (!speech.isAvailable) return;
    }
    listening ? await speech.stop() : await speech.start();
  }

  /// While set, finished phrases go here instead of onto the bill. The
  /// Products screen uses it to find or add a product by voice.
  void Function(String text)? voiceCapture;

  /// Products whose names sound like [name], best first.
  List<Product> findByVoice(String name) => [
    for (final c in _matcher.rank(
      splitWords(name).map(wordKey).where((k) => k.isNotEmpty).toList(),
    ))
      c.product,
  ];

  void _onSpeech(SpeechResult r) {
    if (!r.isFinal) {
      heard = r.text;
      notifyListeners();
      return;
    }
    final capture = voiceCapture;
    if (capture != null) {
      heard = r.text;
      capture(r.text);
      notifyListeners();
      return;
    }
    final alts = r.alternatives.isEmpty ? [r.text] : r.alternatives;
    for (final a in alts) {
      final cmd = detectCommand(a);
      if (cmd != null) {
        heard = a;
        runCommand(cmd);
        return;
      }
    }
    final best = chooseAlternative(alts);
    final before = bill.lines.length;
    final counts = {for (final l in bill.lines) l.product.id: l.count};
    final (sure, unsure) = handleSpoken(best, EntryMethod.voice);
    _replyAdded(before, counts, unsure);
    repo.logVoice(
      service: speech.runtimeType.toString(),
      heard: r.text,
      alternatives: alts,
      usedText: best,
      sure: sure,
      unsure: unsure,
      result: bill.lines.map((l) => l.product.nameEn).join(', '),
    );
  }

  /// Runs a spoken command. Saving goes through [voiceSaves].
  void runCommand(VoiceCommand c) {
    switch (c) {
      case VoiceCommand.saveCash:
        _save(PaymentMode.cash);
      case VoiceCommand.saveUpi:
        _save(PaymentMode.upi);
      case VoiceCommand.saveCredit:
        _save(PaymentMode.credit);
      case VoiceCommand.clear:
        if (bill.lines.isEmpty && pending.isEmpty) return;
        clearBill();
        _say('பில் அழிக்கப்பட்டது', 'Bill cleared');
      case VoiceCommand.removeLast:
        if (pending.isNotEmpty) {
          pending.removeLast();
          notifyListeners();
          return;
        }
        if (bill.lines.isEmpty) return;
        final l = bill.lines.removeLast();
        notifyListeners();
        _say('${_taName(l)} நீக்கப்பட்டது', '${l.product.nameEn} removed');
      case VoiceCommand.total:
        _sayTotal();
      // Only the total is said: a customer must not hear "wholesale".
      case VoiceCommand.wholesale:
        setWholesale(true);
        _sayTotal();
      case VoiceCommand.retail:
        setWholesale(false);
        _sayTotal();
    }
  }

  void _save(PaymentMode m) {
    if (bill.lines.isEmpty) {
      _say('பில் காலியாக உள்ளது', 'The bill is empty');
      return;
    }
    _commands.add(m);
  }

  void _say(String ta, String en) {
    if (voiceReplies) speech.say(ta, en);
  }

  static String _rs(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _sayTotal() => _say(
    'மொத்தம் ${_rs(bill.total)} ரூபாய்',
    'Total ${_rs(bill.total)} rupees',
  );

  static String _taName(BillLine l) =>
      l.product.nameTa.isEmpty ? l.product.nameEn : l.product.nameTa;

  /// Says what was just added: "2 கடலை மிட்டாய். மொத்தம் 10 ரூபாய்".
  void _replyAdded(int before, Map<String, double> counts, int unsure) {
    final ta = <String>[], en = <String>[];
    for (final l in bill.lines) {
      final added = l.count - (counts[l.product.id] ?? 0);
      if (added <= 0) continue;
      final size = l.variant == null ? l.product.stockUnit.code : '';
      ta.add('${formatQty(added)} $size ${_taName(l)}'.replaceAll('  ', ' '));
      en.add(
        '${formatQty(added)} $size ${l.product.nameEn}'.replaceAll('  ', ' '),
      );
    }
    if (ta.isNotEmpty) {
      _say(
        '${ta.join(', ')}. மொத்தம் ${_rs(bill.total)} ரூபாய்'
            '${unsure > 0 ? '. மீதி எது என்று தொடுங்கள்' : ''}',
        '${en.join(', ')}. Total ${_rs(bill.total)} rupees'
            '${unsure > 0 ? '. Please pick the rest' : ''}',
      );
    } else if (unsure > 0) {
      _say('எது என்று தொடுங்கள்', 'Please pick the product');
    }
  }

  /// Chrome gives up to three guesses of what was said. Use the one whose
  /// items match the catalogue best, preferring its first guess on a tie.
  String chooseAlternative(List<String> alternatives) {
    var best = alternatives.first;
    var bestScore = -1.0;
    for (final a in alternatives) {
      final items = _parser.parse(a);
      if (items.isEmpty) continue;
      var score = 0.0;
      for (final item in items) {
        final m = _matcher.match(item);
        score += m.needsConfirmation ? m.score * 0.5 : 1 + m.score;
      }
      if (score > bestScore + 0.0001) {
        bestScore = score;
        best = a;
      }
    }
    return best;
  }

  /// Turns spoken (or typed) words into bill lines. Sure matches go straight
  /// on the bill; unsure ones wait in [pending] for the owner to pick.
  /// Returns how many items were sure and unsure.
  (int, int) handleSpoken(String text, EntryMethod method) {
    heard = text;
    var sure = 0, unsure = 0;
    for (final item in _parser.parse(text)) {
      final m = _matcher.match(item);
      if (!m.needsConfirmation && m.product != null) {
        sure++;
        bill.add(
          BillLine(
            product: m.product!,
            variant: m.variant,
            count: m.count,
            enteredBy: method,
            spokenText: item.text,
          ),
        );
      } else if (item.nameWords.join().length <= 2) {
        // A stray sound such as "ji" or "um": not worth a question.
        continue;
      } else {
        unsure++;
        pending.add(m);
      }
    }
    notifyListeners();
    return (sure, unsure);
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

  /// Best catalogue guess for a product name read from a supplier bill,
  /// for example "Groundnut 10 KG". Null when nothing is close.
  (Product, ProductVariant?)? guessProduct(String name) {
    final items = _parser.parse(name);
    if (items.isEmpty) return null;
    final m = _matcher.match(items.first);
    final p =
        m.product ?? (m.candidates.isEmpty ? null : m.candidates.first.product);
    if (p == null || m.score < 0.7) return null;
    final it = items.first;
    if (it.unit == null) return (p, p.defaultVariant);
    final pick = ProductMatcher.pickVariant(p, it.quantity, it.unit);
    return (p, pick.variant);
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

  /// Changes one line's price on this bill only. Null or the list price
  /// goes back to the list price.
  void setLinePrice(int index, double? price) {
    final l = bill.lines[index];
    final p = price == null || price < 0 || price == l.listPrice ? null : price;
    bill.lines[index] = l.withPrice(p);
    notifyListeners();
  }

  void removeLine(int index) {
    bill.lines.removeAt(index);
    notifyListeners();
  }

  /// Puts the current bill aside to serve the next customer.
  void holdBill() {
    if (bill.lines.isEmpty) return;
    held.add(bill);
    bill = Bill();
    pending.clear();
    heard = '';
    notifyListeners();
  }

  /// Brings a held bill back. The current bill, if any, is held instead.
  void resumeBill(Bill b) {
    held.remove(b);
    if (bill.lines.isNotEmpty) held.add(bill);
    bill = b;
    notifyListeners();
  }

  void setCustomer(Customer? c) {
    bill.customerId = c?.id;
    bill.customerName = c?.name ?? '';
    bill.customerPhone = c?.phone ?? '';
    // A wholesale customer's bill uses wholesale prices.
    if (c != null && c.isWholesale) bill.setWholesale(true);
    notifyListeners();
  }

  /// Retail or wholesale prices for the whole bill.
  void setWholesale(bool w) {
    bill.setWholesale(w);
    notifyListeners();
  }

  void setDiscount(double rupees) {
    bill.discount = rupees < 0
        ? 0
        : rupees > bill.subtotal
        ? bill.subtotal
        : rupees;
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
    if (mode == PaymentMode.credit && bill.customerId == null) return null;
    final no = repo.saveSale(bill, mode, userId: user?.id);
    _say(
      'பில் சேமிக்கப்பட்டது. ${_rs(bill.total)} ரூபாய். நன்றி',
      'Bill saved. ${_rs(bill.total)} rupees. Thank you',
    );
    lastBill = SavedBill(
      number: no,
      bill: bill,
      mode: mode,
      at: DateTime.now(),
      cashier: user?.name ?? '',
    );
    bill = Bill();
    pending.clear();
    heard = '';
    _reload();
    notifyListeners();
    return no;
  }

  @override
  void dispose() {
    _commands.close();
    _sub.cancel();
    _changeSub.cancel();
    super.dispose();
  }
}

class SavedBill {
  SavedBill({
    required this.number,
    required this.bill,
    required this.mode,
    required this.at,
    required this.cashier,
  });
  final int number;
  final Bill bill;
  final PaymentMode mode;
  final DateTime at;
  final String cashier;
}
