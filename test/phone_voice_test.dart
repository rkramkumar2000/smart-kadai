import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/voice/phone_speech_service.dart';
import 'package:smart_kadai/voice/speech_service.dart';

/// Ram's phone showed Heard: "milk" but nothing reached the bill: the phone
/// never sent a final result.
void main() {
  late List<SpeechResult> out;
  late PhraseAssembler p;
  List<String> finals() => [
    for (final r in out)
      if (r.isFinal) r.text,
  ];

  setUp(() {
    out = [];
    p = PhraseAssembler(out.add);
  });

  test('words with no final result are finished after a pause', () {
    fakeAsync((time) {
      p.add('milk', isFinal: false);
      expect(finals(), isEmpty);
      time.elapse(const Duration(seconds: 2));
      expect(finals(), ['milk']);
    });
  });

  test('a late final result does not add the item twice', () {
    fakeAsync((time) {
      p.add('milk', isFinal: false);
      time.elapse(const Duration(seconds: 2));
      p.add('milk', isFinal: true);
      expect(finals(), ['milk']);
    });
  });

  test('only the new words of a growing result are sent', () {
    fakeAsync((time) {
      p.add('milk', isFinal: false);
      time.elapse(const Duration(seconds: 2));
      p.add('milk sugar', isFinal: false);
      p.add('milk sugar 1 kg', isFinal: false);
      time.elapse(const Duration(seconds: 2));
      expect(finals(), ['milk', 'sugar 1 kg']);
    });
  });

  test('a normal final result goes straight through', () {
    p.add('ரெண்டு முட்டை', isFinal: false);
    p.add(
      'ரெண்டு முட்டை',
      isFinal: true,
      alternatives: ['ரெண்டு முட்டை', 'இரண்டு முட்டை'],
    );
    expect(finals(), ['ரெண்டு முட்டை']);
    expect(out.last.alternatives, hasLength(2));
  });

  test('a new listening session starts fresh', () {
    p.add('milk', isFinal: true);
    p.newSession();
    p.add('milk', isFinal: true);
    expect(finals(), ['milk', 'milk']);
  });

  test('stopping the mic finishes what was heard', () {
    p.add('salt 1 kg', isFinal: false);
    p.flush();
    expect(finals(), ['salt 1 kg']);
  });
}
