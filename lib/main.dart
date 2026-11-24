import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/database.dart';
import 'data/shop_repository.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final db = AppDatabase.open(p.join(dir.path, 'smart_kadai.db'));
  final repo = ShopRepository(db)..seedIfEmpty();
  runApp(SmartKadaiApp(state: AppState(repo)));
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
      home: AppShell(state: state),
    );
  }
}
