import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// True on Android and iPhone, where there is no "Save as" window.
bool get isPhone => Platform.isAndroid || Platform.isIOS;

/// Writes a file the owner keeps. On the PC this asks where to save it.
/// On a phone the file is made in the app's folder and the share sheet
/// opens, so the owner can send it to WhatsApp, Drive or email.
///
/// Returns where it was saved, or null when the owner cancelled.
Future<String?> saveOrShare(
  BuildContext context, {
  required String name,
  required Future<void> Function(String path) write,
  String label = 'File',
  List<String> extensions = const [],
}) async {
  if (isPhone) {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, name);
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    await write(path);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: name),
    );
    return path;
  }
  final loc = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      if (extensions.isNotEmpty)
        XTypeGroup(label: label, extensions: extensions),
    ],
  );
  if (loc == null) return null;
  final f = File(loc.path);
  if (f.existsSync()) f.deleteSync();
  await write(loc.path);
  return loc.path;
}

/// A CSV that Excel opens with Tamil letters intact.
Future<String?> saveCsv(BuildContext context, String name, String csv) =>
    saveOrShare(
      context,
      name: name,
      label: 'Excel (CSV)',
      extensions: const ['csv'],
      write: (path) =>
          File(path).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]),
    );
