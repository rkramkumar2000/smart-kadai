import 'package:sqlite3/sqlite3.dart';

import '../data/shop_repository.dart';

/// A regular customer. [balance] is what they owe the shop (kadan).
class Customer {
  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.balance = 0,
    this.lastActivity,
    this.isWholesale = false,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final double balance;
  final DateTime? lastActivity;

  /// A shop or trader who buys at wholesale prices.
  final bool isWholesale;
}

/// One row of a customer's account: a credit bill or a payment.
class LedgerEntry {
  LedgerEntry({
    required this.at,
    required this.amount,
    required this.isPayment,
    required this.label,
  });

  final DateTime at;

  /// Credit bills add to what is owed, payments take it away.
  final double amount;
  final bool isPayment;
  final String label;
}

/// The credit book: customers, what they owe, and payments received.
class CustomerRepository {
  CustomerRepository(this.shop);

  final ShopRepository shop;
  Database get _db => shop.db;

  List<Customer> customers({String query = ''}) {
    final q = '%${query.trim().toLowerCase()}%';
    return _db
        .select(
          '''
SELECT c.*, MAX(COALESCE(MAX(s.created_at), ''), c.updated_at) AS last
FROM customers c LEFT JOIN sales s ON s.customer_id = c.id
WHERE lower(c.name) LIKE ? OR c.phone LIKE ?
GROUP BY c.id
ORDER BY c.balance DESC, lower(c.name)''',
          [q, q],
        )
        .map(_customer)
        .toList();
  }

  Customer? byId(String id) {
    final r = _db.select(
      'SELECT *, updated_at AS last FROM customers WHERE id = ?',
      [id],
    );
    return r.isEmpty ? null : _customer(r.first);
  }

  Customer save(Customer c) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      '''
INSERT INTO customers (id, name, phone, address, balance, created_at, updated_at, is_wholesale)
VALUES (?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET name = excluded.name, phone = excluded.phone,
  address = excluded.address, updated_at = excluded.updated_at,
  is_wholesale = excluded.is_wholesale''',
      [
        c.id,
        c.name.trim(),
        c.phone.trim(),
        c.address.trim(),
        c.balance,
        now,
        now,
        c.isWholesale ? 1 : 0,
      ],
    );
    shop.onLocalChange?.call('customer', c.id);
    return byId(c.id)!;
  }

  /// Money received from a customer against what they owe.
  void receivePayment(
    String customerId,
    double amount,
    String mode, {
    String note = '',
    String? userId,
  }) {
    if (amount <= 0) return;
    final now = DateTime.now().toIso8601String();
    final id = shop.newId();
    shop.transaction(() {
      _db.execute(
        'INSERT INTO customer_payments (id, customer_id, amount, mode, note, created_at, user_id) VALUES (?,?,?,?,?,?,?)',
        [id, customerId, amount, mode, note, now, userId],
      );
      _db.execute(
        'UPDATE customers SET balance = ROUND(balance - ?, 2), updated_at = ? WHERE id = ?',
        [amount, now, customerId],
      );
    });
    shop.onLocalChange?.call('customer_payment', id);
  }

  /// Credit bills and payments, newest first.
  List<LedgerEntry> ledger(String customerId) {
    final out = <LedgerEntry>[
      for (final r in _db.select(
        "SELECT bill_no, created_at, total FROM sales WHERE customer_id = ? AND payment_mode = 'CREDIT'",
        [customerId],
      ))
        LedgerEntry(
          at: DateTime.parse(r['created_at'] as String),
          amount: (r['total'] as num).toDouble(),
          isPayment: false,
          label: 'Bill ${r['bill_no']}',
        ),
      for (final r in _db.select(
        'SELECT created_at, amount, mode FROM customer_payments WHERE customer_id = ?',
        [customerId],
      ))
        LedgerEntry(
          at: DateTime.parse(r['created_at'] as String),
          amount: (r['amount'] as num).toDouble(),
          isPayment: true,
          label: 'Paid by ${r['mode']}',
        ),
    ];
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// Total all customers owe the shop.
  double totalDue() =>
      ((_db
                          .select(
                            'SELECT COALESCE(SUM(balance),0) AS b FROM customers WHERE balance > 0',
                          )
                          .first['b']
                      as num)
                  .toDouble() *
              100)
          .roundToDouble() /
      100;

  /// A polite reminder in Tamil and English for WhatsApp.
  static String reminderText(Customer c, String shopName, String upiId) {
    final amt = c.balance == c.balance.roundToDouble()
        ? c.balance.toStringAsFixed(0)
        : c.balance.toStringAsFixed(2);
    final b = StringBuffer()
      ..writeln('வணக்கம் ${c.name},')
      ..writeln('$shopName கடையில் உங்கள் நிலுவை தொகை ₹$amt.')
      ..writeln('Hello ${c.name}, your balance at $shopName is ₹$amt.');
    if (upiId.isNotEmpty) {
      b.writeln('UPI: $upiId');
    }
    b.write('நன்றி · Thank you');
    return b.toString();
  }

  Customer _customer(Row r) => Customer(
    id: r['id'] as String,
    name: r['name'] as String,
    phone: r['phone'] as String,
    address: r['address'] as String,
    balance: (r['balance'] as num).toDouble(),
    lastActivity: DateTime.tryParse('${r['last'] ?? ''}'),
    isWholesale: (r['is_wholesale'] as int? ?? 0) == 1,
  );
}

/// Shop running costs, so the owner sees real profit.
class Expense {
  Expense({
    required this.id,
    required this.day,
    required this.category,
    required this.amount,
    this.note = '',
  });

  final String id;
  final DateTime day;
  final String category;
  final double amount;
  final String note;

  static const categories = [
    'Rent',
    'Electricity',
    'Salary',
    'Transport',
    'Tea and snacks',
    'Repairs',
    'Other',
  ];
}

class ExpenseRepository {
  ExpenseRepository(this.shop);

  final ShopRepository shop;
  Database get _db => shop.db;

  void add(
    DateTime day,
    String category,
    double amount, {
    String note = '',
    String? userId,
  }) {
    if (amount <= 0) return;
    _db.execute(
      'INSERT INTO expenses (id, day, category, amount, note, created_at, user_id) VALUES (?,?,?,?,?,?,?)',
      [
        shop.newId(),
        DateTime(day.year, day.month, day.day).toIso8601String(),
        category,
        amount,
        note.trim(),
        DateTime.now().toIso8601String(),
        userId,
      ],
    );
  }

  void delete(String id) =>
      _db.execute('DELETE FROM expenses WHERE id = ?', [id]);

  List<Expense> list(DateTime from, DateTime to) => _db
      .select(
        'SELECT * FROM expenses WHERE day >= ? AND day < ? ORDER BY day DESC, created_at DESC',
        [from.toIso8601String(), to.toIso8601String()],
      )
      .map(
        (r) => Expense(
          id: r['id'] as String,
          day: DateTime.parse(r['day'] as String),
          category: r['category'] as String,
          amount: (r['amount'] as num).toDouble(),
          note: r['note'] as String,
        ),
      )
      .toList();

  double total(DateTime from, DateTime to) =>
      (_db.select(
                'SELECT COALESCE(SUM(amount),0) AS t FROM expenses WHERE day >= ? AND day < ?',
                [from.toIso8601String(), to.toIso8601String()],
              ).first['t']
              as num)
          .toDouble();
}
