import 'dart:async';

/// Words heard so far. [isFinal] is true once the speaker paused and the
/// service will not change this text any more.
class SpeechResult {
  SpeechResult(this.text, {required this.isFinal});
  final String text;
  final bool isFinal;
}

/// A streaming speech-to-text service for Tamil, English and Tanglish.
///
/// The app only depends on this interface. Which cloud or on-device service
/// sits behind it is decided by the phase 0 test on real shop recordings
/// (candidates: Sarvam AI, Google Cloud Speech-to-Text, AI4Bharat
/// IndicConformer). Partial results must stream while the owner is still
/// speaking so items appear on the bill without waiting.
abstract class SpeechService {
  /// False until a service is configured in Settings.
  bool get isAvailable;

  /// Partial and final results while listening.
  Stream<SpeechResult> get results;

  Future<void> start();
  Future<void> stop();
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
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
