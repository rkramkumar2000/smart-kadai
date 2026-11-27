import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/catalogue/product_import.dart';
import 'package:smart_kadai/customers/customers.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';
import 'package:smart_kadai/printing/bill_printer.dart';
import 'package:smart_kadai/voice/speech_service.dart';
import 'package:smart_kadai/voice/voice_commands.dart';

/// Ram: separate retail and wholesale rates, and a button on the bill.
void main() {
  late AppState s;

  setUp(() {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    repo.setSetting('setup_done', '1');
    s = AppState(repo);
    // Sugar: retail ₹44 / KG, wholesale ₹40 / KG.
    final sugar = s.products.firstWhere((p) => p.nameEn == 'Sugar');
    s.repo.saveProduct(
      sugar.copyWith(
        wholesalePrice: 40,
        variants: [
          for (final v in sugar.variants)
            v.copyWith(wholesalePrice: roundTo(40 * v.stockFactor)),
        ],
      ),
    );
    s.refresh();
  });

  test('wholesale price is saved and read back', () {
    final sugar = s.products.firstWhere((p) => p.nameEn == 'Sugar');
    expect(sugar.wholesalePrice, 40);
    expect(sugar.defaultVariant!.wholesalePrice, greaterThan(0));
  });

  test('the bill switches between retail and wholesale', () {
    s.handleSpoken('sugar 2 kg ok salt 1 kg', EntryMethod.voice);
    final retail = s.bill.total;
    s.setWholesale(true);
    // Sugar is cheaper, salt has no wholesale price so it stays the same.
    expect(s.bill.total, retail - 2 * 4);
    s.setWholesale(false);
    expect(s.bill.total, retail);
  });

  test('items added after switching use wholesale too', () {
    s.setWholesale(true);
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    expect(s.bill.lines.single.unitPrice, 40);
  });

  test('a wholesale customer gets wholesale prices', () {
    final c = s.customers.save(
      Customer(id: s.repo.newId(), name: 'Murugan Stores', isWholesale: true),
    );
    expect(s.customers.byId(c.id)!.isWholesale, isTrue);
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    s.setCustomer(c);
    expect(s.bill.wholesale, isTrue);
    expect(s.bill.total, 40);
  });

  test('saying "wholesale" or "சில்லறை" switches the bill', () {
    expect(detectCommand('wholesale'), VoiceCommand.wholesale);
    expect(detectCommand('ஹோல்சேல்'), VoiceCommand.wholesale);
    expect(detectCommand('சில்லறை'), VoiceCommand.retail);
    expect(detectCommand('மொத்தம்'), VoiceCommand.total);
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    s.runCommand(VoiceCommand.wholesale);
    expect(s.bill.total, 40);
    s.runCommand(VoiceCommand.retail);
    expect(s.bill.total, 44);
  });

  test('a wholesale bill is saved at wholesale prices', () {
    s.setWholesale(true);
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    s.completeBill(PaymentMode.cash);
    final row = s.repo.db.select('SELECT total, wholesale FROM sales').single;
    expect(row['total'], 40);
    expect(row['wholesale'], 1);
    expect(s.bill.wholesale, isFalse, reason: 'the next bill is retail');
  });

  test('Excel sheet has a wholesale price column', () {
    expect(importColumns, contains('Wholesale price'));
    final r = s.readProductSheet(parseCsv(importTemplateCsv()));
    final g = r.products.firstWhere((p) => p.nameEn == 'Groundnut');
    expect(g.wholesalePrice, 132);
    expect(g.variants.map((v) => v.wholesalePrice), [132, 68, 35]);
  });

  test('the customer never sees or hears "wholesale"', () {
    final speech = _Speech();
    final v = AppState(s.repo, speech: speech);
    v.handleSpoken('sugar 1 kg', EntryMethod.voice);
    v.runCommand(VoiceCommand.wholesale);
    expect(v.bill.total, 40);
    final spoken = speech.said.join(' ').toLowerCase();
    expect(spoken, isNot(contains('wholesale')));
    expect(spoken, isNot(contains('மொத்த விலை')));
    v.completeBill(PaymentMode.cash);
    final text = billText(v.lastBill!, v.shopName).toLowerCase();
    expect(text, isNot(contains('wholesale')));
  });

  testWidgets('Retail / Wholesale button on the bill', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    s.login(s.auth.createUser('Ram', Role.owner, '1234'));
    await t.pumpWidget(SmartKadaiApp(state: s));
    await t.pumpAndSettle();
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    await t.pumpAndSettle();
    expect(find.text('₹44'), findsWidgets);
    await t.tap(find.text('W'));
    await t.pumpAndSettle();
    expect(s.bill.wholesale, isTrue);
    expect(find.text('₹40'), findsWidgets);
    await t.tap(find.text('R'));
    await t.pumpAndSettle();
    expect(s.bill.total, 44);
  });
}

double roundTo(double v) => (v * 100).roundToDouble() / 100;

class _Speech extends NoSpeechService {
  final said = <String>[];

  @override
  Future<void> say(String tamil, String english) async =>
      said.addAll([tamil, english]);
}
