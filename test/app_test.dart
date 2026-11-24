import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';

void main() {
  late AppState state;

  setUp(() {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    state = AppState(repo);
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

    final ghee = state.products.firstWhere((p) => p.nameEn == 'Ghee');
    expect(ghee.nameTa, 'நெய்');
    expect(ghee.code, 'P0016');
    expect(ghee.variants, hasLength(1));
  });
}
