import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';

/// The same app on an Android phone screen (about 393 × 851, Pixel size).
void main() {
  late AppState state;

  setUp(() {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    repo.setSetting('setup_done', '1');
    state = AppState(repo);
    state.login(state.auth.createUser('Ram', Role.owner, '1234'));
  });

  Future<void> pumpPhone(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(393, 851);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    state.repo.setSetting('text_scale', '$scale');
    await t.pumpWidget(SmartKadaiApp(state: state));
    await t.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester t, String name) async {
    await t.tap(find.byTooltip('Open navigation menu'));
    await t.pumpAndSettle();
    final item = find.descendant(
      of: find.byType(Drawer),
      matching: find.text(name),
    );
    // With big text the menu scrolls.
    await t.scrollUntilVisible(
      item,
      60,
      scrollable: find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.tap(item);
    await t.pumpAndSettle();
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('bill on a phone, text ${(scale * 100).round()}%', (t) async {
      await pumpPhone(t, scale: scale);
      // The menu is in a drawer, so billing gets the whole width.
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      await t.enterText(
        find.byType(TextField).first,
        'sugar 2 kg ok salt 1 kg',
      );
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(state.bill.lines, hasLength(2));

      await t.tap(find.text('Cash · பணம்'));
      await t.pumpAndSettle();
      expect(state.bill.lines, isEmpty);
      expect(state.today.bills, 1);
    });

    testWidgets('every screen fits a phone, text ${(scale * 100).round()}%', (
      t,
    ) async {
      await pumpPhone(t, scale: scale);
      for (final name in [
        'Credit book',
        'Products',
        'Stock',
        'Purchases',
        'Reports',
        'Settings',
        'Billing',
      ]) {
        await openMenu(t, name);
      }
      await openMenu(t, 'Products');
      await t.tap(find.text('Add product'));
      await t.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
    });
  }

  testWidgets('quick items add with one tap on a phone', (t) async {
    await pumpPhone(t);
    await t.tap(find.byType(ActionChip).first);
    await t.pumpAndSettle();
    expect(state.bill.lines, hasLength(1));
  });
}
