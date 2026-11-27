import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/core/units.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';
import 'package:smart_kadai/voice/product_voice.dart';

import 'voice_commands_test.dart' show FakeSpeech;

/// Ram: find a product by voice to change it, or say a new one to add it.
void main() {
  group('parseSpokenProduct', () {
    test('English name, size and price', () {
      final sp = parseSpokenProduct('Aavin milk 500 ml 28 rupees');
      expect(sp.name, 'Aavin milk');
      expect(sp.isTamil, isFalse);
      expect(sp.size, 500);
      expect(sp.unit, Unit.ml);
      expect(sp.price, 28);
    });

    test('Tamil name, size and price', () {
      final sp = parseSpokenProduct('ஆச்சி மிளகாய் தூள் 100 கிராம் 45 ரூபாய்');
      expect(sp.name, 'ஆச்சி மிளகாய் தூள்');
      expect(sp.isTamil, isTrue);
      expect(sp.size, 100);
      expect(sp.unit, Unit.gram);
      expect(sp.price, 45);
    });

    test('"விலை" before the price', () {
      final sp = parseSpokenProduct('சர்க்கரை 1 கிலோ விலை 44');
      expect(sp.name, 'சர்க்கரை');
      expect(sp.size, 1);
      expect(sp.unit, Unit.kg);
      expect(sp.price, 44);
    });

    test('just a name', () {
      final sp = parseSpokenProduct('sugar');
      expect(sp.name, 'sugar');
      expect(sp.size, isNull);
      expect(sp.price, isNull);
    });
  });

  group('finding by voice', () {
    late AppState s;
    late FakeSpeech speech;
    setUp(() {
      final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
      repo.setSetting('setup_done', '1');
      speech = FakeSpeech();
      s = AppState(repo, speech: speech);
      s.login(s.auth.createUser('Ram', Role.owner, '1234'));
    });

    test('names sound like products', () {
      expect(s.findByVoice('muttai').map((p) => p.nameEn), contains('Egg'));
      expect(s.findByVoice('சர்க்கரை').first.nameEn, 'Sugar');
      expect(s.findByVoice('onion').first.nameEn, 'Onion');
    });

    test('while finding, what is said does not go on the bill', () async {
      final heard = <String>[];
      s.voiceCapture = heard.add;
      speech.hear('sugar 2 kg');
      await pumpEventQueue();
      expect(heard, ['sugar 2 kg']);
      expect(s.bill.lines, isEmpty);
      s.voiceCapture = null;
      speech.hear('sugar 2 kg');
      await pumpEventQueue();
      expect(s.bill.lines, hasLength(1));
    });

    Future<void> openProducts(WidgetTester t, {required bool phone}) async {
      t.view.physicalSize = phone
          ? const Size(393, 851)
          : const Size(1366, 768);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(SmartKadaiApp(state: s));
      await t.pumpAndSettle();
      if (phone) {
        await t.tap(find.byTooltip('Open navigation menu'));
        await t.pumpAndSettle();
      }
      await t.tap(find.text('Products').first);
      await t.pumpAndSettle();
    }

    for (final phone in [false, true]) {
      final where = phone ? 'phone' : 'PC';

      testWidgets('say a product to change it ($where)', (t) async {
        await openProducts(t, phone: phone);
        await t.tap(find.byTooltip('Find by voice'));
        await t.pumpAndSettle();
        speech.hear('sugar');
        await t.pumpAndSettle();
        expect(find.textContaining('Heard'), findsOneWidget);
        expect(
          find.ancestor(
            of: find.textContaining('Sugar ·'),
            matching: find.byType(ActionChip),
          ),
          findsWidgets,
        );
        await t.tap(find.textContaining('Sugar ·').first);
        await t.pumpAndSettle();
        expect(find.text('Sugar'), findsWidgets); // the form, filled in
        expect(s.bill.lines, isEmpty);
        expect(t.takeException(), isNull);
      });

      testWidgets('say a new product to add it ($where)', (t) async {
        await openProducts(t, phone: phone);
        await t.tap(find.byTooltip('Find by voice'));
        await t.pumpAndSettle();
        speech.hear('Kumbakonam degree coffee 200 gram 120 rupees');
        await t.pumpAndSettle();
        final add = find.textContaining('as new');
        expect(add, findsOneWidget);
        await t.tap(add);
        await t.pumpAndSettle();
        expect(find.text('Kumbakonam Degree Coffee'), findsOneWidget);
        expect(find.text('200'), findsWidgets);
        expect(find.text('120'), findsWidgets);
        expect(s.bill.lines, isEmpty);
        expect(t.takeException(), isNull);
      });
    }
  });
}
