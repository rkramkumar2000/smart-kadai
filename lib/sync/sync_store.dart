import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import '../data/shop_repository.dart';

/// The database side of billing from many phones through the shop PC.
///
/// The PC keeps the one true copy of products, stock, customers and staff.
/// A phone keeps a copy of those (a "snapshot") so it can bill without
/// Wi-Fi, and sends what it does (bills, new products, customers and
/// payments) to the PC through its outbox.
class SyncStore {
  SyncStore(this.repo);

  final ShopRepository repo;
  Database get _db => repo.db;

  /// Settings a phone takes from the PC. The phone keeps its own screen and
  /// voice choices (language, text size, hold to speak).
  static const sharedSettings = [
    'shop_name', 'shop_address', 'shop_phone', 'shop_gstin', 'bill_footer', //
    'upi_id', 'bill_paper',
  ];

  List<Map<String, Object?>> _rows(
    String sql, [
    List<Object?> args = const [],
  ]) => [for (final r in _db.select(sql, args)) Map<String, Object?>.from(r)];

  final _columnCache = <String, List<String>>{};
  List<String> _columns(String table) => _columnCache.putIfAbsent(
    table,
    () => [
      for (final r in _db.select('PRAGMA table_info($table)'))
        r['name'] as String,
    ],
  );

  /// Inserts [row], or updates it when its id is already there. Columns in
  /// [keep] are not changed on update.
  void _upsert(
    String table,
    Map<String, Object?> row, {
    Set<String> keep = const {},
    String key = 'id',
  }) {
    final cols = [
      for (final c in _columns(table))
        if (row.containsKey(c)) c,
    ];
    final updates = [
      for (final c in cols)
        if (c != key && !keep.contains(c)) '$c=excluded.$c',
    ];
    _db.execute(
      'INSERT INTO $table (${cols.join(',')}) VALUES (${List.filled(cols.length, '?').join(',')})'
      ' ON CONFLICT($key) DO ${updates.isEmpty ? 'NOTHING' : 'UPDATE SET ${updates.join(',')}'}',
      [for (final c in cols) row[c]],
    );
  }

  bool _exists(String table, String id, {String key = 'id'}) =>
      _db.select('SELECT 1 FROM $table WHERE $key = ?', [id]).isNotEmpty;

  // =================================================================== PC

  /// Everything a phone needs to bill: products, sizes, customers, staff
  /// logins, learned voice words and the shop's bill details.
  Map<String, Object?> snapshot() => {
    'products': _rows('SELECT * FROM products'),
    'product_variants': _rows('SELECT * FROM product_variants'),
    'customers': _rows('SELECT * FROM customers'),
    'users': _rows('SELECT * FROM users'),
    'voice_aliases': _rows('SELECT * FROM voice_aliases'),
    'settings': {for (final k in sharedSettings) k: repo.setting(k)},
  };

  /// Saves a bill sent by a phone, lowers stock and adds credit to the
  /// customer's account. The PC gives it the next bill number. Sending the
  /// same bill twice saves it once. Returns the PC's bill number.
  int receiveSale(Map<String, Object?> payload, String deviceId) {
    final sale = Map<String, Object?>.from(payload['sale'] as Map);
    final items = [
      for (final i in payload['items'] as List)
        Map<String, Object?>.from(i as Map),
    ];
    final id = sale['id'] as String;
    final had = _db.select('SELECT bill_no FROM sales WHERE id = ?', [id]);
    if (had.isNotEmpty) return had.first['bill_no'] as int;
    for (final i in items) {
      if (!_exists('products', i['product_id'] as String)) {
        throw StateError('Unknown product ${i['product_id']}');
      }
      final v = i['variant_id'] as String?;
      if (v != null && !_exists('product_variants', v)) i['variant_id'] = null;
    }
    late int billNo;
    repo.transaction(() {
      final c = payload['customer'];
      if (c is Map) _receiveCustomerRow(Map<String, Object?>.from(c));
      final cid = sale['customer_id'] as String?;
      if (cid != null && !_exists('customers', cid)) sale['customer_id'] = null;
      final last = _db.select('SELECT MAX(bill_no) AS n FROM sales').first['n'];
      billNo = ((last as int?) ?? 0) + 1;
      sale
        ..['device_bill_no'] = sale['bill_no']
        ..['bill_no'] = billNo
        ..['device_id'] = deviceId
        ..['pc_bill_no'] = null;
      _upsert('sales', sale);
      final userId = sale['user_id'] as String?;
      for (final i in items) {
        i['sale_id'] = id;
        _upsert('sale_items', i);
        repo.moveStock(
          i['product_id'] as String,
          -((i['stock_delta'] as num).toDouble()),
          'SALE',
          id,
          userId: userId,
        );
      }
      if (sale['payment_mode'] == 'CREDIT' && sale['customer_id'] != null) {
        _db.execute(
          'UPDATE customers SET balance = ROUND(balance + ?, 2), updated_at = ? WHERE id = ?',
          [sale['total'], sale['created_at'], sale['customer_id']],
        );
      }
    });
    return billNo;
  }

  /// A product added or changed on a phone. The PC's stock count is kept.
  /// A new product whose code the PC already uses gets the next free code.
  /// Returns the product's code on the PC.
  String receiveProduct(Map<String, Object?> payload) {
    final p = Map<String, Object?>.from(payload['product'] as Map);
    final id = p['id'] as String;
    repo.transaction(() {
      if (!_exists('products', id)) {
        final clash = _db.select(
          'SELECT 1 FROM products WHERE code = ? AND id <> ?',
          [p['code'], id],
        );
        if (clash.isNotEmpty) p['code'] = repo.nextProductCode();
      }
      _upsert('products', p, keep: {'stock_qty', 'created_at'});
      final variants = [
        for (final v in payload['variants'] as List)
          Map<String, Object?>.from(v as Map),
      ];
      for (final v in variants) {
        _upsert('product_variants', v);
      }
      final keep = {for (final v in variants) v['id']};
      for (final r in _db.select(
        'SELECT id FROM product_variants WHERE product_id = ?',
        [id],
      )) {
        if (keep.contains(r['id'])) continue;
        try {
          _db.execute('DELETE FROM product_variants WHERE id = ?', [r['id']]);
        } on SqliteException {
          // Still on old bills: kept.
        }
      }
    });
    return _db.select('SELECT code FROM products WHERE id = ?', [
          id,
        ]).first['code']
        as String;
  }

  void _receiveCustomerRow(Map<String, Object?> c) {
    // What a customer owes is counted on the PC from bills and payments.
    if (_exists('customers', c['id'] as String)) {
      _upsert('customers', c, keep: {'balance', 'created_at'});
    } else {
      _upsert('customers', {...c, 'balance': 0});
    }
  }

  void receiveCustomer(Map<String, Object?> payload) => _receiveCustomerRow(
    Map<String, Object?>.from(payload['customer'] as Map),
  );

  /// Money a customer paid at a phone.
  void receivePayment(Map<String, Object?> payload) {
    final p = Map<String, Object?>.from(payload['payment'] as Map);
    if (_exists('customer_payments', p['id'] as String)) return;
    repo.transaction(() {
      final c = payload['customer'];
      if (c is Map) _receiveCustomerRow(Map<String, Object?>.from(c));
      if (!_exists('customers', p['customer_id'] as String)) {
        throw StateError('Unknown customer');
      }
      _upsert('customer_payments', p);
      _db.execute(
        'UPDATE customers SET balance = ROUND(balance - ?, 2), updated_at = ? WHERE id = ?',
        [p['amount'], p['created_at'], p['customer_id']],
      );
    });
  }

  // ------------------------------------------------------------- devices

  /// Adds a phone and returns its id and secret token.
  ({String id, String token}) addDevice(String name) {
    final rnd = Random.secure();
    final token = List.generate(
      32,
      (_) => rnd.nextInt(16).toRadixString(16),
    ).join();
    final id = repo.newId();
    _db.execute(
      'INSERT INTO devices (id, name, token, paired_at, active) VALUES (?,?,?,?,1)',
      [
        id,
        name.trim().isEmpty ? 'Phone' : name.trim(),
        token,
        DateTime.now().toIso8601String(),
      ],
    );
    return (id: id, token: token);
  }

  /// The phone holding [token], or null when unknown or removed.
  ({String id, String name})? deviceFor(String token) {
    if (token.isEmpty) return null;
    final r = _db.select(
      'SELECT id, name FROM devices WHERE token = ? AND active = 1',
      [token],
    );
    if (r.isEmpty) return null;
    _db.execute('UPDATE devices SET last_seen = ? WHERE id = ?', [
      DateTime.now().toIso8601String(),
      r.first['id'],
    ]);
    return (id: r.first['id'] as String, name: r.first['name'] as String);
  }

  List<PairedPhone> devices() {
    final day = DateTime.now();
    final start = DateTime(day.year, day.month, day.day).toIso8601String();
    return [
      for (final r in _db.select(
        '''
SELECT d.*, (SELECT COUNT(*) FROM sales s WHERE s.device_id = d.id AND s.created_at >= ?) AS bills,
  (SELECT COALESCE(SUM(total),0) FROM sales s WHERE s.device_id = d.id AND s.created_at >= ?) AS total
FROM devices d WHERE d.active = 1 ORDER BY d.paired_at''',
        [start, start],
      ))
        PairedPhone(
          id: r['id'] as String,
          name: r['name'] as String,
          lastSeen: r['last_seen'] == null
              ? null
              : DateTime.parse(r['last_seen'] as String),
          billsToday: r['bills'] as int,
          salesToday: (r['total'] as num).toDouble(),
        ),
    ];
  }

  /// The phone can no longer send bills. Its bills stay in the reports.
  void removeDevice(String id) =>
      _db.execute('UPDATE devices SET active = 0 WHERE id = ?', [id]);

  // ================================================================ phone

  /// Puts the PC's products, customers, staff and bill details on the
  /// phone. Products and staff the PC no longer has stop selling or
  /// logging in; nothing on old bills is deleted.
  void applySnapshot(Map<String, Object?> snap) {
    List<Map<String, Object?>> rows(String k) => [
      for (final r in (snap[k] as List? ?? const []))
        Map<String, Object?>.from(r as Map),
    ];
    repo.transaction(() {
      final products = rows('products');
      for (final p in products) {
        // Codes are unique: move a clashing local code out of the way.
        _db.execute(
          "UPDATE products SET code = code || '-' || substr(id,1,4) WHERE code = ? AND id <> ?",
          [p['code'], p['id']],
        );
        _upsert('products', p);
      }
      final ids = {for (final p in products) p['id']};
      for (final r in _db.select('SELECT id FROM products')) {
        if (!ids.contains(r['id'])) {
          _db.execute("UPDATE products SET status = 'INACTIVE' WHERE id = ?", [
            r['id'],
          ]);
        }
      }
      final variants = rows('product_variants');
      for (final v in variants) {
        _upsert('product_variants', v);
      }
      final vids = {for (final v in variants) v['id']};
      for (final r in _db.select('SELECT id FROM product_variants')) {
        if (vids.contains(r['id'])) continue;
        try {
          _db.execute('DELETE FROM product_variants WHERE id = ?', [r['id']]);
        } on SqliteException {
          // On a bill still waiting to be sent: kept.
        }
      }
      for (final c in rows('customers')) {
        _upsert('customers', c);
      }
      final users = rows('users');
      for (final u in users) {
        _upsert('users', u);
      }
      final uids = {for (final u in users) u['id']};
      for (final r in _db.select('SELECT id FROM users')) {
        if (!uids.contains(r['id'])) {
          _db.execute('UPDATE users SET active = 0 WHERE id = ?', [r['id']]);
        }
      }
      for (final a in rows('voice_aliases')) {
        if (_exists('products', a['product_id'] as String)) {
          _upsert('voice_aliases', a, key: 'phrase_key');
        }
      }
      final settings = snap['settings'];
      if (settings is Map) {
        settings.forEach((k, v) => repo.setSetting('$k', '$v'));
      }
      repo.setSetting('setup_done', '1');
    });
  }

  // -------------------------------------------------------------- outbox

  void queue(String kind, String refId) {
    // A product or customer changed twice is sent once, as it is now.
    if (kind != 'sale' && kind != 'customer_payment') {
      _db.execute('DELETE FROM sync_outbox WHERE kind = ? AND ref_id = ?', [
        kind,
        refId,
      ]);
    }
    _db.execute(
      'INSERT INTO sync_outbox (id, kind, ref_id, created_at) VALUES (?,?,?,?)',
      [repo.newId(), kind, refId, DateTime.now().toIso8601String()],
    );
  }

  /// What still has to go to the PC, oldest first.
  List<({String id, String kind, String refId})> outbox() => [
    for (final r in _db.select(
      'SELECT * FROM sync_outbox ORDER BY created_at, rowid',
    ))
      (
        id: r['id'] as String,
        kind: r['kind'] as String,
        refId: r['ref_id'] as String,
      ),
  ];

  int get waiting =>
      _db.select('SELECT COUNT(*) AS n FROM sync_outbox').first['n'] as int;

  /// Bills still to be sent.
  int get waitingBills =>
      _db
              .select(
                "SELECT COUNT(*) AS n FROM sync_outbox WHERE kind = 'sale'",
              )
              .first['n']
          as int;

  void sent(String outboxId) =>
      _db.execute('DELETE FROM sync_outbox WHERE id = ?', [outboxId]);

  void failed(String outboxId, String error) => _db.execute(
    'UPDATE sync_outbox SET tries = tries + 1, last_error = ? WHERE id = ?',
    [error, outboxId],
  );

  /// What to send to the PC for one outbox item, or null when the thing
  /// it points to is gone.
  Map<String, Object?>? payload(String kind, String refId) {
    Map<String, Object?>? one(String sql, String id) {
      final r = _rows(sql, [id]);
      return r.isEmpty ? null : r.first;
    }

    switch (kind) {
      case 'sale':
        final sale = one('SELECT * FROM sales WHERE id = ?', refId);
        if (sale == null) return null;
        final cid = sale['customer_id'] as String?;
        return {
          'sale': sale,
          'items': _rows('SELECT * FROM sale_items WHERE sale_id = ?', [refId]),
          'customer': cid == null
              ? null
              : one('SELECT * FROM customers WHERE id = ?', cid),
        };
      case 'product':
        final p = one('SELECT * FROM products WHERE id = ?', refId);
        if (p == null) return null;
        return {
          'product': p,
          'variants': _rows(
            'SELECT * FROM product_variants WHERE product_id = ?',
            [refId],
          ),
        };
      case 'customer':
        final c = one('SELECT * FROM customers WHERE id = ?', refId);
        return c == null ? null : {'customer': c};
      case 'customer_payment':
        final p = one('SELECT * FROM customer_payments WHERE id = ?', refId);
        if (p == null) return null;
        return {
          'payment': p,
          'customer': one(
            'SELECT * FROM customers WHERE id = ?',
            p['customer_id'] as String,
          ),
        };
    }
    return null;
  }

  /// The PC's number for a bill made on this phone, once it is sent.
  int? pcBillNo(String saleId) {
    final r = _db.select('SELECT pc_bill_no FROM sales WHERE id = ?', [saleId]);
    return r.isEmpty ? null : r.first['pc_bill_no'] as int?;
  }

  void setPcBillNo(String saleId, int no) =>
      _db.execute('UPDATE sales SET pc_bill_no = ? WHERE id = ?', [no, saleId]);
}

class PairedPhone {
  PairedPhone({
    required this.id,
    required this.name,
    required this.lastSeen,
    required this.billsToday,
    required this.salesToday,
  });
  final String id;
  final String name;
  final DateTime? lastSeen;
  final int billsToday;
  final double salesToday;
}
