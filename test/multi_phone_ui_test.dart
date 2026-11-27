import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';
import 'package:smart_kadai/sync/shop_host.dart';
import 'package:smart_kadai/sync/shop_server.dart';
import 'package:smart_kadai/voice/speech_service.dart';

/// The screens for billing from staff phones through the shop PC.
void main() {
  late AppState pc;
  late ShopHost phone;

  Future<void> setUpShop(WidgetTester t) async {
    // Widget tests block real network calls; these talk to a real local
    // shop server.
    HttpOverrides.global = null;
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    repo
      ..setSetting('setup_done', '1')
      ..setSetting('shop_name', 'Sri Murugan Stores');
    pc = AppState(repo);
    pc.auth.createUser('Ram', Role.owner, '1234');
    pc.auth.createUser('Kumar', Role.staff, '5678');
    pc.server = ShopServer(pc.sync, port: 0, onChange: pc.refresh);
    await t.runAsync(
      () => pc.server!.start(address: InternetAddress.loopbackIPv4),
    );
    addTearDown(() => t.runAsync(() => pc.server!.stop()));
    phone = ShopHost(
      openOwn: () => AppDatabase.inMemory(),
      openLinked: () => AppDatabase.inMemory(),
      rememberLinked: (_) async {},
      linked: false,
      speech: NoSpeechService(),
      isPhone: true,
    );
  }

  Future<void> show(WidgetTester t, AppState s, {bool asPhone = true}) async {
    t.view.physicalSize = asPhone
        ? const Size(393, 851)
        : const Size(1366, 768);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ValueListenableBuilder<AppState>(
        valueListenable: asPhone ? phone : ValueNotifier(s),
        builder: (_, st, _) => SmartKadaiApp(key: ObjectKey(st), state: st),
      ),
    );
    await t.pumpAndSettle();
  }

  /// Lets real network calls finish, then draws the result.
  Future<void> wait(WidgetTester t, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('PC: turn on phones and show the pairing QR', (t) async {
    await setUpShop(t);
    await t.runAsync(() => pc.server!.stop());
    pc.server = null;
    pc.login(pc.auth.users().firstWhere((u) => u.isOwner));
    await show(t, pc, asPhone: false);
    await t.tap(find.text('Settings').first);
    await t.pumpAndSettle();
    final sw = find.widgetWithText(
      SwitchListTile,
      'Phones can bill through this PC',
    );
    await t.ensureVisible(sw);
    await t.pumpAndSettle();
    expect(find.text('No phones paired yet.'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('Pair a phone'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await t.pumpAndSettle();
    expect(pc.server?.running, isTrue);
    expect(pc.phonesOn, isTrue);
    // Either the QR (on a network) or a message to join the Wi-Fi.
    expect(
      find.textContaining('Code').evaluate().isNotEmpty ||
          find.textContaining('not on a network').evaluate().isNotEmpty,
      isTrue,
    );
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    await t.runAsync(() => pc.setPhonesOn(false));
    expect(pc.server?.running, isFalse);
  });

  testWidgets('phone: pair by typing the code, log in, bill to the PC', (
    t,
  ) async {
    await setUpShop(t);
    final code = pc.server!.newPairingCode();
    await show(t, phone.value);
    // A new phone: owner setup, or connect to the shop PC.
    expect(find.text('Connect to shop PC'), findsOneWidget);
    await t.tap(find.text('Type code instead'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'PC address, like 192.168.1.5'),
      '127.0.0.1:${pc.server!.port}',
    );
    await t.enterText(find.widgetWithText(TextField, '6-digit code'), code);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Kumar phone');
    await t.tap(find.text('Connect'));
    await t.pump();
    for (var i = 0; i < 10 && !phone.value.isLinkedPhone; i++) {
      await wait(t, 300);
    }
    expect(phone.value.isLinkedPhone, isTrue);
    await wait(t);
    final s = phone.value;
    expect(pc.sync.devices().single.name, 'Kumar phone');

    // The PC's staff log in with their own PIN.
    expect(find.textContaining('Kumar · Staff'), findsOneWidget);
    await t.tap(find.textContaining('Kumar · Staff'));
    await t.pumpAndSettle();
    for (final d in '5678'.split('')) {
      await t.tap(find.text(d).hitTestable().first);
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(s.user?.name, 'Kumar');

    // Stock, purchases and reports stay on the PC.
    await t.tap(find.byTooltip('Open navigation menu'));
    await t.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(
      find.descendant(of: drawer, matching: find.text('Stock')),
      findsNothing,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Reports')),
      findsNothing,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Products')),
      findsOneWidget,
    );
    await t.tap(find.descendant(of: drawer, matching: find.text('Billing')));
    await t.pumpAndSettle();

    // A bill on the phone goes to the PC and takes its number.
    await t.enterText(find.byType(TextField).first, 'sugar 2 kg');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await t.tap(find.text('Cash · பணம்').hitTestable().first);
    await t.pump();
    await wait(t, 1500);
    expect(pc.today.bills, 1);
    expect(find.textContaining('Bill 1 saved'), findsOneWidget);
    final row = pc.repo.db.select('SELECT * FROM sales').single;
    expect(row['user_id'], s.user!.id);

    // Wi-Fi gone: the bill waits on the phone.
    await t.runAsync(() => pc.server!.stop());
    ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
        .clearSnackBars();
    await t.enterText(find.byType(TextField).first, 'salt 1 kg');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await t.tap(find.text('Cash · பணம்').hitTestable().first);
    await t.pump();
    await wait(t, 1500);
    expect(find.textContaining('when Wi-Fi is back'), findsOneWidget);
    expect(s.link!.waitingBills, 1);
    expect(find.byIcon(Icons.cloud_off_outlined), findsWidgets);
    await t.runAsync(
      () => pc.server!.start(address: InternetAddress.loopbackIPv4),
    );
    await t.runAsync(() => s.link!.syncNow());
    await t.pumpAndSettle();
    expect(pc.today.bills, 2);
    expect(s.link!.waitingBills, 0);
    phone.value.dispose();
  });
}
