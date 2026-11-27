import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/main.dart';
import 'package:smart_kadai/voice/speech_service.dart';

/// A mic that remembers when it was turned on and off.
class MicSpeech implements SpeechService {
  final log = <String>[];
  var _on = false;
  final _results = StreamController<SpeechResult>.broadcast();
  final _changes = StreamController<void>.broadcast();
  void hear(String t) => _results.add(SpeechResult(t, isFinal: true));

  @override
  bool get isAvailable => true;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  bool get isListening => _on;
  @override
  Future<void> open() async {}
  @override
  Stream<SpeechResult> get results => _results.stream;
  @override
  Future<void> start() async {
    log.add('start');
    _on = true;
    _changes.add(null);
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    _on = false;
    _changes.add(null);
  }

  @override
  String? get problem => null;
  @override
  Future<void> say(String tamil, String english) async {}
}

/// Ram: "hold and speak", chosen in Settings, for a noisy shop.
void main() {
  late AppState s;
  late MicSpeech mic;

  setUp(() {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    repo.setSetting('setup_done', '1');
    mic = MicSpeech();
    s = AppState(repo, speech: mic);
    s.login(s.auth.createUser('Ram', Role.owner, '1234'));
  });

  test('off by default, and saved when turned on', () {
    expect(s.holdToSpeak, isFalse);
    s.holdToSpeak = true;
    expect(AppState(s.repo).holdToSpeak, isTrue);
  });

  test('listens only while held', () async {
    await s.holdStart();
    expect(s.listening, isTrue);
    await s.holdEnd();
    expect(s.listening, isFalse);
    expect(mic.log, ['start', 'stop']);
  });

  Future<void> pump(WidgetTester t, {required bool phone}) async {
    t.view.physicalSize = phone ? const Size(393, 851) : const Size(1366, 768);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    s.holdToSpeak = true;
    await t.pumpWidget(SmartKadaiApp(state: s));
    await t.pumpAndSettle();
  }

  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'PC';

    testWidgets('hold the mic, speak, let go ($where)', (t) async {
      await pump(t, phone: phone);
      final button = find.byIcon(Icons.mic).first;
      final hold = await t.startGesture(t.getCenter(button));
      await t.pump(const Duration(milliseconds: 800));
      expect(s.listening, isTrue);
      mic.hear('sugar 2 kg');
      await t.pump();
      await hold.up();
      await t.pumpAndSettle();
      expect(s.listening, isFalse);
      expect(s.bill.lines.single.product.nameEn, 'Sugar');
      expect(t.takeException(), isNull);
    });

    testWidgets('a quick tap says to keep holding ($where)', (t) async {
      await pump(t, phone: phone);
      await t.tap(find.byIcon(Icons.mic).first);
      await t.pump();
      expect(s.listening, isFalse);
      expect(find.textContaining('Keep holding'), findsOneWidget);
    });
  }

  testWidgets('hold F2 on the PC', (t) async {
    await pump(t, phone: false);
    await t.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await t.pump();
    expect(s.listening, isTrue);
    await t.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await t.pump();
    expect(s.listening, isFalse);
  });

  testWidgets('hold the mic on Products to find a product', (t) async {
    await pump(t, phone: true);
    await t.tap(find.byTooltip('Open navigation menu'));
    await t.pumpAndSettle();
    await t.tap(find.text('Products').first);
    await t.pumpAndSettle();
    final hold = await t.startGesture(
      t.getCenter(find.byTooltip('Find by voice')),
    );
    await t.pump(const Duration(milliseconds: 800));
    mic.hear('sugar');
    await t.pump();
    await hold.up();
    await t.pumpAndSettle();
    expect(find.textContaining('Sugar ·'), findsWidgets);
    expect(s.bill.lines, isEmpty);
    expect(s.listening, isFalse);
  });

  testWidgets('the switch is in Settings', (t) async {
    t.view.physicalSize = const Size(1366, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(SmartKadaiApp(state: s));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings').first);
    await t.pumpAndSettle();
    final sw = find.widgetWithText(SwitchListTile, 'Hold the mic to speak');
    await t.scrollUntilVisible(
      sw,
      200,
      scrollable: find
          .ancestor(
            of: find.text('Back up now'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.tap(sw);
    await t.pumpAndSettle();
    expect(s.holdToSpeak, isTrue);
  });
}
