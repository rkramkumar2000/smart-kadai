import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/customers/customers.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';

import 'voice_commands_test.dart' show FakeSpeech;

/// Ram: every feature shown in the demo video must work with no error, on
/// the PC and on a phone. This walks through them all, as in the video.
void main() {
  late AppState s;
  late FakeSpeech speech;

  // Made inside each test, so voice events run in the test's clock.
  void init() {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    repo
      ..setSetting('setup_done', '1')
      ..setSetting('shop_name', 'Sri Murugan Stores')
      ..setSetting('upi_id', 'murugan@upi');
    speech = FakeSpeech();
    s = AppState(repo, speech: speech);
    s.auth.createUser('Ram', Role.owner, '1234');
    final soap = s.products.firstWhere((p) => p.nameEn == 'Hamam Soap');
    s.saveProduct(soap.copyWith(barcode: '8901030865278'));
    s.customers.save(
      Customer(id: repo.newId(), name: 'Selvi', phone: '9876543210'),
    );
  }

  for (final (phone, scale) in [
    (false, 1.0),
    (true, 1.0),
    (false, 1.3),
    (true, 1.3),
  ]) {
    final where = '${phone ? 'phone' : 'PC'}${scale == 1 ? '' : ', big text'}';

    Future<void> pump(WidgetTester t) async {
      init();
      s.repo.setSetting('text_scale', '$scale');
      t.view.physicalSize = phone
          ? const Size(393, 851)
          : const Size(1366, 768);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(SmartKadaiApp(state: s));
      await t.pumpAndSettle();
    }

    Future<void> tapText(WidgetTester t, String text) async {
      final all = find.text(text);
      if (all.evaluate().isNotEmpty && all.hitTestable().evaluate().isEmpty) {
        await t.ensureVisible(all.last);
        await t.pumpAndSettle();
      }
      final f = find.text(text).hitTestable();
      expect(f, findsWidgets, reason: 'no "$text" on screen');
      await t.tap(f.first);
      await t.pumpAndSettle();
    }

    Future<void> tapContaining(WidgetTester t, String text) async {
      final all = find.textContaining(text);
      if (all.evaluate().isNotEmpty) {
        await t.ensureVisible(all.first);
        await t.pumpAndSettle();
      }
      final f = find.textContaining(text).hitTestable();
      expect(f, findsWidgets, reason: 'no "$text" on screen');
      await t.tap(f.first);
      await t.pumpAndSettle();
    }

    Future<void> openMenu(WidgetTester t, String name) async {
      if (phone) {
        await t.tap(find.byTooltip('Open navigation menu'));
        await t.pumpAndSettle();
      }
      // With big text the menu scrolls.
      final item = phone
          ? find.descendant(of: find.byType(Drawer), matching: find.text(name))
          : find.text(name);
      await t.scrollUntilVisible(
        item.first,
        60,
        scrollable: phone
            ? find
                  .descendant(
                    of: find.byType(Drawer),
                    matching: find.byType(Scrollable),
                  )
                  .first
            : find
                  .ancestor(
                    of: find.text('Credit book').first,
                    matching: find.byType(Scrollable),
                  )
                  .first,
      );
      await t.pumpAndSettle();
      await t.tap(item.hitTestable().first);
      await t.pumpAndSettle();
    }

    Future<void> typeOrder(WidgetTester t, String text) async {
      await t.enterText(find.byType(TextField).first, text);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
    }

    void mark(WidgetTester t, String step) {
      expect(t.takeException(), isNull, reason: 'error $step');
    }

    Future<void> closeSnack(WidgetTester t) async {
      ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await t.pumpAndSettle();
    }

    testWidgets('login and billing, as in the demo ($where)', (t) async {
      await pump(t);
      mark(t, 'before Login with PIN.');
      // Login with PIN.
      for (final d in '1234'.split('')) {
        await t.tap(find.text(d).hitTestable().first);
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(s.user?.name, 'Ram');

      mark(t, 'before Voice billing: several items a');
      // Voice billing: several items at once.
      speech.hear('ரெண்டு கடலை மிட்டாய் ஒரு கிலோ சர்க்கரை');
      await t.pumpAndSettle();
      expect(s.bill.lines, hasLength(2));
      mark(t, 'before Not sure: "which one?"');
      // Not sure: "which one?"
      await typeOrder(t, 'oru soap');
      expect(s.pending, hasLength(1));
      await tapContaining(t, 'Hamam Soap ·');
      expect(s.bill.lines, hasLength(3));
      mark(t, 'before Typed item and a barcode.');
      // Typed item and a barcode.
      await typeOrder(t, 'salt 1 kg');
      await typeOrder(t, '8901030865278');
      expect(s.bill.lines.length, 4);
      expect(
        s.bill.lines.firstWhere((l) => l.product.nameEn == 'Hamam Soap').count,
        2,
      );

      mark(t, 'before Retail / wholesale switch.');
      // Retail / wholesale switch.
      final retail = s.bill.total;
      await t.tap(find.text('W').hitTestable().first);
      await t.pumpAndSettle();
      expect(s.bill.wholesale, isTrue);
      await t.tap(find.text('R').hitTestable().first);
      await t.pumpAndSettle();
      expect(s.bill.total, retail);

      mark(t, 'before change price');
      // Change an item's price.
      await t.tap(find.byTooltip('Change price').first);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '12');
      await tapText(t, 'OK');
      expect(s.bill.lines.first.price, 12);

      mark(t, 'before Discount (the error in the fir');
      // Discount (the error in the first video).
      await tapContaining(t, 'Discount');
      await t.enterText(find.byType(TextField).last, '10');
      await tapText(t, 'Apply');
      expect(s.bill.discount, 10);
      await tapContaining(t, '₹10 off');
      await tapText(t, 'No discount');
      expect(s.bill.discount, 0);
      await tapContaining(t, 'Discount');
      await t.enterText(find.byType(TextField).last, '5%');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(s.bill.discount, greaterThan(0));

      mark(t, 'before Hold the bill, serve someone e');
      // Hold the bill, serve someone else, bring it back.
      final lines = s.bill.lines.length;
      await tapContaining(t, 'Hold bill');
      expect(s.bill.lines, isEmpty);
      await typeOrder(t, 'sugar 1 kg');
      await tapContaining(t, 'Held');
      expect(
        s.bill.lines.length + s.held.fold<int>(0, (n, b) => n + b.lines.length),
        lines + 1,
      );

      mark(t, 'before Customer, then save on credit.');
      // Customer, then save on credit.
      await tapContaining(t, 'Customer');
      await tapText(t, 'Selvi');
      expect(s.bill.customerName, 'Selvi');
      await tapText(t, phone ? 'Credit' : 'Credit · கடன்');
      expect(s.today.bills, 1);
      await closeSnack(t);

      mark(t, 'before UPI with the QR code.');
      // UPI with the QR code.
      if (s.bill.lines.isEmpty) await typeOrder(t, 'sugar 1 kg');
      await tapContaining(t, 'UPI');
      expect(find.text('Scan to pay · UPI'), findsOneWidget);
      await tapText(t, 'Paid · பணம் வந்தது');
      expect(s.today.bills, 2);
      await closeSnack(t);

      mark(t, 'before Cash, by voice: "bill podu".');
      // Cash, by voice: "bill podu".
      await typeOrder(t, 'salt 1 kg');
      speech.hear('bill podu');
      await t.pump();
      await t.pump();
      await t.pumpAndSettle();
      expect(s.today.bills, 3);
      expect(find.textContaining('Print bill'), findsWidgets);
      expect(find.textContaining('WhatsApp bill'), findsWidgets);
      await closeSnack(t);
    });

    testWidgets(
      'credit book, products, stock, purchases, reports, settings ($where)',
      (t) async {
        await pump(t);
        s.login(s.auth.users().first);
        await t.pumpAndSettle();
        mark(t, 'before A credit bill for Selvi first.');
        // A credit bill for Selvi first.
        await typeOrder(t, 'sugar 1 kg');
        s.setCustomer(s.customers.customers().first);
        s.completeBill(PaymentMode.credit);
        await t.pumpAndSettle();

        mark(t, 'before Credit book: money received.');
        // Credit book: money received.
        await openMenu(t, 'Credit book');
        await tapText(t, 'Selvi');
        await tapText(t, 'Money received');
        await t.enterText(find.widgetWithText(TextField, 'Amount ₹'), '20');
        await tapText(t, 'Save');
        expect(s.customers.customers().first.balance, 24);
        if (phone && find.byTooltip('Back').evaluate().isNotEmpty) {
          await t.tap(find.byTooltip('Back').first);
          await t.pumpAndSettle();
        }
        await tapText(t, 'Add customer');
        await t.enterText(
          find.widgetWithText(TextField, 'Name · பெயர்'),
          'Kannan',
        );
        await tapText(t, 'Save');
        expect(s.customers.customers().map((c) => c.name), contains('Kannan'));

        mark(t, 'before Products: voice search, edit, ');
        // Products: voice search, edit, add.
        await openMenu(t, 'Products');
        await t.tap(find.byTooltip('Find by voice'));
        await t.pumpAndSettle();
        speech.hear('சர்க்கரை');
        await t.pumpAndSettle();
        await tapContaining(t, 'Sugar ·');
        expect(find.text('Save'), findsOneWidget);
        await tapText(t, 'Save');
        await tapText(t, 'Add product');
        await t.enterText(
          find.widgetWithText(TextFormField, 'English name *'),
          'Ghee',
        );
        await t.enterText(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.decoration?.labelText ?? '').startsWith('Selling price per'),
          ),
          '600',
        );
        await tapText(t, 'Save');
        expect(s.products.map((p) => p.nameEn), contains('Ghee'));
        mark(t, 'before Search.');
        // Search.
        await t.enterText(find.byType(TextField).first, 'ghee');
        await t.pumpAndSettle();
        expect(find.text('Ghee'), findsWidgets);

        mark(t, 'before Stock: alerts, correct, histor');
        // Stock: alerts, correct, history.
        await openMenu(t, 'Stock');
        await tapText(t, 'Only low stock');
        await tapText(t, 'Only low stock');
        await tapText(t, 'Correct');
        await t.enterText(find.byType(TextField).last, '25');
        await tapText(t, 'Save');
        await tapText(t, 'History');
        await tapText(t, 'Close');

        mark(t, 'before Purchases: a supplier bill typ');
        // Purchases: a supplier bill typed in.
        await openMenu(t, 'Purchases');
        await tapText(t, 'New purchase');
        expect(find.text('Save purchase'), findsWidgets);
        if (find.byTooltip('Back').evaluate().isNotEmpty) {
          await t.tap(find.byTooltip('Back').first);
          await t.pumpAndSettle();
        } else if (find.text('Cancel').hitTestable().evaluate().isNotEmpty) {
          await tapText(t, 'Cancel');
        }

        mark(t, 'before Reports and expenses.');
        // Reports and expenses.
        await openMenu(t, 'Reports');
        for (final p in ['Last 7 days', 'This month', 'Today']) {
          await tapContaining(t, p);
        }
        await tapText(t, 'Add expense');
        await t.enterText(find.widgetWithText(TextField, 'Amount ₹'), '500');
        await tapText(t, 'Save');
        expect(find.textContaining('Sales by staff'), findsOneWidget);

        mark(t, 'before Settings: the screen in Tamil,');
        // Settings: the screen in Tamil, bigger text, and back.
        await openMenu(t, 'Settings');
        await tapContaining(t, 'தமிழ்');
        expect(find.text('அமைப்பு'), findsWidgets);
        await tapContaining(t, 'A+');
        await tapContaining(t, 'A−');
      },
    );
  }
}
