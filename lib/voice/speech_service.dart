import 'dart:async';

/// Words heard so far. [isFinal] is true once the speaker paused and the
/// service will not change this text any more.
class SpeechResult {
  SpeechResult(
    this.text, {
    required this.isFinal,
    this.alternatives = const [],
  });
  final String text;
  final bool isFinal;

  /// Other ways the service thought the words could be heard, best first.
  /// Includes [text].
  final List<String> alternatives;
}

/// A streaming speech-to-text service for Tamil, English and Tanglish.
///
/// The app only depends on this interface. Which cloud or on-device service
/// sits behind it is decided by the phase 0 test on real shop recordings
/// (candidates: Sarvam AI, Google Cloud Speech-to-Text, AI4Bharat
/// IndicConformer). Partial results must stream while the owner is still
/// speaking so items appear on the bill without waiting.
abstract class SpeechService {
  /// False until a service is configured and ready.
  bool get isAvailable;

  /// Changes whenever [isAvailable] or the listening state changes.
  Stream<void> get changes;

  /// True while the microphone is on.
  bool get isListening;

  /// Shows the service's window if it has one (the Chrome helper).
  Future<void> open();

  /// Partial and final results while listening.
  Stream<SpeechResult> get results;

  Future<void> start();
  Future<void> stop();

  /// Why voice is not working right now, in plain words. Null when fine.
  String? get problem => null;
}

/// Used until a real service is configured. The owner can still type or
/// scan, and testers can type what was said to try the voice parser.
class NoSpeechService implements SpeechService {
  final _controller = StreamController<SpeechResult>.broadcast();

  @override
  bool get isAvailable => false;

  @override
  Stream<SpeechResult> get results => _controller.stream;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  bool get isListening => false;

  @override
  Future<void> open() async {}

  @override
  Future<void> start() async {}

  @override
  String? get problem => null;

  @override
  Future<void> stop() async {}
}
