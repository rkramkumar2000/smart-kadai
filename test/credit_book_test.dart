import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/customers/customers.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/printing/bill_printer.dart';
import 'package:smart_kadai/reports/reports.dart';

void main() {
  late AppState s;
  setUp(() {
    s = AppState(ShopRepository(AppDatabase.inMemory())..seedIfEmpty());
  });

  Customer addLakshmi() => s.customers.save(
    Customer(id: s.repo.newId(), name: 'Lakshmi', phone: '98765 43210'),
  );

  test('credit bill needs a customer and adds to what they owe', () {
    s.handleTyped('rendu kadalai mittai oru kilo kadalai'); // 10 + 140
    expect(s.completeBill(PaymentMode.credit), isNull);

    final c = addLakshmi();
    s.setCustomer(c);
    expect(s.completeBill(PaymentMode.credit), isNotNull);
    expect(s.customers.byId(c.id)!.balance, 150);

    s.customers.receivePayment(c.id, 100, 'UPI');
    expect(s.customers.byId(c.id)!.balance, 50);
    expect(s.customers.totalDue(), 50);
    final ledger = s.customers.ledger(c.id);
    expect(ledger, hasLength(2));
    expect(ledger.where((e) => e.isPayment).single.amount, 100);

    final text = CustomerRepository.reminderText(
      s.customers.byId(c.id)!,
      'Ram Stores',
      'ram@okaxis',
    );
    expect(text, contains('₹50'));
    expect(text, contains('ram@okaxis'));
  });

  test('discount lowers the total, and reports show it', () {
    s.handleTyped('oru kilo kadalai'); // 140
    s.setDiscount(10);
    expect(s.bill.subtotal, 140);
    expect(s.bill.total, 130);
    s.setDiscount(500);
    expect(s.bill.total, 0);
    s.setDiscount(10);
    s.completeBill(PaymentMode.cash);
    s.expenses.add(DateTime.now(), 'Electricity', 40);
    final (from, to) = ReportPeriod.today.range(DateTime.now());
    final r = s.reports.build(from, to);
    expect(r.sales, 130);
    expect(r.discounts, 10);
    expect(r.expenses, 40);
    expect(r.netProfit, closeTo(r.profit - 40, 0.001));
  });

  test('hold a bill, serve another, then bring it back', () {
    s.handleTyped('oru kilo kadalai');
    s.holdBill();
    expect(s.bill.lines, isEmpty);
    expect(s.held, hasLength(1));
    s.handleTyped('anju chocolate');
    final first = s.held.single;
    s.resumeBill(first);
    expect(s.bill.lines.single.product.nameEn, 'Groundnut');
    expect(s.held.single.lines.single.product.nameEn, 'Chocolate');
  });

  test('bill for WhatsApp lists items and total', () {
    s.handleTyped('rendu kadalai mittai');
    s.completeBill(PaymentMode.upi);
    final t = billText(s.lastBill!, 'Ram Stores');
    expect(t, contains('Groundnut Candy'));
    expect(t, contains('₹10'));
  });
}
