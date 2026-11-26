import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/voice/speech_service.dart';
import 'package:smart_kadai/voice/voice_commands.dart';

class FakeSpeech implements SpeechService {
  final said = <String>[];
  final _results = StreamController<SpeechResult>.broadcast();
  void hear(String t) => _results.add(SpeechResult(t, isFinal: true));

  @override
  bool get isAvailable => true;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  bool get isListening => true;
  @override
  Future<void> open() async {}
  @override
  Stream<SpeechResult> get results => _results.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  String? get problem => null;
  @override
  Future<void> say(String tamil, String english) async => said.add(english);
}

void main() {
  group('detectCommand', () {
    final cases = {
      'bill podu': VoiceCommand.saveCash,
      'ok bill podu': VoiceCommand.saveCash,
      'பில் போடு': VoiceCommand.saveCash,
      'Cash': VoiceCommand.saveCash,
      'சரி முடிஞ்சது': VoiceCommand.saveCash,
      'GPay': VoiceCommand.saveUpi,
      'UPI': VoiceCommand.saveUpi,
      'கடன்': VoiceCommand.saveCredit,
      'கேன்சல்': VoiceCommand.clear,
      'எல்லாம் வேண்டாம்': VoiceCommand.clear,
      'கடைசி வேண்டாம்': VoiceCommand.removeLast,
      'undo': VoiceCommand.removeLast,
      'மொத்தம் எவ்வளவு': VoiceCommand.total,
      'total': VoiceCommand.total,
    };
    cases.forEach((text, cmd) {
      test(text, () => expect(detectCommand(text), cmd));
    });
    for (final order in [
      'sugar 2 kg',
      'ரெண்டு கடலை மிட்டாய் cash',
      'ok hamam 1 packet ok salt 1 kg ok rice 1 kg',
      'உப்பு 1 கிலோ',
      '',
    ]) {
      test('not a command: $order', () => expect(detectCommand(order), isNull));
    }
  });

  group('spoken commands', () {
    late AppState s;
    late FakeSpeech speech;
    setUp(() {
      speech = FakeSpeech();
      s = AppState(
        ShopRepository(AppDatabase.inMemory())..seedIfEmpty(),
        speech: speech,
      );
    });

    test('items are read back with the total', () async {
      speech.hear('sugar 2 kg');
      await pumpEventQueue();
      expect(s.bill.lines, hasLength(1));
      expect(speech.said.last, contains('Sugar'));
      expect(speech.said.last, contains('Total'));
    });

    test('"கடைசி வேண்டாம்" removes the last item', () async {
      s.handleSpoken('sugar 2 kg ok salt 1 kg', EntryMethod.voice);
      expect(s.bill.lines, hasLength(2));
      speech.hear('கடைசி வேண்டாம்');
      await pumpEventQueue();
      expect(s.bill.lines.map((l) => l.product.nameEn), ['Sugar']);
      expect(speech.said.last, 'Salt removed');
    });

    test('"cancel" clears the bill', () async {
      s.handleSpoken('sugar 2 kg', EntryMethod.voice);
      speech.hear('கேன்சல்');
      await pumpEventQueue();
      expect(s.bill.lines, isEmpty);
      expect(speech.said.last, 'Bill cleared');
    });

    test('"total" says the total', () async {
      s.handleSpoken('sugar 2 kg', EntryMethod.voice);
      speech.hear('total');
      await pumpEventQueue();
      expect(speech.said.last, 'Total ${_rs(s.bill.total)} rupees');
    });

    test('"bill podu" asks the screen to save as cash', () async {
      final saves = <PaymentMode>[];
      s.voiceSaves.listen(saves.add);
      s.handleSpoken('sugar 2 kg', EntryMethod.voice);
      speech.hear('பில் போடு');
      speech.hear('GPay');
      await pumpEventQueue();
      expect(saves, [PaymentMode.cash, PaymentMode.upi]);
    });

    test('saving an empty bill only speaks', () async {
      final saves = <PaymentMode>[];
      s.voiceSaves.listen(saves.add);
      speech.hear('cash');
      await pumpEventQueue();
      expect(saves, isEmpty);
      expect(speech.said.last, 'The bill is empty');
    });

    test('replies can be turned off', () async {
      s.repo.setSetting('voice_reply', '0');
      speech.hear('sugar 2 kg');
      await pumpEventQueue();
      expect(s.bill.lines, hasLength(1));
      expect(speech.said, isEmpty);
    });
  });
}

String _rs(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
