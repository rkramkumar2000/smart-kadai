import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../billing/bill.dart';
import '../catalogue/product.dart';
import '../core/units.dart';
import '../voice/product_matcher.dart';
import 'theme.dart';

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

  void _pay(PaymentMode mode) {
    final no = s.completeBill(mode);
    if (no == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Bill $no saved (${mode.label}). Stock updated.',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
    _inputFocus.requestFocus();
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
        const SizedBox(height: 12),
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
