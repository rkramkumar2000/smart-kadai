// Serves the Chrome voice helper without the desktop app and prints what it
// hears. Run: dart run tool/voice_helper_preview.dart, then open the address.
import 'dart:io';

import 'package:smart_kadai/voice/chrome_voice_bridge.dart';

Future<void> main() async {
  final bridge = ChromeVoiceBridge();
  await bridge.serve();
  stdout.writeln('Voice helper at ${bridge.pageUrl}');
  bridge.results.listen(
    (r) => stdout.writeln(
      '${r.isFinal ? 'FINAL' : 'partial'}: ${r.text} ${r.alternatives}',
    ),
  );
  bridge.changes.listen(
    (_) => stdout.writeln('connected: ${bridge.isAvailable}'),
  );
}
