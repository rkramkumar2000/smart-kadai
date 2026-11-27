import 'package:sqlite3/sqlite3.dart';

import '../data/shop_repository.dart';

enum ReportPeriod {
  today('Today', 'இன்று'),
  week('Last 7 days', '7 நாள்'),
  month('This month', 'இந்த மாதம்');

  const ReportPeriod(this.label, this.tamil);
  final String label;
  final String tamil;

  /// Start (inclusive) and end (exclusive) of the period around [now].
  (DateTime, DateTime) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1));
    return switch (this) {
      ReportPeriod.today => (today, end),
      ReportPeriod.week => (today.subtract(const Duration(days: 6)), end),
      ReportPeriod.month => (DateTime(now.year, now.month, 1), end),
    };
  }
}

class ItemSales {
  ItemSales(this.nameEn, this.nameTa, this.amount, this.quantity, this.unit);
  final String nameEn;
  final String nameTa;
  final double amount;
  final double quantity;
  final String unit;
}

/// Bills made by one staff member on one counter (the PC or a phone).
class StaffSales {
  StaffSales(this.name, this.where, this.bills, this.amount);
  final String name;

  /// "This PC" or the phone's name.
  final String where;
  final int bills;
  final double amount;
}

class DaySales {
  DaySales(this.day, this.amount);
  final DateTime day;
  final double amount;
}

class SalesReport {
  SalesReport({
    required this.from,
    required this.to,
    required this.sales,
    required this.cost,
    required this.bills,
    required this.byMode,
    required this.byDay,
    required this.topItems,
    required this.purchases,
    required this.purchaseBills,
    required this.supplierDue,
    required this.voiceShare,
    this.expenses = 0,
    this.discounts = 0,
    this.customerDue = 0,
  });

  final DateTime from;
  final DateTime to;
  final double sales;
  final double cost;
  final int bills;
  final Map<String, double> byMode;
  final List<DaySales> byDay;
  final List<ItemSales> topItems;
  final double purchases;
  final int purchaseBills;

  /// What the shop owes all suppliers today.
  final double supplierDue;

  /// Share of bill lines entered by voice, 0 to 1.
  final double voiceShare;

  /// Rent, electricity, salary and other running costs in the period.
  final double expenses;

  /// Discounts given on bills in the period.
  final double discounts;

  /// What all customers owe the shop today (credit book).
  final double customerDue;

  /// Sales minus what the goods cost.
  double get profit => sales - cost;

  /// Profit after running costs.
  double get netProfit => profit - expenses;
}

/// Sales and purchase figures for the Reports screen and Excel export.
class ReportRepository {
  ReportRepository(this.shop);

  final ShopRepository shop;
  Database get _db => shop.db;

  SalesReport build(DateTime from, DateTime to) {
    final f = from.toIso8601String(), t = to.toIso8601String();
    final head = _db.select(
      'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS s FROM sales WHERE created_at >= ? AND created_at < ?',
      [f, t],
    ).first;
    final cost = _db
        .select(
          '''
SELECT COALESCE(SUM(i.cost_total),0) AS c,
  COALESCE(SUM(CASE WHEN i.entered_by = 'voice' THEN 1 ELSE 0 END),0) AS v,
  COUNT(i.id) AS lines
FROM sale_items i JOIN sales s ON s.id = i.sale_id
WHERE s.created_at >= ? AND s.created_at < ?''',
          [f, t],
        )
        .first;
    final modes = {
      for (final r in _db.select(
        'SELECT payment_mode, SUM(total) AS s FROM sales WHERE created_at >= ? AND created_at < ? GROUP BY payment_mode',
        [f, t],
      ))
        r['payment_mode'] as String: (r['s'] as num).toDouble(),
    };
    final days = <DateTime, double>{};
    for (var d = from; d.isBefore(to); d = d.add(const Duration(days: 1))) {
      days[DateTime(d.year, d.month, d.day)] = 0;
    }
    for (final r in _db.select(
      'SELECT substr(created_at,1,10) AS d, SUM(total) AS s FROM sales WHERE created_at >= ? AND created_at < ? GROUP BY d',
      [f, t],
    )) {
      final d = DateTime.parse(r['d'] as String);
      days[DateTime(d.year, d.month, d.day)] = (r['s'] as num).toDouble();
    }
    final top = _db
        .select(
          '''
SELECT p.name_en, p.name_ta, p.stock_unit, SUM(i.line_total) AS amt, SUM(i.stock_delta) AS qty
FROM sale_items i JOIN sales s ON s.id = i.sale_id JOIN products p ON p.id = i.product_id
WHERE s.created_at >= ? AND s.created_at < ?
GROUP BY i.product_id ORDER BY amt DESC LIMIT 10''',
          [f, t],
        )
        .map(
          (r) => ItemSales(
            r['name_en'] as String,
            r['name_ta'] as String,
            (r['amt'] as num).toDouble(),
            (r['qty'] as num).toDouble(),
            r['stock_unit'] as String,
          ),
        )
        .toList();
    final buy = _db.select(
      'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS s FROM purchases WHERE invoice_date >= ? AND invoice_date < ?',
      [f, t],
    ).first;
    final due = _db
        .select('SELECT COALESCE(SUM(balance),0) AS b FROM suppliers')
        .first['b'];
    final lines = cost['lines'] as int;
    final exp = _db.select(
      'SELECT COALESCE(SUM(amount),0) AS t FROM expenses WHERE day >= ? AND day < ?',
      [f, t],
    ).first['t'];
    final disc = _db.select(
      'SELECT COALESCE(SUM(discount),0) AS d FROM sales WHERE created_at >= ? AND created_at < ?',
      [f, t],
    ).first['d'];
    final owed = _db
        .select(
          'SELECT COALESCE(SUM(balance),0) AS b FROM customers WHERE balance > 0',
        )
        .first['b'];
    return SalesReport(
      from: from,
      to: to,
      sales: (head['s'] as num).toDouble(),
      cost: (cost['c'] as num).toDouble(),
      bills: head['n'] as int,
      byMode: modes,
      byDay: [for (final e in days.entries) DaySales(e.key, e.value)],
      topItems: top,
      purchases: (buy['s'] as num).toDouble(),
      purchaseBills: buy['n'] as int,
      supplierDue: (due as num).toDouble(),
      voiceShare: lines == 0 ? 0 : (cost['v'] as num) / lines,
      expenses: (exp as num).toDouble(),
      discounts: (disc as num).toDouble(),
      customerDue: (owed as num).toDouble(),
    );
  }

  /// Sales by who billed and on which counter, biggest first.
  List<StaffSales> byStaff(DateTime from, DateTime to) => [
    for (final r in _db.select(
      '''
SELECT COALESCE(u.name, '-') AS name, COALESCE(d.name, 'This PC') AS dev,
  COUNT(*) AS n, COALESCE(SUM(s.total),0) AS t
FROM sales s LEFT JOIN users u ON u.id = s.user_id
LEFT JOIN devices d ON d.id = s.device_id
WHERE s.created_at >= ? AND s.created_at < ?
GROUP BY s.user_id, s.device_id ORDER BY t DESC''',
      [from.toIso8601String(), to.toIso8601String()],
    ))
      StaffSales(
        r['name'] as String,
        r['dev'] as String,
        r['n'] as int,
        (r['t'] as num).toDouble(),
      ),
  ];

  /// Every sale line in the period as CSV, which opens in Excel.
  String salesCsv(DateTime from, DateTime to) {
    final rows = _db.select(
      '''
SELECT s.bill_no, s.created_at, s.payment_mode, p.code, p.name_en, p.name_ta,
  COALESCE(v.quantity || ' ' || v.unit, p.stock_unit || ' loose') AS size,
  i.count, i.unit_price, i.line_total, i.cost_total, i.entered_by
FROM sale_items i JOIN sales s ON s.id = i.sale_id
JOIN products p ON p.id = i.product_id
LEFT JOIN product_variants v ON v.id = i.variant_id
WHERE s.created_at >= ? AND s.created_at < ?
ORDER BY s.bill_no''',
      [from.toIso8601String(), to.toIso8601String()],
    );
    final out = StringBuffer(
      'Bill no,Date,Payment,Product ID,Product,Tamil name,Size,Quantity,Rate,Amount,Cost,Entered by\n',
    );
    for (final r in rows) {
      out.writeln(
        [
          r['bill_no'],
          (r['created_at'] as String)
              .replaceFirst('T', ' ')
              .substring(0, 16), //
          r['payment_mode'], r['code'], r['name_en'], r['name_ta'], r['size'],
          r['count'], r['unit_price'], r['line_total'], r['cost_total'],
          r['entered_by'],
        ].map(_csv).join(','),
      );
    }
    return out.toString();
  }

  /// Every purchase line in the period as CSV.
  String purchasesCsv(DateTime from, DateTime to) {
    final rows = _db.select(
      '''
SELECT pu.invoice_date, su.name AS supplier, pu.invoice_no, p.code, p.name_en,
  COALESCE(v.quantity || ' ' || v.unit, p.stock_unit) AS size,
  i.count, i.unit_cost, i.gst_percent, i.line_total
FROM purchase_items i JOIN purchases pu ON pu.id = i.purchase_id
JOIN suppliers su ON su.id = pu.supplier_id
JOIN products p ON p.id = i.product_id
LEFT JOIN product_variants v ON v.id = i.variant_id
WHERE pu.invoice_date >= ? AND pu.invoice_date < ?
ORDER BY pu.invoice_date''',
      [from.toIso8601String(), to.toIso8601String()],
    );
    final out = StringBuffer(
      'Date,Supplier,Bill no,Product ID,Product,Size,Quantity,Cost,GST %,Amount\n',
    );
    for (final r in rows) {
      out.writeln(
        [
          (r['invoice_date'] as String).substring(0, 10), r['supplier'], //
          r['invoice_no'], r['code'], r['name_en'], r['size'], r['count'],
          r['unit_cost'], r['gst_percent'], r['line_total'],
        ].map(_csv).join(','),
      );
    }
    return out.toString();
  }

  static String _csv(Object? v) {
    final s = '${v ?? ''}';
    return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }
}
