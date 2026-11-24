import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../catalogue/product_import.dart';
import 'theme.dart';

/// Saves the sample product sheet for the owner to fill in Excel.
Future<void> saveProductTemplate(BuildContext context) async {
  final loc = await getSaveLocation(
    suggestedName: 'smart-kadai-products.csv',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Excel (CSV)', extensions: ['csv']),
    ],
  );
  if (loc == null) return;
  // The byte-order mark makes Excel show Tamil names correctly.
  await File(loc.path)
      .writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(importTemplateCsv())]);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(
        'Saved ${loc.path}. Open it in Excel, replace the example rows with '
        'your products, save, then click Import from Excel.',
        style: const TextStyle(fontSize: 15),
      ),
    ),
  );
}

/// Picks a filled sheet, shows what will change, and imports on OK.
Future<void> importProductsFlow(BuildContext context, AppState s) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Excel or CSV', extensions: ['xlsx', 'csv']),
    ],
  );
  if (file == null || !context.mounted) return;
  final bytes = await file.readAsBytes();
  List<List<String>> rows;
  try {
    rows = file.name.toLowerCase().endsWith('.xlsx')
        ? parseXlsx(bytes)
        : parseCsv(utf8.decode(bytes, allowMalformed: true));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not read that file. Save it from Excel as .xlsx or CSV UTF-8.',
        ),
      ),
    );
    return;
  }
  final r = s.readProductSheet(rows);
  if (!context.mounted) return;
  var hideOthers = false;
  final added = r.products.length - r.updated;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Import products'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$added new products, ${r.updated} updated',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Products with the same English name as one already in the '
                'shop are updated, not copied.',
                style: TextStyle(color: KadaiColors.quiet),
              ),
              if (r.problems.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${r.problems.length} rows skipped:',
                  style: const TextStyle(
                    color: KadaiColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in r.problems)
                        Text(p, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: hideOthers,
                onChanged: (v) => setLocal(() => hideOthers = v ?? false),
                title: const Text(
                  'Stop selling products that are not in this sheet',
                ),
                subtitle: const Text(
                  'Use this to remove the 15 sample products. Their bills stay.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: r.products.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: Text('Import ${r.products.length} products'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  s.importProducts(r, hideOthers: hideOthers);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Imported ${r.products.length} products. Voice knows them now.',
        style: const TextStyle(fontSize: 15),
      ),
    ),
  );
}
