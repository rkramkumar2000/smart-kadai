import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/purchases/purchases.dart';
import 'package:smart_kadai/reports/reports.dart';

void main() {
  late AppDatabase db;
  late ShopRepository shop;

  setUp(() {
    db = AppDatabase.inMemory();
    shop = ShopRepository(db)..seedIfEmpty();
  });
  tearDown(() => db.close());

  group('login', () {
    test('owner PIN works, wrong PIN does not, PIN is not stored', () {
      final auth = AuthRepository(db);
      expect(auth.hasOwner, isFalse);
      final owner = auth.createUser('Ram', Role.owner, '1234');
      expect(auth.hasOwner, isTrue);
      expect(auth.verify(owner.id, '1234')?.name, 'Ram');
      expect(auth.verify(owner.id, '9999'), isNull);
      final row = db.db.select('SELECT pin_hash FROM users').first;
      expect(row['pin_hash'], isNot(contains('1234')));
    });

    test('five wrong PINs lock the login for 30 seconds', () {
      final auth = AuthRepository(db);
      var clock = DateTime(2026, 11, 24, 10);
      auth.now = () => clock;
      final u = auth.createUser('Staff', Role.staff, '1111');
      for (var i = 0; i < 4; i++) {
        expect(auth.verify(u.id, '0000'), isNull);
      }
      expect(
        () => auth.verify(u.id, '0000'),
        throwsA(isA<PinLockedException>()),
      );
      expect(
        () => auth.verify(u.id, '1111'),
        throwsA(isA<PinLockedException>()),
      );
      clock = clock.add(const Duration(seconds: 31));
      expect(auth.verify(u.id, '1111'), isNotNull);
    });

    test('staff cannot see profit or edit products; last owner stays', () {
      final auth = AuthRepository(db);
      final owner = auth.createUser('Ram', Role.owner, '1234');
      final staff = auth.createUser('Kumar', Role.staff, '5678');
      expect(staff.canSeeProfit, isFalse);
      expect(staff.canEditProducts, isFalse);
      expect(owner.canSeeProfit, isTrue);
      expect(() => auth.setActive(owner.id, false), throwsStateError);
      auth.setActive(staff.id, false);
      expect(auth.users().map((u) => u.name), ['Ram']);
    });
  });

  group('purchases', () {
    test('a supplier bill raises stock, cost and the amount owed', () {
      final buy = PurchaseRepository(shop);
      final sup = buy.saveSupplier(
        Supplier(
          id: shop.newId(),
          name: 'Murugan Traders',
          gstin: '33ABCDE1234F1Z5',
        ),
      );
      final g = shop.loadProducts().firstWhere((p) => p.nameEn == 'Groundnut');
      final tenKg = g.variants.firstWhere((v) => v.label == '10 KG');
      buy.savePurchase(
        supplier: sup,
        invoiceNo: 'INV-1',
        invoiceDate: DateTime(2026, 11, 24),
        paid: 500,
        lines: [
          PurchaseLine(
            product: g,
            variant: tenKg,
            count: 2,
            unitCost: 1100,
            gstPercent: 5,
          ),
        ],
      );
      final after = shop.loadProducts().firstWhere(
        (p) => p.nameEn == 'Groundnut',
      );
      expect(after.stockQty, g.stockQty + 20);
      expect(after.purchasePrice, 115.5); // 1100 / 10 kg + 5% GST
      final s = buy.suppliers().single;
      expect(s.balance, 2310 - 500);
      buy.paySupplier(s.id, 810, 'UPI');
      expect(buy.suppliers().single.balance, 1000);
      expect(
        buy.findSupplier(gstin: '33abcde1234f1z5')?.name,
        'Murugan Traders',
      );
      expect(buy.recentPurchases().single.due, 1810);
    });
  });

  group('stock', () {
    test('corrections are recorded with a reason', () {
      final t = shop.loadProducts().firstWhere((p) => p.nameEn == 'Tomato');
      shop.adjustStock(t.id, -2, 'Spoiled');
      final h = shop.stockHistory(t.id);
      expect(h.first.delta, -2);
      expect(h.first.note, 'Spoiled');
      expect(
        shop.loadProducts().firstWhere((p) => p.nameEn == 'Tomato').stockQty,
        t.stockQty - 2,
      );
    });
  });

  group('reports', () {
    test('sales, profit, payment split and top items', () {
      final ps = shop.loadProducts();
      final g = ps.firstWhere((p) => p.nameEn == 'Groundnut');
      final c = ps.firstWhere((p) => p.nameEn == 'Chocolate');
      shop.saveSale(
        Bill()
          ..add(
            BillLine(
              product: g,
              variant: g.defaultVariant,
              count: 2,
              enteredBy: EntryMethod.voice,
            ),
          )
          ..add(
            BillLine(
              product: c,
              variant: c.defaultVariant,
              count: 5,
              enteredBy: EntryMethod.tap,
            ),
          ),
        PaymentMode.cash,
      );
      shop.saveSale(
        Bill()..add(
          BillLine(
            product: c,
            variant: c.defaultVariant,
            count: 1,
            enteredBy: EntryMethod.scan,
          ),
        ),
        PaymentMode.upi,
      );
      final (from, to) = ReportPeriod.today.range(DateTime.now());
      final r = ReportRepository(shop).build(from, to);
      expect(r.bills, 2);
      expect(r.sales, 280 + 50 + 10);
      expect(r.byMode['CASH'], 330);
      expect(r.byMode['UPI'], 10);
      expect(r.cost, closeTo(238 + 42.5 + 8.5, 0.01));
      expect(r.profit, closeTo(340 - 289, 0.01));
      expect(r.topItems.first.nameEn, 'Groundnut');
      expect(r.voiceShare, closeTo(1 / 3, 0.001));
      final csv = ReportRepository(shop).salesCsv(from, to);
      expect(csv.split('\n').where((l) => l.isNotEmpty).length, 4);
    });
  });
}
