import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../catalogue/product.dart';
import '../core/units.dart';
import 'theme.dart';
import 'whatsapp.dart';

/// Stock levels, low-stock alerts, corrections with a reason, and history.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.state});

  final AppState state;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String _query = '';
  bool _lowOnly = false;

  AppState get s => widget.state;

  /// A plain order list the owner can send to a supplier.
  String _orderText(List<Product> items) {
    final b = StringBuffer('${s.shopName} order list:\n');
    for (final p in items) {
      final need = (p.minStock * 2 - p.stockQty).clamp(0, double.infinity);
      b.writeln(
        '- ${p.nameEn} (${p.nameTa}): ${formatQty(need.toDouble())} ${p.stockUnit.code}',
      );
    }
    return b.toString();
  }

  Future<void> _share(List<Product> items) =>
      sendOnWhatsApp(context, _orderText(items));

  Future<void> _correct(Product p) async {
    final countCtl = TextEditingController(text: formatQty(p.stockQty));
    var reason = 'Counted again';
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Correct stock: ${p.nameEn}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Now: ${p.stockUnit.format(p.stockQty)}',
                  style: const TextStyle(color: KadaiColors.quiet),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: countCtl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Actual stock (${p.stockUnit.code})',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Reason · காரணம்'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in const [
                      'Counted again',
                      'Spoiled',
                      'Returned',
                      'Own use',
                      'Opening stock',
                    ])
                      ChoiceChip(
                        label: Text(r),
                        selected: reason == r,
                        onSelected: (_) => setLocal(() => reason = r),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(countCtl.text.trim());
                if (v == null || v < 0) return;
                Navigator.pop(context, v);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    countCtl.dispose();
    if (result == null) return;
    final delta = roundQty(result - p.stockQty);
    if (delta != 0) s.adjustStock(p, delta, reason);
  }

  Future<void> _history(Product p) async {
    final rows = s.repo.stockHistory(p.id);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stock history: ${p.nameEn}'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: rows.isEmpty
              ? const Center(child: Text('No changes yet'))
              : ListView(
                  children: [
                    for (final m in rows)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          m.delta >= 0
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: m.delta >= 0
                              ? KadaiColors.green
                              : KadaiColors.danger,
                        ),
                        title: Text(
                          '${m.delta >= 0 ? '+' : ''}${p.stockUnit.format(m.delta)} · ${_type(m.type)}',
                        ),
                        subtitle: Text(
                          '${_when(m.at)}${m.note.isEmpty ? '' : ' · ${m.note}'}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static String _type(String t) => switch (t) {
    'SALE' => 'Sale',
    'PURCHASE' => 'Purchase',
    'CORRECTION' => 'Correction',
    _ => t,
  };

  static String _when(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final low = s.lowStock;
        final out = low.where((p) => p.stockQty <= 0).length;
        final q = _query.trim().toLowerCase();
        final rows = (_lowOnly ? low : s.activeProducts).where((p) {
          if (q.isEmpty) return true;
          return p.nameEn.toLowerCase().contains(q) ||
              p.nameTanglish.toLowerCase().contains(q) ||
              p.nameTa.contains(_query.trim()) ||
              p.code.toLowerCase().contains(q);
        }).toList();
        final value = s.activeProducts.fold<double>(
          0,
          (sum, p) => sum + (p.stockQty > 0 ? p.stockQty * p.purchasePrice : 0),
        );
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TwoLang('Stock', 'இருப்பு', size: 24),
              const SizedBox(height: 14),
              Row(
                children: [
                  _tile(
                    'Running low · குறைவு',
                    '${low.length - out} items',
                    KadaiColors.warnTint,
                    KadaiColors.warnInk,
                    () => setState(() => _lowOnly = true),
                  ),
                  const SizedBox(width: 14),
                  _tile(
                    'Out of stock · இல்லை',
                    '$out items',
                    const Color(0xFFFDECE7),
                    KadaiColors.danger,
                    () => setState(() => _lowOnly = true),
                  ),
                  const SizedBox(width: 14),
                  _tile(
                    'Stock value at cost',
                    s.user?.canSeeProfit == true ? rupees(value) : '—',
                    Colors.white,
                    KadaiColors.quiet,
                    null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: const TextStyle(fontSize: 17),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search product',
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('Only low stock'),
                    selected: _lowOnly,
                    onSelected: (v) => setState(() => _lowOnly = v),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: low.isEmpty ? null : () => _share(low),
                    icon: const Icon(Icons.send),
                    label: const Text('Send order list on WhatsApp'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: rows.isEmpty
                      ? const Center(
                          child: Text(
                            'Nothing here',
                            style: TextStyle(
                              fontSize: 17,
                              color: KadaiColors.quiet,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: Color(0xFFE8EBE4),
                          ),
                          itemBuilder: (context, i) {
                            final p = rows[i];
                            final color = p.stockQty <= 0
                                ? KadaiColors.danger
                                : p.isLowStock
                                ? KadaiColors.warn
                                : KadaiColors.ink;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: TwoLang(p.nameEn, p.nameTa),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      p.stockUnit.format(p.stockQty),
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Alert below ${p.stockUnit.format(p.minStock)}',
                                      style: const TextStyle(
                                        color: KadaiColors.quiet,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _history(p),
                                    child: const Text('History'),
                                  ),
                                  if (s.user?.canCorrectStock ?? false)
                                    OutlinedButton(
                                      onPressed: () => _correct(p),
                                      child: const Text('Correct'),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(
    String label,
    String value,
    Color bg,
    Color ink,
    VoidCallback? onTap,
  ) => Expanded(
    child: Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: KadaiColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: ink, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
