import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/database.dart';
import 'printing/bill_printer.dart';
import 'sync/shop_host.dart';
import 'voice/chrome_voice_bridge.dart';
import 'voice/phone_speech_service.dart';
import 'voice/speech_service.dart';
import 'ui/login_screen.dart';
import 'ui/setup_guide.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final linkedFlag = File(p.join(dir.path, 'billing_through_pc'));

  final SpeechService voice;
  if (Platform.isAndroid || Platform.isIOS) {
    // The phone's own Google speech recognition, in Tamil.
    voice = PhoneSpeechService();
  } else {
    // Free voice through Chrome's speech recognition. The helper window
    // opens after login; if Chrome is missing, billing still works by tap
    // and scan.
    final chrome = ChromeVoiceBridge();
    try {
      await chrome.serve();
    } on SocketException {
      // Port busy (another copy running): voice stays off in this copy.
    }
    voice = chrome;
  }
  final host = ShopHost(
    openOwn: () => AppDatabase.open(p.join(dir.path, 'smart_kadai.db')),
    // The shop PC's copy, kept apart from the phone's own shop.
    openLinked: () => AppDatabase.open(p.join(dir.path, 'shop_pc_copy.db')),
    rememberLinked: (on) async {
      if (on) {
        await linkedFlag.writeAsString('1');
      } else if (linkedFlag.existsSync()) {
        await linkedFlag.delete();
      }
    },
    linked: (Platform.isAndroid || Platform.isIOS) && linkedFlag.existsSync(),
    speech: voice,
    isPhone: Platform.isAndroid || Platform.isIOS,
  );
  final s = host.value;
  // Bills from staff phones print on the PC's bill printer if asked.
  s.phoneBillArrived = (id) {
    if (s.repo.setting('print_phone_bills') != '1') return;
    final b = s.savedBill(id);
    if (b != null) printBillDirect(s, b);
  };
  if (!s.isLinkedPhone && s.phonesOn) {
    // The shop PC: phones on the Wi-Fi can send bills again.
    await s.setPhonesOn(true);
  }
  runApp(
    ValueListenableBuilder<AppState>(
      valueListenable: host,
      builder: (_, state, _) =>
          SmartKadaiApp(key: ObjectKey(state), state: state),
    ),
  );
}

class SmartKadaiApp extends StatelessWidget {
  const SmartKadaiApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    UiPrefs.lang.value = UiLang.fromCode(state.repo.setting('ui_lang', 'both'));
    UiPrefs.textScale.value =
        double.tryParse(state.repo.setting('text_scale', '1')) ?? 1;
    return ListenableBuilder(
      listenable: Listenable.merge([UiPrefs.lang, UiPrefs.textScale]),
      builder: (context, _) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      // A new key rebuilds every screen in the chosen language.
      key: ValueKey(UiPrefs.lang.value),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(UiPrefs.textScale.value)),
        child: child!,
      ),
      title: 'Smart Kadai',
      debugShowCheckedModeBanner: false,
      theme: kadaiTheme(),
      // Nobody logged in: the PIN screen. Locking returns here.
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => state.user == null
            ? LoginScreen(key: const ValueKey('login'), state: state)
            : needsSetup(state)
            ? SetupGuide(key: const ValueKey('setup'), state: state)
            : AppShell(key: ValueKey(state.user!.id), state: state),
      ),
    );
  }
}
