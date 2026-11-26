import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_service.dart';

/// Voice on an Android phone: Google's speech recognition built into the
/// phone, in Tamil (ta-IN), and the phone's own voice for replies.
///
/// Android stops listening after a pause, so while the owner has the mic
/// on, this starts it again after every phrase.
class PhoneSpeechService implements SpeechService {
  PhoneSpeechService({SpeechToText? stt, FlutterTts? tts})
    : _stt = stt ?? SpeechToText(),
      _tts = tts ?? FlutterTts();

  final SpeechToText _stt;
  final FlutterTts _tts;
  final _results = StreamController<SpeechResult>.broadcast();
  final _changes = StreamController<void>.broadcast();

  bool _ready = false;
  bool _wanted = false;
  bool _speaking = false;
  String? _problem;
  String _locale = 'ta_IN';
  Timer? _restart;

  @override
  bool get isAvailable => _ready;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  bool get isListening => _wanted;

  @override
  Stream<SpeechResult> get results => _results.stream;

  @override
  String? get problem => _problem;

  void _changed() => _changes.add(null);

  /// Asks for the microphone and checks that Tamil speech is installed.
  @override
  Future<void> open() async {
    if (_ready) return;
    try {
      _ready = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
        finalTimeout: const Duration(milliseconds: 800),
      );
    } catch (_) {
      _ready = false;
    }
    if (!_ready) {
      _problem =
          'Allow the microphone for Smart Kadai in phone Settings, and keep '
          'the Google app installed. · மைக்கை அனுமதியுங்கள்.';
    } else {
      final locales = await _stt.locales();
      final ta = locales.where(
        (l) => l.localeId.toLowerCase().startsWith('ta'),
      );
      if (ta.isNotEmpty) {
        _locale = ta.first.localeId;
        _problem = null;
      } else {
        _locale = 'en_IN';
        _problem =
            'Tamil speech is not installed. Open Google app → Settings → '
            'Voice → Languages and add தமிழ் (இந்தியா).';
      }
      try {
        await _tts.awaitSpeakCompletion(true);
        await _tts.setSpeechRate(0.5);
      } catch (_) {}
    }
    _changed();
  }

  @override
  Future<void> start() async {
    if (!_ready) await open();
    if (!_ready) return;
    _wanted = true;
    _changed();
    await _listen();
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    _restart?.cancel();
    await _stt.stop();
    _changed();
  }

  Future<void> _listen() async {
    if (!_wanted || _speaking || _stt.isListening) return;
    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: _locale,
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(minutes: 1),
        ),
      );
    } catch (_) {
      _again();
    }
  }

  /// Starts listening again shortly, unless the owner switched it off.
  void _again() {
    _restart?.cancel();
    if (!_wanted || _speaking) return;
    _restart = Timer(const Duration(milliseconds: 300), _listen);
  }

  void _onResult(SpeechRecognitionResult r) {
    if (_speaking) return;
    _problem = null;
    final alts = [
      for (final a in r.alternates)
        if (a.recognizedWords.trim().isNotEmpty) a.recognizedWords,
    ];
    _results.add(
      SpeechResult(
        r.recognizedWords,
        isFinal: r.finalResult,
        alternatives: alts,
      ),
    );
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _again();
    }
  }

  void _onError(SpeechRecognitionError e) {
    switch (e.errorMsg) {
      case 'error_no_match' || 'error_speech_timeout':
        break; // Silence at the counter is normal.
      case 'error_permission' || 'error_insufficient_permissions':
        _problem =
            'Allow the microphone for Smart Kadai in phone Settings. · '
            'மைக்கை அனுமதியுங்கள்.';
        _wanted = false;
      case 'error_network' || 'error_network_timeout' || 'error_server':
        _problem =
            'No internet for voice. Turn on mobile data, or install offline '
            'Tamil speech in the Google app. · இணையம் இல்லை.';
      case 'error_language_not_supported' || 'error_language_unavailable':
        _problem =
            'Tamil speech is not installed. Open Google app → Settings → '
            'Voice → Languages and add தமிழ் (இந்தியா).';
    }
    _changed();
    _again();
  }

  /// Says the reply. The mic is off while speaking so it does not hear
  /// itself, then listening starts again.
  @override
  Future<void> say(String tamil, String english) async {
    _speaking = true;
    _restart?.cancel();
    try {
      if (_stt.isListening) await _stt.stop();
      final hasTamil = await _tts.isLanguageAvailable('ta-IN') == true;
      await _tts.setLanguage(hasTamil ? 'ta-IN' : 'en-IN');
      await _tts.speak(hasTamil ? tamil : english);
    } catch (_) {
      // No voice engine: the reply is skipped, billing goes on.
    } finally {
      _speaking = false;
      _again();
    }
  }
}
