import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';

void main() {
  late AppState state;

  setUp(() {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    state = AppState(repo);
    state.login(state.auth.createUser('Ram', Role.owner, '1234'));
  });

  Future<void> pumpApp(WidgetTester t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(SmartKadaiApp(state: state));
    await t.pumpAndSettle();
  }

  testWidgets('typed Tanglish order becomes bill lines and saves', (t) async {
    await pumpApp(t);
    await t.enterText(
      find.byType(TextField).first,
      'rendu kadalai mittai oru kilo kadalai',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(state.bill.lines, hasLength(2));
    expect(find.text('Groundnut Candy'), findsWidgets);
    expect(find.text('₹150'), findsOneWidget); // 2 x 5 + 140

    await t.tap(find.text('Cash · பணம் (F12)'));
    await t.pumpAndSettle();
    expect(state.bill.lines, isEmpty);
    expect(state.today.bills, 1);
  });

  testWidgets('unsure match asks before adding', (t) async {
    await pumpApp(t);
    await t.enterText(find.byType(TextField).first, 'oru soap');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(state.bill.lines, isEmpty);
    expect(state.pending, hasLength(1));
    await t.tap(find.textContaining('Hamam Soap ·').first);
    await t.pumpAndSettle();
    expect(state.bill.lines.single.product.nameEn, 'Hamam Soap');
  });

  testWidgets('add a product with two sizes', (t) async {
    await pumpApp(t);
    await t.tap(find.text('Products'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add product'));
    await t.pumpAndSettle();

    await t.enterText(
      find.widgetWithText(TextFormField, 'English name *'),
      'Ghee',
    );
    await t.enterText(
      find.widgetWithText(TextFormField, 'Tamil name · தமிழ் பெயர்'),
      'நெய்',
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Enter a selling price.'), findsOneWidget);
    await t.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.labelText ?? '').startsWith('Selling price per'),
      ),
      '600',
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    final ghee = state.products.firstWhere((p) => p.nameEn == 'Ghee');
    expect(ghee.nameTa, 'நெய்');
    expect(ghee.code, 'P0016');
    expect(ghee.variants, hasLength(1));
    expect(ghee.variants.single.sellingPrice, 600);
    expect(ghee.nameTanglish, 'ney');
  });

  testWidgets('every owner screen opens', (t) async {
    await pumpApp(t);
    for (final name in [
      'Credit book',
      'Stock',
      'Purchases',
      'Reports',
      'Settings',
    ]) {
      await t.tap(find.text(name).first);
      await t.pumpAndSettle();
    }
    expect(find.text('Back up now'), findsOneWidget);
  });

  testWidgets('staff do not see purchases, reports or settings', (t) async {
    state.login(state.auth.createUser('Kumar', Role.staff, '5678'));
    await pumpApp(t);
    expect(find.text('Stock'), findsWidgets);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('lock, then log in again with the PIN', (t) async {
    await pumpApp(t);
    await t.tap(find.byTooltip('Lock · பூட்டு'));
    await t.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);
    for (final d in ['1', '2', '3', '4']) {
      await t.tap(find.text(d));
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(state.user?.name, 'Ram');
  });

  testWidgets('first run asks for the owner name and PIN twice', (t) async {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    state = AppState(repo);
    await pumpApp(t);
    expect(find.text('Welcome to Smart Kadai'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Ram');
    for (var round = 0; round < 2; round++) {
      for (final d in ['4', '3', '2', '1']) {
        await t.tap(find.text(d));
        await t.pump();
      }
      await t.pumpAndSettle();
    }
    expect(state.user?.isOwner, isTrue);
    expect(state.auth.verify(state.user!.id, '4321'), isNotNull);
  });
}
