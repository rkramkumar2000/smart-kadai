import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../billing/bill.dart';
import '../catalogue/product.dart';
import '../core/units.dart';
import 'database.dart';
import 'seed.dart';

/// Reads and writes products, voice aliases and bills in the local database.
class ShopRepository {
  ShopRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;
  static const _uuid = Uuid();

  String newId() => _uuid.v4();

  /// Loads the starter catalogue on first run.
  void seedIfEmpty() {
    final n =
        _db.select('SELECT COUNT(*) AS n FROM products').first['n'] as int;
    if (n > 0) return;
    for (final p in starterCatalogue(DateTime.now())) {
      saveProduct(p);
    }
  }

  // ---------------------------------------------------------------- products

  List<Product> loadProducts() {
    final variants = <String, List<ProductVariant>>{};
    for (final r in _db.select(
      'SELECT * FROM product_variants ORDER BY product_id, sort, quantity',
    )) {
      variants
          .putIfAbsent(r['product_id'] as String, () => [])
          .add(
            ProductVariant(
              id: r['id'] as String,
              productId: r['product_id'] as String,
              unit: Unit.fromCode(r['unit'] as String),
              quantity: (r['quantity'] as num).toDouble(),
              stockFactor: (r['stock_factor'] as num).toDouble(),
              sellingPrice: (r['selling_price'] as num).toDouble(),
              purchasePrice: (r['purchase_price'] as num).toDouble(),
              barcode: r['barcode'] as String?,
              isDefault: (r['is_default'] as int) == 1,
              sort: r['sort'] as int,
            ),
          );
    }
    return _db
        .select('SELECT * FROM products ORDER BY name_en COLLATE NOCASE')
        .map(
          (r) => Product(
            id: r['id'] as String,
            code: r['code'] as String,
            nameEn: r['name_en'] as String,
            nameTa: r['name_ta'] as String,
            nameTanglish: r['name_tanglish'] as String,
            category: r['category'] as String,
            brand: r['brand'] as String,
            description: r['description'] as String,
            barcode: r['barcode'] as String?,
            purchasePrice: (r['purchase_price'] as num).toDouble(),
            sellingPrice: (r['selling_price'] as num).toDouble(),
            minStock: (r['min_stock'] as num).toDouble(),
            stockUnit: Unit.fromCode(r['stock_unit'] as String),
            stockQty: (r['stock_qty'] as num).toDouble(),
            status: ProductStatus.fromCode(r['status'] as String),
            createdAt: DateTime.parse(r['created_at'] as String),
            updatedAt: DateTime.parse(r['updated_at'] as String),
            variants: variants[r['id']] ?? const [],
          ),
        )
        .toList();
  }

  /// Next free product ID such as P0016.
  String nextProductCode() {
    final rows = _db.select(
      "SELECT code FROM products WHERE code GLOB 'P[0-9]*' ORDER BY length(code) DESC, code DESC LIMIT 1",
    );
    final last = rows.isEmpty
        ? 0
        : int.tryParse((rows.first['code'] as String).substring(1)) ?? 0;
    return 'P${(last + 1).toString().padLeft(4, '0')}';
  }

  /// Inserts or updates a product and replaces its variants.
  void saveProduct(Product p) {
    _transaction(() {
      _db.execute(
        '''
INSERT INTO products (id, code, name_en, name_ta, name_tanglish, category,
  brand, description, barcode, purchase_price, selling_price, min_stock,
  stock_unit, stock_qty, status, created_at, updated_at)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  code=excluded.code, name_en=excluded.name_en, name_ta=excluded.name_ta,
  name_tanglish=excluded.name_tanglish, category=excluded.category,
  brand=excluded.brand, description=excluded.description,
  barcode=excluded.barcode, purchase_price=excluded.purchase_price,
  selling_price=excluded.selling_price, min_stock=excluded.min_stock,
  stock_unit=excluded.stock_unit, status=excluded.status,
  updated_at=excluded.updated_at
''',
        [
          p.id, p.code, p.nameEn, p.nameTa, p.nameTanglish, p.category, //
          p.brand, p.description, _blankToNull(p.barcode), p.purchasePrice,
          p.sellingPrice, p.minStock, p.stockUnit.code, p.stockQty,
          p.status.code, p.createdAt.toIso8601String(),
          p.updatedAt.toIso8601String(),
        ],
      );
      final keep = p.variants.map((v) => v.id).toList();
      if (keep.isEmpty) {
        _db.execute('DELETE FROM product_variants WHERE product_id = ?', [
          p.id,
        ]);
      } else {
        _db.execute(
          'DELETE FROM product_variants WHERE product_id = ? AND id NOT IN (${List.filled(keep.length, '?').join(',')})',
          [p.id, ...keep],
        );
      }
      final stmt = _db.prepare('''
INSERT INTO product_variants (id, product_id, unit, quantity, stock_factor,
  selling_price, purchase_price, barcode, is_default, sort)
VALUES (?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET unit=excluded.unit, quantity=excluded.quantity,
  stock_factor=excluded.stock_factor, selling_price=excluded.selling_price,
  purchase_price=excluded.purchase_price, barcode=excluded.barcode,
  is_default=excluded.is_default, sort=excluded.sort
''');
      for (final v in p.variants) {
        stmt.execute([
          v.id, p.id, v.unit.code, v.quantity, v.stockFactor, //
          v.sellingPrice, v.purchasePrice, _blankToNull(v.barcode),
          v.isDefault ? 1 : 0, v.sort,
        ]);
      }
      stmt.close();
    });
  }

  /// Sets the stock of a product and records why.
  void adjustStock(String productId, double delta, String reason) {
    _transaction(() => _moveStock(productId, delta, reason, null));
  }

  /// True when another product or variant already uses [barcode].
  bool barcodeInUse(String barcode, {String? exceptProductId}) {
    final rows = _db.select(
      '''
SELECT id FROM products WHERE barcode = ? AND id IS NOT ?
UNION SELECT product_id FROM product_variants WHERE barcode = ? AND product_id IS NOT ?
''',
      [barcode, exceptProductId, barcode, exceptProductId],
    );
    return rows.isNotEmpty;
  }

  // ----------------------------------------------------------- voice aliases

  Map<String, String> loadAliases() => {
    for (final r in _db.select(
      'SELECT phrase_key, product_id FROM voice_aliases',
    ))
      r['phrase_key'] as String: r['product_id'] as String,
  };

  void saveAlias(String phraseKey, String productId) {
    if (phraseKey.trim().isEmpty) return;
    _db.execute(
      '''
INSERT INTO voice_aliases (phrase_key, product_id, hits, updated_at)
VALUES (?, ?, 1, ?)
ON CONFLICT(phrase_key) DO UPDATE SET product_id=excluded.product_id,
  hits=voice_aliases.hits + 1, updated_at=excluded.updated_at
''',
      [phraseKey, productId, DateTime.now().toIso8601String()],
    );
  }

  // ------------------------------------------------------------------ sales

  /// Saves the bill and lowers stock for every line, all or nothing.
  /// Returns the bill number.
  int saveSale(Bill bill, PaymentMode mode) {
    late int billNo;
    _transaction(() {
      final last = _db.select('SELECT MAX(bill_no) AS n FROM sales').first['n'];
      billNo = ((last as int?) ?? 0) + 1;
      final saleId = newId();
      final now = DateTime.now().toIso8601String();
      _db.execute(
        'INSERT INTO sales (id, bill_no, created_at, total, payment_mode) VALUES (?,?,?,?,?)',
        [saleId, billNo, now, bill.total, mode.code],
      );
      final stmt = _db.prepare('''
INSERT INTO sale_items (id, sale_id, product_id, variant_id, count,
  unit_price, line_total, stock_delta, entered_by, spoken_text)
VALUES (?,?,?,?,?,?,?,?,?,?)''');
      for (final l in bill.lines) {
        stmt.execute([
          newId(), saleId, l.product.id, l.variant?.id, l.count, //
          l.unitPrice, l.total, l.stockDelta, l.enteredBy.name, l.spokenText,
        ]);
        _moveStock(l.product.id, -l.stockDelta, 'SALE', saleId);
      }
      stmt.close();
    });
    return billNo;
  }

  ({int bills, double total}) todaySummary() {
    final start = DateTime.now();
    final day = DateTime(start.year, start.month, start.day).toIso8601String();
    final r = _db.select(
      'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS t FROM sales WHERE created_at >= ?',
      [day],
    ).first;
    return (bills: r['n'] as int, total: (r['t'] as num).toDouble());
  }

  // ---------------------------------------------------------------- helpers

  void _moveStock(String productId, double delta, String type, String? ref) {
    _db.execute(
      'UPDATE products SET stock_qty = ROUND(stock_qty + ?, 4), updated_at = ? WHERE id = ?',
      [delta, DateTime.now().toIso8601String(), productId],
    );
    _db.execute(
      'INSERT INTO stock_movements (id, product_id, delta, type, ref_id, created_at) VALUES (?,?,?,?,?,?)',
      [newId(), productId, delta, type, ref, DateTime.now().toIso8601String()],
    );
  }

  void _transaction(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  static String? _blankToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
