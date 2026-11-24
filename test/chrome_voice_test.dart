import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/voice/chrome_voice_bridge.dart';

void main() {
  late ChromeVoiceBridge bridge;
  late AppState state;
  late ShopRepository repo;

  setUp(() async {
    bridge = ChromeVoiceBridge(port: 0);
    await bridge.serve();
    repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    state = AppState(repo, speech: bridge);
  });

  tearDown(() async {
    state.dispose();
    await bridge.close();
  });

  Future<WebSocket> connectHelper() async {
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${bridge.pageUrl.port}/ws',
      headers: {'origin': 'http://127.0.0.1:${bridge.pageUrl.port}'},
    );
    await _settle();
    return ws;
  }

  test('serves the helper page', () async {
    final client = HttpClient();
    final res = await (await client.getUrl(bridge.pageUrl)).close();
    final body = await res.transform(utf8.decoder).join();
    expect(res.statusCode, 200);
    expect(body, contains('webkitSpeechRecognition'));
    expect(body, contains("'ta-IN'"));
    client.close();
  });

  test('voice is ready only while the Chrome window is connected', () async {
    expect(state.voiceReady, isFalse);
    final ws = await connectHelper();
    expect(state.voiceReady, isTrue);
    await ws.close();
    await _settle();
    expect(state.voiceReady, isFalse);
  });

  test('partial words show live, final words go on the bill', () async {
    final ws = await connectHelper();
    ws.add(jsonEncode({'type': 'partial', 'text': 'ரெண்டு கடலை'}));
    await _settle();
    expect(state.heard, 'ரெண்டு கடலை');
    expect(state.bill.lines, isEmpty);

    ws.add(
      jsonEncode({
        'type': 'final',
        'text': 'ரெண்டு கடலை மிட்டாய்',
        'alternatives': ['ரெண்டு கடலை மிட்டாய்'],
      }),
    );
    await _settle();
    expect(state.bill.lines.single.product.nameEn, 'Groundnut Candy');
    expect(state.bill.lines.single.count, 2);

    final log = repo.recentVoiceLog();
    expect(log.single['heard'], 'ரெண்டு கடலை மிட்டாய்');
    expect(log.single['sure_items'], 1);
    await ws.close();
  });

  test('a better second guess from Chrome is used', () async {
    final ws = await connectHelper();
    ws.add(
      jsonEncode({
        'type': 'final',
        'text': 'two hammer soup',
        'alternatives': ['two hammer soup', 'two hamam soap'],
      }),
    );
    await _settle();
    expect(state.bill.lines.single.product.nameEn, 'Hamam Soap');
    expect(repo.recentVoiceLog().single['used_text'], 'two hamam soap');
    await ws.close();
  });

  test('F2 sends start and stop to the Chrome window', () async {
    final ws = await connectHelper();
    final got = <String>[];
    ws.listen((m) => got.add(m as String));
    await state.toggleListening();
    await _settle();
    expect(got.last, contains('start'));
    ws.add(jsonEncode({'type': 'state', 'listening': true}));
    await _settle();
    expect(state.listening, isTrue);
    await state.toggleListening();
    await _settle();
    expect(got.last, contains('stop'));
    await ws.close();
  });

  test('a blocked or missing microphone is explained in plain words', () async {
    final ws = await connectHelper();
    expect(state.voiceProblem, isNull);
    ws.add(jsonEncode({'type': 'error', 'error': 'not-allowed'}));
    await _settle();
    expect(state.voiceProblem, contains('blocked'));
    ws.add(jsonEncode({'type': 'error', 'error': 'audio-capture'}));
    await _settle();
    expect(state.voiceProblem, contains('No microphone'));
    ws.add(jsonEncode({'type': 'state', 'listening': true}));
    await _settle();
    expect(state.voiceProblem, isNull);
    await ws.close();
  });

  test('a second copy says another Smart Kadai is open', () async {
    final second = ChromeVoiceBridge(port: bridge.pageUrl.port);
    await expectLater(second.serve(), throwsA(isA<SocketException>()));
    expect(second.problem, contains('Another Smart Kadai'));
  });

  test('rejects pages from other websites', () async {
    expect(
      () => WebSocket.connect(
        'ws://127.0.0.1:${bridge.pageUrl.port}/ws',
        headers: {'origin': 'https://evil.example'},
      ),
      throwsA(isA<WebSocketException>()),
    );
  });
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));
