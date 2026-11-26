import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';

/// Ram: "Option to edit the amt?" Change one item's price on this bill.
void main() {
  late AppState s;
  setUp(() {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    repo.setSetting('setup_done', '1');
    s = AppState(repo);
    s.login(s.auth.createUser('Ram', Role.owner, '1234'));
  });

  test('a typed price is used for this bill only', () {
    s.handleSpoken('sugar 2 kg', EntryMethod.voice);
    expect(s.bill.total, 88);
    s.setLinePrice(0, 42);
    expect(s.bill.lines.single.unitPrice, 42);
    expect(s.bill.total, 84);
    // More of the same item keeps the typed price.
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    expect(s.bill.total, 126);
    s.completeBill(PaymentMode.cash);
    final row = s.repo.db.select('SELECT unit_price FROM sale_items').single;
    expect(row['unit_price'], 42);
    // The product keeps its own price.
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    expect(s.bill.total, 44);
  });

  test('going back to the list price', () {
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    s.setLinePrice(0, 40);
    s.setLinePrice(0, null);
    expect(s.bill.lines.single.price, isNull);
    expect(s.bill.total, 44);
  });

  for (final (name, size) in [
    ('PC', const Size(1440, 900)),
    ('phone', const Size(393, 851)),
  ]) {
    testWidgets('tap the price to change it on the $name', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(SmartKadaiApp(state: s));
      await t.pumpAndSettle();
      s.handleSpoken('sugar 2 kg', EntryMethod.voice);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Change price'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '40');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(s.bill.total, 80);
      expect(find.text('@₹40'), findsOneWidget);
    });
  }
}
