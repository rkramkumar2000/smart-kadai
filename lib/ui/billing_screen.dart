import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../billing/bill.dart';
import '../catalogue/product.dart';
import '../core/units.dart';
import '../printing/bill_printer.dart';
import '../voice/product_matcher.dart';
import 'barcode_scan.dart';
import 'customers_screen.dart';
import 'save_file.dart' show isPhone;
import 'theme.dart';
import 'upi_qr.dart';
import 'whatsapp.dart';

/// The counter screen: speak, scan, type or tap items onto the bill.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.state});

  final AppState state;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  StreamSubscription<PaymentMode>? _voiceSaves;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    // "பில் போடு" / "cash" / "UPI" spoken at the counter saves the bill.
    _voiceSaves = s.voiceSaves.listen((m) {
      if (mounted) _pay(m);
    });
  }

  @override
  void dispose() {
    _voiceSaves?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// On the PC the typing box keeps focus for the barcode gun. On a phone
  /// that would keep the keyboard open over the bill, so it does not.
  void _refocus() {
    if (!isPhone) _inputFocus.requestFocus();
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final before = s.bill.lines.length;
    s.handleTyped(code);
    if (s.bill.lines.length == before && s.findByBarcode(code) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tt(
              'No product has barcode $code. Add it in Products.',
              'இந்த பார்கோடு உள்ள பொருள் இல்லை.',
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
      );
    }
  }

  void _submit() {
    s.handleTyped(_input.text);
    _input.clear();
    _refocus();
  }

  Future<void> _pay(PaymentMode mode) async {
    if (s.bill.lines.isEmpty) return;
    if (mode == PaymentMode.credit && s.bill.customerId == null) {
      final c = await pickCustomer(context, s);
      if (c == null) return;
      s.setCustomer(c);
    }
    final upiId = s.repo.setting('upi_id');
    if (mode == PaymentMode.upi && upiId.isNotEmpty) {
      if (!mounted) return;
      final paid = await showUpiQr(
        context,
        upiId: upiId,
        payee: s.shopName,
        amount: s.bill.total,
        note: s.shopName,
      );
      if (!paid) return;
    }
    final no = s.completeBill(mode);
    if (no == null || !mounted) return;
    final saved = s.lastBill!;
    if (s.repo.setting('auto_print') == '1') printBill(s, saved);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: isNarrow(context) ? double.infinity : 520,
              child: Text(
                t(
                  'Bill $no saved (${mode.label}'
                      '${saved.bill.customerName.isEmpty ? '' : ', ${saved.bill.customerName}'}). '
                      'Stock updated.',
                  'பில் $no சேமிக்கப்பட்டது (${modeTa(mode)}'
                      '${saved.bill.customerName.isEmpty ? '' : ', ${saved.bill.customerName}'}).',
                ),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () {
                messenger.hideCurrentSnackBar();
                printBill(s, saved);
              },
              child: Text(t('Print bill', 'அச்சிடு')),
            ),
            TextButton(
              onPressed: () {
                messenger.hideCurrentSnackBar();
                sendOnWhatsApp(
                  context,
                  billText(saved, s.shopName),
                  phone: saved.bill.customerPhone,
                );
              },
              child: Text(t('WhatsApp bill', 'வாட்ஸ்அப்')),
            ),
          ],
        ),
      ),
    );
    _refocus();
  }

  Future<void> _discount() async {
    final c = TextEditingController(
      text: s.bill.discount == 0 ? '' : formatQty(s.bill.discount),
    );
    final v = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(bi('Discount · தள்ளுபடி')),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t('Bill', 'பில்')} ${rupees(s.bill.subtotal)}'),
              const SizedBox(height: 10),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: t(
                    'Rupees off, or a % like 5%',
                    'தள்ளுபடி ரூபாய், அல்லது 5% போல',
                  ),
                ),
                onSubmitted: (t) => Navigator.pop(context, _parseOff(t)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: Text(t('No discount', 'தள்ளுபடி இல்லை')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _parseOff(c.text)),
            child: Text(t('Apply', 'சரி')),
          ),
        ],
      ),
    );
    c.dispose();
    if (v != null) s.setDiscount(v);
    _refocus();
  }

  double _parseOff(String t) {
    final x = t.trim();
    if (x.endsWith('%')) {
      final p = double.tryParse(x.substring(0, x.length - 1).trim()) ?? 0;
      return (s.bill.subtotal * p / 100).roundToDouble();
    }
    return double.tryParse(x) ?? 0;
  }

  Future<void> _customer() async {
    final c = await pickCustomer(context, s);
    if (c != null) s.setCustomer(c);
    _refocus();
  }

  /// Customer, discount and held bills, just above the total.
  /// Keyboard shortcut hints are for the PC only.
  static String _key(String k) => isPhone ? '' : ' ($k)';

  Widget _billOptions() {
    final b = s.bill;
    final chips = <Widget>[
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: false,
            label: Text(t('Retail', 'சில்லறை')),
            icon: const Icon(Icons.storefront_outlined),
          ),
          ButtonSegment(
            value: true,
            label: Text(t('Wholesale', 'மொத்த விலை')),
            icon: const Icon(Icons.local_shipping_outlined),
          ),
        ],
        selected: {b.wholesale},
        onSelectionChanged: (v) => s.setWholesale(v.first),
      ),
      InputChip(
        avatar: const Icon(Icons.person_outline),
        label: Text(
          b.customerName.isEmpty
              ? '${t('Customer', 'வாடிக்கையாளர்')}${_key('F4')}'
              : b.customerName,
          style: const TextStyle(fontSize: 15),
        ),
        onPressed: _customer,
        onDeleted: b.customerName.isEmpty ? null : () => s.setCustomer(null),
      ),
      InputChip(
        avatar: const Icon(Icons.percent),
        label: Text(
          b.discount == 0
              ? '${t('Discount', 'தள்ளுபடி')}${_key('F6')}'
              : '${rupees(b.discount)} ${t('off', 'தள்ளுபடி')}',
          style: const TextStyle(fontSize: 15),
        ),
        onPressed: b.lines.isEmpty ? null : _discount,
        onDeleted: b.discount == 0 ? null : () => s.setDiscount(0),
      ),
      ActionChip(
        avatar: const Icon(Icons.pause_circle_outline),
        label: Text(
          '${t('Hold bill', 'பில் நிறுத்து')}${_key('F8')}',
          style: const TextStyle(fontSize: 15),
        ),
        onPressed: b.lines.isEmpty ? null : s.holdBill,
      ),
      for (final (i, h) in s.held.indexed)
        ActionChip(
          backgroundColor: KadaiColors.warnTint,
          avatar: const Icon(Icons.play_arrow),
          label: Text(
            '${t('Held', 'நிறுத்திய பில்')} ${i + 1}: '
            '${h.customerName.isEmpty ? '${h.lines.length} ${t('items', 'பொருள்')}' : h.customerName}'
            ' · ${rupees(h.total)}',
            style: const TextStyle(fontSize: 15),
          ),
          onPressed: () => s.resumeBill(h),
        ),
    ];
    // On a phone the options scroll sideways in one row, to leave room for
    // the bill.
    if (isNarrow(context)) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, c) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              c,
            ],
          ],
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }

  void _voice() {
    if (!s.voiceReady && !isPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Opening the voice window in Chrome. The first time, click Allow '
                  'for the microphone.',
              'Chrome-ல் குரல் சாளரம் திறக்கிறது. முதல் முறை மைக்ரோஃபோனுக்கு Allow அழுத்துங்கள்.',
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
      );
    }
    s.toggleListening();
    _refocus();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _voice,
        const SingleActivator(LogicalKeyboardKey.f12): () =>
            _pay(PaymentMode.cash),
        const SingleActivator(LogicalKeyboardKey.escape): s.clearBill,
        const SingleActivator(LogicalKeyboardKey.f4): _customer,
        const SingleActivator(LogicalKeyboardKey.f6): _discount,
        const SingleActivator(LogicalKeyboardKey.f8): s.holdBill,
      },
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => MediaQuery.sizeOf(context).width < 720
            ? Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: _billColumn(phone: true),
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _billColumn()),
                    const SizedBox(width: 20),
                    SizedBox(width: 330, child: _quickItems()),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _billColumn({bool phone = false}) {
    // While the phone keyboard is open only the box and the bill show.
    final typing = phone && MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                autofocus: !isPhone,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: phone
                      ? t('Type an item', 'பொருள் தேடு')
                      : bi(
                          'Type item, scan barcode, or type what was said · பொருள் தேடு',
                        ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            if (isPhone) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 60,
                width: 60,
                child: IconButton.filledTonal(
                  tooltip: tt('Scan barcode', 'பார்கோடு ஸ்கேன்'),
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner, size: 28),
                ),
              ),
            ],
            SizedBox(width: phone ? 8 : 12),
            if (phone)
              SizedBox(
                height: 60,
                width: 72,
                child: FilledButton(
                  onPressed: _voice,
                  style: FilledButton.styleFrom(
                    backgroundColor: s.listening
                        ? KadaiColors.danger
                        : KadaiColors.green,
                    padding: EdgeInsets.zero,
                  ),
                  child: Icon(s.listening ? Icons.stop : Icons.mic, size: 32),
                ),
              )
            else
              SizedBox(
                height: 60,
                child: FilledButton.icon(
                  onPressed: _voice,
                  style: FilledButton.styleFrom(
                    backgroundColor: s.listening
                        ? KadaiColors.danger
                        : KadaiColors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  icon: Icon(s.listening ? Icons.stop : Icons.mic, size: 28),
                  label: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.listening
                            ? t('Listening…', 'கேட்கிறது…')
                            : t('Speak', 'பேசு'),
                        style: const TextStyle(fontSize: 17),
                      ),
                      const Text(
                        'F2 · பேசுங்கள்',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              Icons.circle,
              size: 10,
              color: s.voiceProblem != null
                  ? KadaiColors.danger
                  : s.voiceReady
                  ? KadaiColors.green
                  : KadaiColors.warn,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.voiceProblem ??
                    (!s.voiceReady
                        ? (isPhone
                              ? t(
                                  'Press Speak and allow the microphone.',
                                  'பேசு அழுத்தி மைக்கை அனுமதியுங்கள்.',
                                )
                              : t(
                                  'Voice window is closed. Click Speak to open it in Chrome.',
                                  'குரல் சாளரம் மூடியுள்ளது. திறக்க பேசு அழுத்துங்கள்.',
                                ))
                        : s.listening
                        ? t(
                            'Listening. Speak naturally; items appear as you finish each one.',
                            'கேட்கிறது. சாதாரணமாக பேசுங்கள்; ஒவ்வொரு பொருளும் சொன்னதும் சேரும்.',
                          )
                        : t(
                            'Voice ready. Press F2 or Speak.',
                            'குரல் தயார். F2 அல்லது பேசு அழுத்துங்கள்.',
                          )),
                style: TextStyle(
                  fontSize: s.voiceProblem != null ? 15 : 13,
                  fontWeight: s.voiceProblem != null ? FontWeight.w600 : null,
                  color: s.voiceProblem != null
                      ? KadaiColors.danger
                      : KadaiColors.quiet,
                ),
              ),
            ),
          ],
        ),
        if (s.heard.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, color: KadaiColors.green),
                  const SizedBox(width: 10),
                  Text(
                    t('Heard: ', 'கேட்டது: '),
                    style: const TextStyle(
                      color: KadaiColors.quiet,
                      fontSize: 16,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '"${s.heard}"',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        for (final m in s.pending) ...[
          const SizedBox(height: 12),
          _ConfirmCard(
            match: m,
            products: s.activeProducts,
            onPick: (p) {
              s.confirm(m, p);
              _refocus();
            },
            onSkip: () => s.dismiss(m),
          ),
        ],
        if (phone && !typing) ...[const SizedBox(height: 8), _quickStrip()],
        SizedBox(height: phone ? 8 : 12),
        Expanded(
          child: Card(child: _lines(phone: phone)),
        ),
        if (!typing) ...[
          SizedBox(height: phone ? 6 : 10),
          _billOptions(),
          SizedBox(height: phone ? 6 : 10),
          phone ? _phoneTotalBar() : _totalBar(),
        ],
      ],
    );
  }

  Widget _lines({bool phone = false}) {
    final lines = s.bill.lines;
    if (lines.isEmpty) {
      return Center(
        child: Text(
          t(
            'Speak, scan or tap items to start a bill',
            'பில் தொடங்க பேசுங்கள், ஸ்கேன் செய்யுங்கள் அல்லது பொருளை தொடுங்கள்',
          ),
          style: TextStyle(fontSize: 17, color: KadaiColors.quiet),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: lines.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Color(0xFFE8EBE4)),
      itemBuilder: (context, i) {
        final l = lines[i];
        final step = l.variant == null ? _looseStep(l.product.stockUnit) : 1.0;
        if (phone) return _phoneLine(i, l, step);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: TwoLang(
                  l.product.nameEn,
                  '${l.product.nameTa} · ${_how(l.enteredBy)}',
                ),
              ),
              Expanded(flex: 2, child: _variantPicker(i, l)),
              IconButton.outlined(
                tooltip: t('Less', 'குறை'),
                onPressed: () => s.setCount(i, roundQty(l.count - step)),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  l.quantityLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: t('More', 'கூட்டு'),
                onPressed: () => s.setCount(i, roundQty(l.count + step)),
                icon: const Icon(Icons.add),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  rupees(l.unitPrice),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: KadaiColors.quiet),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  rupees(l.total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: t('Remove', 'நீக்கு'),
                onPressed: () => s.removeLine(i),
                icon: const Icon(Icons.close, color: KadaiColors.danger),
              ),
            ],
          ),
        );
      },
    );
  }

  /// One bill line on a phone: name and size above, buttons below.
  Widget _phoneLine(int i, BillLine l, double step) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: TwoLang(l.product.nameEn, l.product.nameTa)),
            Text(
              rupees(l.total),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            IconButton(
              tooltip: t('Remove', 'நீக்கு'),
              visualDensity: VisualDensity.compact,
              onPressed: () => s.removeLine(i),
              icon: const Icon(Icons.close, color: KadaiColors.danger),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(child: _variantPicker(i, l)),
            IconButton.outlined(
              tooltip: t('Less', 'குறை'),
              onPressed: () => s.setCount(i, roundQty(l.count - step)),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 76,
              child: Text(
                l.quantityLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: t('More', 'கூட்டு'),
              onPressed: () => s.setCount(i, roundQty(l.count + step)),
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ],
    ),
  );

  /// Quick items as one scrolling row on a phone.
  Widget _quickStrip() {
    final items = s.activeProducts.take(14).toList();
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(
          label: Text(
            productName(items[i]),
            style: const TextStyle(fontSize: 15),
          ),
          onPressed: () => s.addTap(items[i]),
        ),
      ),
    );
  }

  /// Total with big pay buttons below it, for a phone.
  Widget _phoneTotalBar() {
    final count = s.bill.lines.length;
    final off = count == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    '${t('$count items · மொத்தம்', '$count பொருள் · மொத்தம்')}'
                    '${s.bill.wholesale ? ' · ${t('WHOLESALE', 'மொத்த விலை')}' : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: KadaiColors.quiet,
                    ),
                  ),
                ),
                Text(
                  rupees(s.bill.total),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    onPressed: off ? null : () => _pay(PaymentMode.cash),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                    child: Text(bi('Cash · பணம்')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: off ? null : () => _pay(PaymentMode.upi),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                    child: const Text('UPI'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: off ? null : () => _pay(PaymentMode.credit),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                    child: Text(t('Credit', 'கடன்')),
                  ),
                ),
              ],
            ),
            if (!off || s.pending.isNotEmpty)
              TextButton(
                onPressed: s.clearBill,
                style: TextButton.styleFrom(
                  foregroundColor: KadaiColors.danger,
                ),
                child: Text(t('Clear bill', 'பில் அழி')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _variantPicker(int i, BillLine l) {
    final options = <ProductVariant?>[...l.product.variants, null];
    return DropdownButton<ProductVariant?>(
      value: l.variant,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: [
        for (final v in options)
          DropdownMenuItem(
            value: v,
            child: Text(
              v?.label ?? '${l.product.stockUnit.code} loose',
              style: const TextStyle(fontSize: 15),
            ),
          ),
      ],
      onChanged: (v) => s.setVariant(i, v),
    );
  }

  Widget _totalBar() {
    final count = s.bill.lines.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t('$count items · மொத்தம்', '$count பொருள் · மொத்தம்')}'
                  '${s.bill.wholesale ? ' · ${t('WHOLESALE', 'மொத்த விலை')}' : ''}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: KadaiColors.quiet,
                  ),
                ),
                Text(
                  rupees(s.bill.total),
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (s.bill.discount > 0)
                  Text(
                    '${rupees(s.bill.subtotal)} − ${rupees(s.bill.discount)} off',
                    style: const TextStyle(color: KadaiColors.quiet),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: count == 0 ? null : () => _pay(PaymentMode.cash),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(150, 60),
                    ),
                    child: Text(bi('Cash · பணம் (F12)')),
                  ),
                  OutlinedButton(
                    onPressed: count == 0 ? null : () => _pay(PaymentMode.upi),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(110, 60),
                    ),
                    child: const Text('UPI'),
                  ),
                  OutlinedButton(
                    onPressed: count == 0
                        ? null
                        : () => _pay(PaymentMode.credit),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(130, 60),
                    ),
                    child: Text(bi('Credit · கடன்')),
                  ),
                  TextButton(
                    onPressed: count == 0 && s.pending.isEmpty
                        ? null
                        : s.clearBill,
                    style: TextButton.styleFrom(
                      foregroundColor: KadaiColors.danger,
                      minimumSize: const Size(90, 60),
                    ),
                    child: Text(t('Clear (Esc)', 'அழி (Esc)')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickItems() {
    final items = s.activeProducts.take(14).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            bi('Quick items · விரைவு'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              for (final p in items)
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: KadaiColors.line),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      s.addTap(p);
                      _refocus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.nameEn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            p.nameTa,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: KadaiColors.quiet,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            '${rupees(p.defaultVariant?.priceFor(wholesale: s.bill.wholesale) ?? p.priceFor(wholesale: s.bill.wholesale))} · ${p.defaultVariant?.label ?? p.stockUnit.code}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: KadaiColors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static double _looseStep(Unit u) => switch (u.family) {
    UnitFamily.mass || UnitFamily.volume => 0.25,
    _ => 1,
  };

  static String _how(EntryMethod m) => switch (m) {
    EntryMethod.voice => t('by voice', 'குரல்'),
    EntryMethod.scan => t('scanned', 'ஸ்கேன்'),
    EntryMethod.typed => t('typed', 'தட்டச்சு'),
    EntryMethod.tap => t('tapped', 'தொடுதல்'),
  };
}

/// Yellow card for an unsure voice match: the owner picks the right product
/// before it goes on the bill.
class _ConfirmCard extends StatefulWidget {
  const _ConfirmCard({
    required this.match,
    required this.products,
    required this.onPick,
    required this.onSkip,
  });

  final VoiceMatch match;
  final List<Product> products;
  final ValueChanged<Product> onPick;
  final VoidCallback onSkip;

  @override
  State<_ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends State<_ConfirmCard> {
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final amount = m.spoken.unit != null
        ? m.spoken.unit!.format(m.spoken.quantity ?? 1)
        : '× ${formatQty(m.spoken.quantity ?? 1)}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KadaiColors.warnTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9C46A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline, color: KadaiColors.warnInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.candidates.isEmpty
                      ? tt(
                          'Not found: "${m.spoken.text}". Which product?',
                          '"${m.spoken.text}" கிடைக்கவில்லை. எந்த பொருள்?',
                        )
                      : tt(
                          'Which one for "${m.spoken.text}" ($amount)?',
                          '"${m.spoken.text}" ($amount) எது?',
                        ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KadaiColors.warnInk,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onSkip,
                child: Text(t('Skip', 'வேண்டாம்')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (i, c) in m.candidates.indexed)
                OutlinedButton(
                  onPressed: () => widget.onPick(c.product),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: i == 0 ? KadaiColors.warn : KadaiColors.line,
                      width: i == 0 ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    '${productName(c.product)} · ${rupees(c.product.defaultVariant?.sellingPrice ?? c.product.sellingPrice)}',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _searching = !_searching),
                style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                icon: const Icon(Icons.search),
                label: Text(t('Other product', 'வேறு பொருள்')),
              ),
            ],
          ),
          if (_searching) ...[
            const SizedBox(height: 10),
            Autocomplete<Product>(
              displayStringForOption: productName,
              optionsBuilder: (v) {
                final q = v.text.toLowerCase();
                if (q.isEmpty) return const Iterable<Product>.empty();
                return widget.products.where(
                  (p) =>
                      p.nameEn.toLowerCase().contains(q) ||
                      p.nameTanglish.toLowerCase().contains(q) ||
                      p.nameTa.contains(v.text),
                );
              },
              onSelected: widget.onPick,
              fieldViewBuilder: (context, c, f, onSubmit) => TextField(
                controller: c,
                focusNode: f,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: bi('Search product · பொருள் தேடு'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Payment mode in Tamil.
String modeTa(PaymentMode m) => switch (m) {
  PaymentMode.cash => 'பணம்',
  PaymentMode.upi => 'UPI',
  PaymentMode.credit => 'கடன்',
};

/// A product's name in the screen's language.
String productName(Product p) =>
    p.nameTa.isEmpty ? p.nameEn : tt(p.nameEn, p.nameTa);
