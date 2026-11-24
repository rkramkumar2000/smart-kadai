import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/database.dart';
import 'data/shop_repository.dart';
import 'voice/chrome_voice_bridge.dart';
import 'ui/login_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final db = AppDatabase.open(p.join(dir.path, 'smart_kadai.db'));
  final repo = ShopRepository(db)..seedIfEmpty();

  // Free voice through Chrome's speech recognition. The helper window opens
  // with the app; if Chrome is missing, billing still works by tap and scan.
  final voice = ChromeVoiceBridge();
  try {
    await voice.serve();
    await voice.open();
  } on SocketException {
    // Port busy (another copy running): voice stays off in this copy.
  }
  runApp(SmartKadaiApp(state: AppState(repo, speech: voice)));
}

class SmartKadaiApp extends StatelessWidget {
  const SmartKadaiApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Kadai',
      debugShowCheckedModeBanner: false,
      theme: kadaiTheme(),
      // Nobody logged in: the PIN screen. Locking returns here.
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => state.user == null
            ? LoginScreen(key: const ValueKey('login'), state: state)
            : AppShell(key: ValueKey(state.user!.id), state: state),
      ),
    );
  }
}
