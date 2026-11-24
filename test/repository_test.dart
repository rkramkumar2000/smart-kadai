import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/core/units.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';

void main() {
  late AppDatabase db;
  late ShopRepository repo;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = ShopRepository(db)..seedIfEmpty();
  });
  tearDown(() => db.close());

  test('starter catalogue loads with variants', () {
    final products = repo.loadProducts();
    expect(products.length, 15);
    final g = products.firstWhere((p) => p.nameEn == 'Groundnut');
    expect(g.nameTa, 'கடலை');
    expect(g.nameTanglish, 'Kadalai');
    expect(
      g.variants.map((v) => v.label),
      containsAll(['1 KG', '5 KG', '10 KG', '250 GRAM', '500 GRAM']),
    );
    expect(repo.nextProductCode(), 'P0016');
  });

  test('saving a bill lowers stock in the stock unit', () {
    final g = repo.loadProducts().firstWhere((p) => p.nameEn == 'Groundnut');
    final v250 = g.variants.firstWhere((v) => v.label == '250 GRAM');
    final bill = Bill()
      ..add(
        BillLine(
          product: g,
          variant: v250,
          count: 2,
          enteredBy: EntryMethod.voice,
        ),
      );
    final no = repo.saveSale(bill, PaymentMode.cash);
    expect(no, 1);
    final after = repo.loadProducts().firstWhere(
      (p) => p.nameEn == 'Groundnut',
    );
    expect(after.stockQty, g.stockQty - 0.5);
    expect(repo.todaySummary().bills, 1);
  });

  test('edit a product and its variants', () {
    final g = repo.loadProducts().firstWhere((p) => p.nameEn == 'Groundnut');
    final trimmed = g.copyWith(
      brand: 'Local',
      variants: g.variants.where((v) => v.unit == Unit.kg).toList(),
    );
    repo.saveProduct(trimmed);
    final after = repo.loadProducts().firstWhere(
      (p) => p.nameEn == 'Groundnut',
    );
    expect(after.brand, 'Local');
    expect(after.variants.every((v) => v.unit == Unit.kg), isTrue);
  });

  test('voice aliases are remembered', () {
    repo.saveAlias('soap', 'p-hamam');
    repo.saveAlias('soap', 'p-hamam');
    expect(repo.loadAliases(), {'soap': 'p-hamam'});
  });
}
