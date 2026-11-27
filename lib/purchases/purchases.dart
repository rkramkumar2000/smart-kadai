import 'package:sqlite3/sqlite3.dart';

import '../catalogue/product.dart';
import '../core/units.dart';
import '../data/shop_repository.dart';

class Supplier {
  Supplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.gstin = '',
    this.address = '',
    this.balance = 0,
  });

  final String id;
  final String name;
  final String phone;
  final String gstin;
  final String address;

  /// Amount the shop owes this supplier.
  final double balance;
}

/// One line of a supplier bill.
class PurchaseLine {
  PurchaseLine({
    required this.product,
    required this.variant,
    required this.count,
    required this.unitCost,
    this.gstPercent = 0,
  });

  final Product product;

  /// Null when bought loose in the product's stock unit.
  final ProductVariant? variant;
  final double count;

  /// Cost of one [variant] (or one stock unit when loose), before GST.
  final double unitCost;
  final double gstPercent;

  double get total =>
      (unitCost * count * (1 + gstPercent / 100) * 100).roundToDouble() / 100;

  /// How much stock goes up, in the product's stock unit.
  double get stockDelta => roundQty(count * (variant?.stockFactor ?? 1));

  /// Cost of one stock unit, used to update the product's purchase price.
  double get costPerStockUnit {
    final f = variant?.stockFactor ?? 1;
    return f == 0 ? unitCost : unitCost / f;
  }

  String get unitLabel => variant?.label ?? product.stockUnit.code;
}

class PurchaseSummary {
  PurchaseSummary({
    required this.id,
    required this.supplierName,
    required this.invoiceNo,
    required this.date,
    required this.total,
    required this.paid,
    required this.itemCount,
    required this.source,
  });

  final String id;
  final String supplierName;
  final String invoiceNo;
  final DateTime date;
  final double total;
  final double paid;
  final int itemCount;
  final String source;

  double get due => total - paid;
}

/// Suppliers, purchases from them and payments to them.
class PurchaseRepository {
  PurchaseRepository(this.shop);

  final ShopRepository shop;
  Database get _db => shop.db;

  // --------------------------------------------------------------- suppliers

  List<Supplier> suppliers() => _db
      .select('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE')
      .map(
        (r) => Supplier(
          id: r['id'] as String,
          name: r['name'] as String,
          phone: r['phone'] as String,
          gstin: r['gstin'] as String,
          address: r['address'] as String,
          balance: (r['balance'] as num).toDouble(),
        ),
      )
      .toList();

  Supplier saveSupplier(Supplier s) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      '''
INSERT INTO suppliers (id, name, phone, gstin, address, balance, created_at, updated_at)
VALUES (?,?,?,?,?,0,?,?)
ON CONFLICT(id) DO UPDATE SET name=excluded.name, phone=excluded.phone,
  gstin=excluded.gstin, address=excluded.address, updated_at=excluded.updated_at
''',
      [
        s.id,
        s.name.trim(),
        s.phone.trim(),
        s.gstin.trim(),
        s.address.trim(),
        now,
        now,
      ],
    );
    return s;
  }

  /// Finds a supplier by GSTIN or by name, for invoice OCR.
  Supplier? findSupplier({String? gstin, String? name}) {
    final all = suppliers();
    if (gstin != null && gstin.trim().isNotEmpty) {
      for (final s in all) {
        if (s.gstin.toUpperCase() == gstin.trim().toUpperCase()) return s;
      }
    }
    if (name != null && name.trim().isNotEmpty) {
      final n = name.trim().toLowerCase();
      for (final s in all) {
        if (s.name.toLowerCase() == n) return s;
      }
    }
    return null;
  }

  // --------------------------------------------------------------- purchases

  /// Saves a supplier bill: stock goes up for every line, the supplier's
  /// balance goes up by what was not paid, and each product's purchase price
  /// is updated to the latest cost when [updateCosts] is true.
  String savePurchase({
    required Supplier supplier,
    required List<PurchaseLine> lines,
    required DateTime invoiceDate,
    String invoiceNo = '',
    double paid = 0,
    String source = 'MANUAL',
    String? imagePath,
    String? userId,
    bool updateCosts = true,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError('A purchase needs at least one line');
    }
    final id = shop.newId();
    final total =
        (lines.fold<double>(0, (s, l) => s + l.total) * 100).roundToDouble() /
        100;
    shop.transaction(() {
      _db.execute(
        '''
INSERT INTO purchases (id, supplier_id, invoice_no, invoice_date, created_at,
  total, paid, source, image_path, user_id)
VALUES (?,?,?,?,?,?,?,?,?,?)''',
        [
          id, supplier.id, invoiceNo.trim(), _day(invoiceDate), //
          DateTime.now().toIso8601String(), total, paid, source, imagePath,
          userId,
        ],
      );
      final stmt = _db.prepare('''
INSERT INTO purchase_items (id, purchase_id, product_id, variant_id, count,
  unit_cost, gst_percent, line_total, stock_delta)
VALUES (?,?,?,?,?,?,?,?,?)''');
      for (final l in lines) {
        stmt.execute([
          shop.newId(), id, l.product.id, l.variant?.id, l.count, //
          l.unitCost, l.gstPercent, l.total, l.stockDelta,
        ]);
        shop.moveStock(
          l.product.id,
          l.stockDelta,
          'PURCHASE',
          id,
          note: invoiceNo,
          userId: userId,
        );
        if (updateCosts && l.unitCost > 0) {
          final withGst = l.costPerStockUnit * (1 + l.gstPercent / 100);
          _db.execute('UPDATE products SET purchase_price = ? WHERE id = ?', [
            _round2(withGst),
            l.product.id,
          ]);
          if (l.variant != null) {
            _db.execute(
              'UPDATE product_variants SET purchase_price = ? WHERE id = ?',
              [_round2(l.unitCost * (1 + l.gstPercent / 100)), l.variant!.id],
            );
          }
        }
      }
      stmt.close();
      _db.execute(
        'UPDATE suppliers SET balance = ROUND(balance + ?, 2), updated_at = ? WHERE id = ?',
        [total - paid, DateTime.now().toIso8601String(), supplier.id],
      );
      if (paid > 0) {
        _db.execute(
          'INSERT INTO supplier_payments (id, supplier_id, amount, mode, note, created_at) VALUES (?,?,?,?,?,?)',
          [
            shop.newId(), supplier.id, paid, 'CASH', //
            'With bill $invoiceNo', DateTime.now().toIso8601String(),
          ],
        );
      }
    });
    return id;
  }

  /// Records money paid to a supplier against what the shop owes.
  void paySupplier(
    String supplierId,
    double amount,
    String mode, {
    String note = '',
  }) {
    if (amount <= 0) return;
    shop.transaction(() {
      _db.execute(
        'INSERT INTO supplier_payments (id, supplier_id, amount, mode, note, created_at) VALUES (?,?,?,?,?,?)',
        [
          shop.newId(),
          supplierId,
          amount,
          mode,
          note,
          DateTime.now().toIso8601String(),
        ],
      );
      _db.execute(
        'UPDATE suppliers SET balance = ROUND(balance - ?, 2), updated_at = ? WHERE id = ?',
        [amount, DateTime.now().toIso8601String(), supplierId],
      );
    });
  }

  List<PurchaseSummary> recentPurchases({int limit = 100}) => _db
      .select(
        '''
SELECT p.*, s.name AS supplier_name,
  (SELECT COUNT(*) FROM purchase_items i WHERE i.purchase_id = p.id) AS n
FROM purchases p JOIN suppliers s ON s.id = p.supplier_id
ORDER BY p.invoice_date DESC, p.created_at DESC LIMIT ?''',
        [limit],
      )
      .map(
        (r) => PurchaseSummary(
          id: r['id'] as String,
          supplierName: r['supplier_name'] as String,
          invoiceNo: r['invoice_no'] as String,
          date: DateTime.parse(r['invoice_date'] as String),
          total: (r['total'] as num).toDouble(),
          paid: (r['paid'] as num).toDouble(),
          itemCount: r['n'] as int,
          source: r['source'] as String,
        ),
      )
      .toList();

  static String _day(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String();
  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}
