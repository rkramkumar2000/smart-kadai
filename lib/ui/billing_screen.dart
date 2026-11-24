import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../billing/bill.dart';
import '../catalogue/product.dart';
import '../core/units.dart';
import '../printing/bill_printer.dart';
import '../voice/product_matcher.dart';
import 'customers_screen.dart';
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

  AppState get s => widget.state;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _submit() {
    s.handleTyped(_input.text);
    _input.clear();
    _inputFocus.requestFocus();
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
        content: Row(
          children: [
            Expanded(
              child: Text(
                'Bill $no saved (${mode.label}'
                '${saved.bill.customerName.isEmpty ? '' : ', ${saved.bill.customerName}'}). '
                'Stock updated.',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () {
                messenger.hideCurrentSnackBar();
                printBill(s, saved);
              },
              child: const Text('Print bill'),
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
              child: const Text('WhatsApp bill'),
            ),
          ],
        ),
      ),
    );
    _inputFocus.requestFocus();
  }

  Future<void> _discount() async {
    final c = TextEditingController(
      text: s.bill.discount == 0 ? '' : formatQty(s.bill.discount),
    );
    final v = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discount · தள்ளுபடி'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bill ${rupees(s.bill.subtotal)}'),
              const SizedBox(height: 10),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Rupees off, or a % like 5%',
                ),
                onSubmitted: (t) => Navigator.pop(context, _parseOff(t)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: const Text('No discount'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _parseOff(c.text)),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    c.dispose();
    if (v != null) s.setDiscount(v);
    _inputFocus.requestFocus();
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
    _inputFocus.requestFocus();
  }

  /// Customer, discount and held bills, just above the total.
  Widget _billOptions() {
    final b = s.bill;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InputChip(
          avatar: const Icon(Icons.person_outline),
          label: Text(
            b.customerName.isEmpty ? 'Customer (F4)' : b.customerName,
            style: const TextStyle(fontSize: 15),
          ),
          onPressed: _customer,
          onDeleted: b.customerName.isEmpty ? null : () => s.setCustomer(null),
        ),
        InputChip(
          avatar: const Icon(Icons.percent),
          label: Text(
            b.discount == 0 ? 'Discount (F6)' : '${rupees(b.discount)} off',
            style: const TextStyle(fontSize: 15),
          ),
          onPressed: b.lines.isEmpty ? null : _discount,
          onDeleted: b.discount == 0 ? null : () => s.setDiscount(0),
        ),
        ActionChip(
          avatar: const Icon(Icons.pause_circle_outline),
          label: const Text('Hold bill (F8)', style: TextStyle(fontSize: 15)),
          onPressed: b.lines.isEmpty ? null : s.holdBill,
        ),
        for (final (i, h) in s.held.indexed)
          ActionChip(
            backgroundColor: KadaiColors.warnTint,
            avatar: const Icon(Icons.play_arrow),
            label: Text(
              'Held ${i + 1}: '
              '${h.customerName.isEmpty ? '${h.lines.length} items' : h.customerName}'
              ' · ${rupees(h.total)}',
              style: const TextStyle(fontSize: 15),
            ),
            onPressed: () => s.resumeBill(h),
          ),
      ],
    );
  }

  void _voice() {
    if (!s.voiceReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Opening the voice window in Chrome. The first time, click Allow '
            'for the microphone.',
            style: TextStyle(fontSize: 15),
          ),
        ),
      );
    }
    s.toggleListening();
    _inputFocus.requestFocus();
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
        builder: (context, _) => Padding(
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

  Widget _billColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                autofocus: true,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Type item, scan barcode, or type what was said · பொருள் தேடு',
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 12),
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
                      s.listening ? 'Listening…' : 'Speak',
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
              color: s.voiceReady ? KadaiColors.green : KadaiColors.warn,
            ),
            const SizedBox(width: 6),
            Text(
              !s.voiceReady
                  ? 'Voice window is closed. Click Speak to open it in Chrome.'
                  : s.listening
                  ? 'Listening through Chrome. Speak naturally; items appear as you finish each one.'
                  : 'Voice ready. Press F2 or Speak.',
              style: const TextStyle(fontSize: 13, color: KadaiColors.quiet),
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
                  const Text(
                    'Heard: ',
                    style: TextStyle(color: KadaiColors.quiet, fontSize: 16),
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
              _inputFocus.requestFocus();
            },
            onSkip: () => s.dismiss(m),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(child: Card(child: _lines())),
        const SizedBox(height: 10),
        _billOptions(),
        const SizedBox(height: 10),
        _totalBar(),
      ],
    );
  }

  Widget _lines() {
    final lines = s.bill.lines;
    if (lines.isEmpty) {
      return const Center(
        child: Text(
          'Speak, scan or tap items to start a bill',
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
                tooltip: 'Less',
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
                tooltip: 'More',
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
                tooltip: 'Remove',
                onPressed: () => s.removeLine(i),
                icon: const Icon(Icons.close, color: KadaiColors.danger),
              ),
            ],
          ),
        );
      },
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
                  '$count items · மொத்தம்',
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
                    child: const Text('Cash · பணம் (F12)'),
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
                    child: const Text('Credit · கடன்'),
                  ),
                  TextButton(
                    onPressed: count == 0 && s.pending.isEmpty
                        ? null
                        : s.clearBill,
                    style: TextButton.styleFrom(
                      foregroundColor: KadaiColors.danger,
                      minimumSize: const Size(90, 60),
                    ),
                    child: const Text('Clear (Esc)'),
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
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Quick items · விரைவு',
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
                      _inputFocus.requestFocus();
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
                            '${rupees(p.defaultVariant?.sellingPrice ?? p.sellingPrice)} · ${p.defaultVariant?.label ?? p.stockUnit.code}',
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
    EntryMethod.voice => 'by voice',
    EntryMethod.scan => 'scanned',
    EntryMethod.typed => 'typed',
    EntryMethod.tap => 'tapped',
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
                      ? 'Not found: "${m.spoken.text}". Which product? · எந்த பொருள்?'
                      : 'Which one for "${m.spoken.text}" ($amount)? · எது?',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KadaiColors.warnInk,
                  ),
                ),
              ),
              TextButton(onPressed: widget.onSkip, child: const Text('Skip')),
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
                    '${c.product.nameEn} · ${c.product.nameTa} · ${rupees(c.product.defaultVariant?.sellingPrice ?? c.product.sellingPrice)}',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _searching = !_searching),
                style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                icon: const Icon(Icons.search),
                label: const Text('Other product'),
              ),
            ],
          ),
          if (_searching) ...[
            const SizedBox(height: 10),
            Autocomplete<Product>(
              displayStringForOption: (p) => '${p.nameEn} · ${p.nameTa}',
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
                decoration: const InputDecoration(
                  hintText: 'Search product · பொருள் தேடு',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
