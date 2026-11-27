import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../core/units.dart';
import '../customers/customers.dart';
import '../reports/reports.dart';
import 'save_file.dart';
import 'theme.dart';

/// Sales, profit, payment split, best sellers and purchases for a period,
/// with export to Excel.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.today;

  AppState get s => widget.state;

  Future<void> _export(bool sales) async {
    final (from, to) = _period.range(DateTime.now());
    final csv = sales
        ? s.reports.salesCsv(from, to)
        : s.reports.purchasesCsv(from, to);
    final name =
        '${sales ? 'sales' : 'purchases'}-${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}.csv';
    final path = await saveCsv(context, name, csv);
    if (path == null || isPhone) return;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved $path. Open it in Excel.')));
  }

  Future<void> _addExpense() async {
    final amt = TextEditingController();
    final note = TextEditingController();
    var cat = Expense.categories.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add expense · செலவு'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in Expense.categories)
                      ChoiceChip(
                        label: Text(c),
                        selected: cat == c,
                        onSelected: (_) => setLocal(() => cat = c),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amt,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount ₹'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final v = double.tryParse(amt.text.trim());
    final n = note.text;
    // The dialog still uses its text boxes while it closes, so they are
    // left for Dart to clean up instead of being disposed here.
    if (ok != true || v == null || v <= 0) return;
    s.expenses.add(DateTime.now(), cat, v, note: n, userId: s.user?.id);
    setState(() {});
  }

  Widget _expenses(DateTime from, DateTime to) {
    final list = s.expenses.list(from, to);
    return _card(
      'Expenses · செலவுகள்',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isEmpty)
            const Text(
              'No expenses added. Add rent, electricity and salary to see real profit.',
              style: TextStyle(color: KadaiColors.quiet),
            ),
          for (final e in list)
            Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    '${e.day.day}-${e.day.month}',
                    style: const TextStyle(color: KadaiColors.quiet),
                  ),
                ),
                Expanded(
                  child: Text(
                    e.note.isEmpty ? e.category : '${e.category} · ${e.note}',
                  ),
                ),
                Text(
                  rupees(e.amount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => setState(() => s.expenses.delete(e.id)),
                ),
              ],
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final (from, to) = _period.range(DateTime.now());
        final r = s.reports.build(from, to);
        final seeProfit = s.user?.canSeeProfit ?? false;
        final narrow = isNarrow(context);
        final tiles = [
          _tile('Sales · விற்பனை', rupees(r.sales), '${r.bills} bills'),
          _tile(
            'Profit · லாபம்',
            seeProfit ? rupees(r.profit) : '—',
            seeProfit && r.sales > 0
                ? '${(r.profit / r.sales * 100).toStringAsFixed(1)}% of sales'
                : '',
          ),
          _tile(
            'Bought · கொள்முதல்',
            rupees(r.purchases),
            '${r.purchaseBills} supplier bills',
          ),
          _tile(
            'You owe suppliers',
            rupees(r.supplierDue),
            'All suppliers today',
          ),
          _tile(
            'Expenses · செலவு',
            rupees(r.expenses),
            'Rent, salary, current…',
          ),
          _tile(
            'Real profit',
            seeProfit ? rupees(r.netProfit) : '—',
            'Profit minus expenses',
          ),
          _tile(
            'Customers owe you',
            rupees(r.customerDue),
            'Credit book today',
          ),
          _tile('Discounts given', rupees(r.discounts), 'On bills'),
        ];
        // Four tiles a row on the PC, two on a phone.
        final perRow = narrow ? 2 : 4;
        Widget pair(Widget a, Widget b) => narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [a, const SizedBox(height: 12), b],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: a),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: b),
                ],
              );
        return SingleChildScrollView(
          padding: screenPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: const TwoLang('Reports', 'அறிக்கை', size: 24),
                actions: [
                  for (final p in ReportPeriod.values)
                    ChoiceChip(
                      label: Text(
                        '${p.label} · ${p.tamil}',
                        style: const TextStyle(fontSize: 15),
                      ),
                      selected: _period == p,
                      onSelected: (_) => setState(() => _period = p),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < tiles.length; i += perRow) ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var j = i;
                        j < i + perRow && j < tiles.length;
                        j++
                      ) ...[
                        if (j > i) const SizedBox(width: 12),
                        Expanded(child: tiles[j]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 2),
              pair(_daily(r), _modes(r)),
              const SizedBox(height: 14),
              pair(_top(r), _expenses(from, to)),
              const SizedBox(height: 14),
              _staff(from, to),
              const SizedBox(height: 14),
              ScreenHeader(
                title: Text(
                  'Voice entered ${(r.voiceShare * 100).round()}% of bill lines',
                  style: const TextStyle(color: KadaiColors.quiet),
                ),
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => _export(false),
                    icon: const Icon(Icons.download),
                    label: const Text('Purchases to Excel'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _export(true),
                    icon: const Icon(Icons.download),
                    label: const Text('Sales to Excel'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(String label, String value, String note) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: KadaiColors.quiet,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
          Text(note, style: const TextStyle(color: KadaiColors.quiet)),
        ],
      ),
    ),
  );

  Widget _card(String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );

  Widget _daily(SalesReport r) {
    final max = r.byDay.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // A month has up to 31 bars; show day numbers then.
    final many = r.byDay.length > 7;
    return _card(
      'Sales by day',
      SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in r.byDay)
              Expanded(
                child: Tooltip(
                  message: rupees(d.amount),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: many ? 1.5 : 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!many)
                          // Narrow bars on a phone: the amount shrinks to
                          // fit instead of wrapping.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              rupees(d.amount),
                              maxLines: 1,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Container(
                          height: max == 0 ? 2 : 2 + 120 * d.amount / max,
                          decoration: BoxDecoration(
                            color: KadaiColors.green,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            many ? '${d.day.day}' : names[d.day.weekday - 1],
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 12,
                              color: KadaiColors.quiet,
                            ),
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
    );
  }

  Widget _modes(SalesReport r) {
    const labels = {'CASH': 'Cash · பணம்', 'UPI': 'UPI', 'CARD': 'Card'};
    return _card(
      'How customers paid',
      Column(
        children: [
          if (r.byMode.isEmpty)
            const Text('No sales', style: TextStyle(color: KadaiColors.quiet)),
          for (final e in r.byMode.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(labels[e.key] ?? e.key)),
                      Text(
                        rupees(e.value),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: r.sales == 0 ? 0 : e.value / r.sales,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Who billed how much, on the PC and on each staff phone.
  Widget _staff(DateTime from, DateTime to) {
    final rows = s.reports.byStaff(from, to);
    return _card(
      t('Sales by staff', 'பணியாளர் வாரியாக விற்பனை'),
      rows.isEmpty
          ? const Text('No sales', style: TextStyle(color: KadaiColors.quiet))
          : Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          r.where == 'This PC'
                              ? Icons.computer
                              : Icons.smartphone,
                          size: 20,
                          color: KadaiColors.quiet,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${r.name} · ${r.where == 'This PC' ? t('This PC', 'இந்த கணினி') : r.where}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        Text(
                          '${r.bills} ${t('bills', 'பில்')}',
                          style: const TextStyle(color: KadaiColors.quiet),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          rupees(r.amount),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _top(SalesReport r) => _card(
    'Best selling items',
    r.topItems.isEmpty
        ? const Text('No sales', style: TextStyle(color: KadaiColors.quiet))
        : Column(
            children: [
              for (final (i, t) in r.topItems.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(color: KadaiColors.quiet),
                        ),
                      ),
                      Expanded(child: TwoLang(t.nameEn, t.nameTa)),
                      SizedBox(
                        width: 140,
                        child: Text(
                          '${formatQty(t.quantity)} ${t.unit}',
                          style: const TextStyle(color: KadaiColors.quiet),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          rupees(t.amount),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );
}
