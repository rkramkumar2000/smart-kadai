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

  /// The database wrapper, for repositories that need their own queries.
  AppDatabase get dbHandle => _appDb;

  /// The raw database, for the other repositories that share it.
  Database get db => _appDb.db;
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
    transaction(() {
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

  /// Changes stock by [delta] and records why ("Spoiled", "Counted again").
  void adjustStock(
    String productId,
    double delta,
    String reason, {
    String? userId,
  }) {
    transaction(
      () => moveStock(
        productId,
        delta,
        'CORRECTION',
        null,
        note: reason,
        userId: userId,
      ),
    );
  }

  /// Stock changes for one product, newest first.
  List<StockMovement> stockHistory(String productId, {int limit = 100}) => _db
      .select(
        'SELECT * FROM stock_movements WHERE product_id = ? ORDER BY created_at DESC LIMIT ?',
        [productId, limit],
      )
      .map(
        (r) => StockMovement(
          delta: (r['delta'] as num).toDouble(),
          type: r['type'] as String,
          note: r['note'] as String,
          at: DateTime.parse(r['created_at'] as String),
        ),
      )
      .toList();

  // --------------------------------------------------------------- settings

  String setting(String key, [String fallback = '']) {
    final r = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? fallback : r.first['value'] as String;
  }

  void setSetting(String key, String value) => _db.execute(
    'INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );

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

  // -------------------------------------------------------------- voice log

  void logVoice({
    required String service,
    required String heard,
    required List<String> alternatives,
    required String usedText,
    required int sure,
    required int unsure,
    required String result,
  }) {
    _db.execute(
      '''
INSERT INTO voice_log (id, created_at, service, heard, alternatives,
  used_text, sure_items, unsure_items, result)
VALUES (?,?,?,?,?,?,?,?,?)''',
      [
        newId(), DateTime.now().toIso8601String(), service, heard, //
        alternatives.join(' | '), usedText, sure, unsure, result,
      ],
    );
  }

  /// Recent voice phrases, newest first.
  List<Map<String, Object?>> recentVoiceLog({int limit = 200}) => _db
      .select('SELECT * FROM voice_log ORDER BY created_at DESC LIMIT ?', [
        limit,
      ])
      .map((r) => Map<String, Object?>.from(r))
      .toList();

  // ------------------------------------------------------------------ sales

  /// Saves the bill and lowers stock for every line, all or nothing.
  /// Returns the bill number.
  int saveSale(Bill bill, PaymentMode mode, {String? userId}) {
    late int billNo;
    transaction(() {
      final last = _db.select('SELECT MAX(bill_no) AS n FROM sales').first['n'];
      billNo = ((last as int?) ?? 0) + 1;
      final saleId = newId();
      final now = DateTime.now().toIso8601String();
      _db.execute(
        'INSERT INTO sales (id, bill_no, created_at, total, payment_mode, user_id, customer_id, discount) VALUES (?,?,?,?,?,?,?,?)',
        [
          saleId, billNo, now, bill.total, mode.code, userId, //
          bill.customerId, bill.discount,
        ],
      );
      if (mode == PaymentMode.credit) {
        if (bill.customerId == null) {
          throw StateError('A credit bill needs a customer');
        }
        _db.execute(
          'UPDATE customers SET balance = ROUND(balance + ?, 2), updated_at = ? WHERE id = ?',
          [bill.total, now, bill.customerId],
        );
      }
      final stmt = _db.prepare('''
INSERT INTO sale_items (id, sale_id, product_id, variant_id, count,
  unit_price, line_total, stock_delta, entered_by, spoken_text, cost_total)
VALUES (?,?,?,?,?,?,?,?,?,?,?)''');
      for (final l in bill.lines) {
        stmt.execute([
          newId(), saleId, l.product.id, l.variant?.id, l.count, //
          l.unitPrice, l.total, l.stockDelta, l.enteredBy.name, l.spokenText,
          l.costTotal,
        ]);
        moveStock(l.product.id, -l.stockDelta, 'SALE', saleId, userId: userId);
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

  /// Changes a product's stock and records the change. Call inside
  /// [transaction].
  void moveStock(
    String productId,
    double delta,
    String type,
    String? ref, {
    String note = '',
    String? userId,
  }) {
    final at = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE products SET stock_qty = ROUND(stock_qty + ?, 4), updated_at = ? WHERE id = ?',
      [delta, at, productId],
    );
    _db.execute(
      'INSERT INTO stock_movements (id, product_id, delta, type, ref_id, created_at, note, user_id) VALUES (?,?,?,?,?,?,?,?)',
      [newId(), productId, delta, type, ref, at, note, userId],
    );
  }

  /// Runs [body] so that all its writes are saved together or not at all.
  void transaction(void Function() body) {
    // Already inside a transaction: the outer one commits or rolls back.
    if (!_db.autocommit) {
      body();
      return;
    }
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

class StockMovement {
  StockMovement({
    required this.delta,
    required this.type,
    required this.note,
    required this.at,
  });
  final double delta;
  final String type;
  final String note;
  final DateTime at;
}
