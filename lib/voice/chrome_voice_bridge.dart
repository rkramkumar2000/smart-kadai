import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'chrome_helper_page.dart';
import 'speech_service.dart';

/// Free voice billing through Google Chrome's built-in speech recognition.
///
/// The app serves a small page on 127.0.0.1 (this PC only) and opens it in a
/// Chrome app window. Chrome listens to the microphone and streams the words
/// back over a WebSocket, so items appear while the owner speaks.
class ChromeVoiceBridge implements SpeechService {
  ChromeVoiceBridge({this.port = 47811});

  /// Fixed port so Chrome remembers the microphone permission for the page.
  final int port;

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  final _results = StreamController<SpeechResult>.broadcast();
  final _changes = StreamController<void>.broadcast();
  bool _listening = false;
  String? _problem;

  /// Set when the port is taken, usually by another Smart Kadai still open.
  bool portBusy = false;

  @override
  String? get problem => portBusy
      ? 'Another Smart Kadai is already open, so voice is off in this one. '
            'Close all Smart Kadai windows (check the taskbar) and start again.'
      : _problem;

  static String? _explain(String code) => switch (code) {
    'not-allowed' || 'service-not-allowed' =>
      'The microphone is blocked. In the Chrome voice window, click the icon '
          'left of the address, set Microphone to Allow, then click Speak.',
    'audio-capture' =>
      'No microphone found. Plug in a microphone or headset and click Speak.',
    'network' => 'Chrome needs internet for speech. Check the connection.',
    'no-speech' =>
      'Nothing was heard. Check the microphone is not muted and speak closer.',
    _ => null,
  };

  Uri get pageUrl => Uri.parse('http://127.0.0.1:${_server?.port ?? port}/');

  /// Starts the local server. Safe to call more than once.
  Future<void> serve() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      portBusy = true;
      rethrow;
    }
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(HttpRequest req) async {
    if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      // Only accept the helper page served by this app.
      final origin = req.headers.value('origin') ?? '';
      if (origin.isNotEmpty &&
          !origin.startsWith('http://127.0.0.1') &&
          !origin.startsWith('http://localhost')) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      _clients.add(ws);
      _changes.add(null);
      ws.listen(
        (data) => _onMessage(data),
        onDone: () {
          _clients.remove(ws);
          if (_clients.isEmpty) _listening = false;
          _changes.add(null);
        },
        onError: (_) {},
      );
      return;
    }
    if (req.uri.path == '/' || req.uri.path == '/index.html') {
      req.response.headers.contentType = ContentType.html;
      req.response.write(chromeHelperPage);
    } else {
      req.response.statusCode = HttpStatus.notFound;
    }
    await req.response.close();
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final m = decoded;
    if (m['type'] == 'partial' || m['type'] == 'final') _problem = null;
    switch (m['type']) {
      case 'partial':
        final text = '${m['text'] ?? ''}'.trim();
        if (text.isNotEmpty) _results.add(SpeechResult(text, isFinal: false));
      case 'final':
        final text = '${m['text'] ?? ''}'.trim();
        final alts = (m['alternatives'] is List)
            ? (m['alternatives'] as List)
                  .map((a) => '$a'.trim())
                  .where((a) => a.isNotEmpty)
                  .toList()
            : <String>[];
        if (text.isNotEmpty) {
          _results.add(
            SpeechResult(
              text,
              isFinal: true,
              alternatives: alts.isEmpty ? [text] : alts,
            ),
          );
        }
      case 'state':
        _listening = m['listening'] == true;
        if (_listening) _problem = null;
        _changes.add(null);
      case 'error':
        final p = _explain('${m['error'] ?? ''}');
        if (p != null) {
          _problem = p;
          _changes.add(null);
        }
    }
  }

  void _sendAll(Map<String, Object?> msg) {
    final s = jsonEncode(msg);
    for (final c in _clients) {
      c.add(s);
    }
  }

  @override
  bool get isAvailable => _clients.isNotEmpty;

  @override
  bool get isListening => _listening;

  @override
  Stream<SpeechResult> get results => _results.stream;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> start() async => _sendAll({'cmd': 'start'});

  @override
  Future<void> stop() async => _sendAll({'cmd': 'stop'});

  @override
  Future<void> say(String tamil, String english) async =>
      _sendAll({'cmd': 'say', 'ta': tamil, 'en': english});

  /// Opens the helper in a small Chrome app window.
  @override
  Future<void> open() async {
    // The other copy owns the voice window; opening it would send speech there.
    if (portBusy) return;
    await serve();
    final url = pageUrl.toString();
    final chrome = findChrome();
    final args = [
      '--app=$url',
      '--window-size=440,420',
      '--window-position=40,40',
    ];
    try {
      if (chrome != null) {
        await Process.start(chrome, args, mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        await Process.start('cmd', [
          '/c',
          'start',
          'chrome',
          ...args,
        ], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [
          '-a',
          'Google Chrome',
          url,
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      }
    } on ProcessException {
      // Chrome not found; the owner can open the address by hand.
    }
  }

  /// Finds chrome.exe in its usual Windows install folders.
  static String? findChrome() {
    if (!Platform.isWindows) return null;
    final env = Platform.environment;
    final roots = [
      env['PROGRAMFILES'],
      env['PROGRAMFILES(X86)'],
      env['LOCALAPPDATA'],
    ].whereType<String>();
    for (final r in roots) {
      final path = '$r\\Google\\Chrome\\Application\\chrome.exe';
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<void> close() async {
    for (final c in _clients.toList()) {
      await c.close();
    }
    await _server?.close(force: true);
    _server = null;
  }
}
