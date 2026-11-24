import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../core/units.dart';
import '../voice/phonetic.dart';
import 'product.dart';

/// Columns of the product sheet, in order. One row per selling size; rows
/// with the same English name become one product with several sizes.
const importColumns = [
  'English name',
  'Tamil name',
  'Tanglish name',
  'Category',
  'Brand',
  'Stock unit',
  'Size',
  'Size unit',
  'Selling price',
  'Purchase price',
  'Barcode',
  'Stock',
  'Minimum stock',
];

/// A sheet the owner can fill in Excel, with example rows.
String importTemplateCsv() {
  final rows = [
    importColumns,
    [
      'Groundnut', 'கடலை', 'Kadalai', 'Pulses', '', 'KG', '1', 'KG', //
      '140', '120', '', '25', '5',
    ],
    [
      'Groundnut', '', '', '', '', '', '500', 'GRAM', '72', '61', '', '', '', //
    ],
    [
      'Groundnut', '', '', '', '', '', '250', 'GRAM', '37', '31', '', '', '', //
    ],
    [
      'Dove Soap', 'டவ் சோப்', 'Dove', 'Soap', 'Dove', 'PIECE', '1', //
      'PIECE', '55', '47', '8901030000000', '24', '6',
    ],
    [
      'Aachi Chilli Powder', 'ஆச்சி மிளகாய் தூள்', 'Milagai thool', //
      'Masala', 'Aachi', 'PACKET', '1', 'PACKET', '45', '38', '', '20', '5',
    ],
  ];
  return rows.map((r) => r.map(_csvCell).join(',')).join('\r\n');
}

String _csvCell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp(r'[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Reads a CSV saved from Excel. Handles quotes, commas and line breaks
/// inside cells, and the byte-order mark Excel adds.
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',' || c == ';' || c == '\t') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// Reads the first sheet of an Excel .xlsx file.
List<List<String>> parseXlsx(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? read(String name) {
    final f = zip.findFile(name);
    return f == null ? null : utf8.decode(f.content as List<int>);
  }

  final shared = <String>[];
  final ss = read('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  final sheetName =
      zip.files
          .map((f) => f.name)
          .where((n) => n.startsWith('xl/worksheets/sheet'))
          .toList()
        ..sort();
  if (sheetName.isEmpty) throw const FormatException('No sheet in the file');
  final sheet = XmlDocument.parse(read(sheetName.first)!);
  final rows = <List<String>>[];
  for (final r in sheet.findAllElements('row')) {
    final cells = <String>[];
    for (final c in r.findElements('c')) {
      final ref = c.getAttribute('r') ?? '';
      final col = _colIndex(ref);
      while (cells.length < col) {
        cells.add('');
      }
      final type = c.getAttribute('t');
      String value;
      if (type == 's') {
        final i = int.tryParse(c.getElement('v')?.innerText ?? '') ?? -1;
        value = i >= 0 && i < shared.length ? shared[i] : '';
      } else if (type == 'inlineStr') {
        value = c.findAllElements('t').map((t) => t.innerText).join();
      } else {
        value = c.getElement('v')?.innerText ?? '';
      }
      cells.add(value);
    }
    rows.add(cells);
  }
  return rows;
}

int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n == 0 ? 0 : n - 1;
}

/// The result of reading a sheet: products ready to save, and the rows that
/// could not be read, with the reason.
class ImportResult {
  ImportResult(this.products, this.problems, this.updated);
  final List<Product> products;
  final List<String> problems;

  /// How many of [products] replace a product already in the shop.
  final int updated;
}

const _unitWords = {
  'KG': Unit.kg, 'KGS': Unit.kg, 'KILO': Unit.kg, 'G': Unit.gram, //
  'GM': Unit.gram, 'GMS': Unit.gram, 'GRAM': Unit.gram, 'GRAMS': Unit.gram,
  'L': Unit.litre, 'LTR': Unit.litre, 'LITRE': Unit.litre, 'LITER': Unit.litre,
  'ML': Unit.ml, 'PIECE': Unit.piece, 'PCS': Unit.piece, 'PC': Unit.piece,
  'NOS': Unit.piece, 'PACKET': Unit.packet, 'PKT': Unit.packet,
  'PACK': Unit.packet, 'BOX': Unit.box, 'DOZEN': Unit.dozen, 'DOZ': Unit.dozen,
  'BAG': Unit.bag,
};

Unit? _unit(String s) => _unitWords[s.trim().toUpperCase()];

double? _num(String s) {
  final t = s.replaceAll(RegExp(r'[₹,\s]'), '').replaceAll('Rs.', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Turns sheet rows into products. Rows with the same English name are one
/// product with several sizes; a name already in the shop updates that
/// product (prices, sizes, stock) instead of making a copy.
ImportResult buildImport(
  List<List<String>> rows,
  List<Product> existing, {
  required String Function() newId,
  required String Function() nextCode,
}) {
  final problems = <String>[];
  if (rows.isEmpty) return ImportResult([], ['The file is empty'], 0);

  // Find columns by header name, so the owner can reorder or drop columns.
  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(String name) => header.indexOf(name.toLowerCase());
  final idx = {for (final c in importColumns) c: col(c)};
  if (idx['English name']! < 0) {
    return ImportResult([], [
      'The first row must have the column names. Download the sample sheet '
          'and keep its first row.',
    ], 0);
  }
  String cell(List<String> r, String name) {
    final i = idx[name]!;
    return i >= 0 && i < r.length ? r[i].trim() : '';
  }

  final byName = <String, Product>{
    for (final p in existing) p.nameEn.trim().toLowerCase(): p,
  };
  final order = <String>[];
  final groups = <String, List<(int, List<String>)>>{};
  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    if (r.every((c) => c.trim().isEmpty)) continue;
    final name = cell(r, 'English name');
    if (name.isEmpty) {
      problems.add('Row ${i + 1}: no English name');
      continue;
    }
    final key = name.toLowerCase();
    if (!groups.containsKey(key)) order.add(key);
    groups.putIfAbsent(key, () => []).add((i + 1, r));
  }

  final out = <Product>[];
  var updated = 0;
  final now = DateTime.now();
  for (final key in order) {
    final g = groups[key]!;
    final first = g.first.$2;
    String firstNonEmpty(String name) => g
        .map((e) => cell(e.$2, name))
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');

    final old = byName[key];
    final nameEn = cell(first, 'English name');
    final nameTa = firstNonEmpty('Tamil name');
    var tanglish = firstNonEmpty('Tanglish name');
    if (tanglish.isEmpty && nameTa.isNotEmpty) {
      tanglish = _capitalise(transliterateTamil(nameTa));
    }

    // Sizes.
    final sizes = <(Unit, double, double, double, String)>[];
    var bad = false;
    for (final (rowNo, r) in g) {
      final unitText = cell(r, 'Size unit');
      final u = _unit(unitText.isEmpty ? cell(r, 'Stock unit') : unitText);
      final qty = _num(cell(r, 'Size')) ?? 1;
      final sell = _num(cell(r, 'Selling price'));
      if (u == null) {
        problems.add(
          'Row $rowNo ($nameEn): unit "$unitText" not known. Use KG, GRAM, '
          'LITRE, ML, PIECE, PACKET, BOX, DOZEN or BAG.',
        );
        bad = true;
        continue;
      }
      if (sell == null || sell <= 0) {
        problems.add('Row $rowNo ($nameEn): no selling price');
        bad = true;
        continue;
      }
      final buy = _num(cell(r, 'Purchase price')) ?? 0;
      sizes.add((u, qty, sell, buy, cell(r, 'Barcode')));
    }
    if (sizes.isEmpty) {
      if (!bad) problems.add('$nameEn: no size with a price');
      continue;
    }

    final stockUnitText = firstNonEmpty('Stock unit');
    final stockUnit =
        _unit(stockUnitText) ?? old?.stockUnit ?? _baseUnit(sizes.first.$1);
    final id = old?.id ?? newId();
    final variants = <ProductVariant>[];
    for (final (i, s) in sizes.indexed) {
      final (u, qty, sell, buy, barcode) = s;
      final factor =
          ProductVariant.autoStockFactor(u, qty, stockUnit) ??
          (u == stockUnit ? qty : 1);
      final match = old?.variants.where(
        (v) => v.unit == u && v.quantity == qty,
      );
      variants.add(
        ProductVariant(
          id: (match != null && match.isNotEmpty) ? match.first.id : newId(),
          productId: id,
          unit: u,
          quantity: qty,
          stockFactor: factor,
          sellingPrice: sell,
          purchasePrice: buy,
          barcode: barcode.isEmpty ? null : barcode,
          isDefault: i == 0,
          sort: i,
        ),
      );
    }
    // Price per stock unit, from the first size.
    final f = variants.first.stockFactor == 0 ? 1 : variants.first.stockFactor;
    final stockText = firstNonEmpty('Stock');
    final minText = firstNonEmpty('Minimum stock');
    out.add(
      Product(
        id: id,
        code: old?.code ?? nextCode(),
        nameEn: nameEn,
        nameTa: nameTa.isNotEmpty ? nameTa : (old?.nameTa ?? ''),
        nameTanglish: tanglish.isNotEmpty
            ? tanglish
            : (old?.nameTanglish ?? ''),
        category: firstNonEmpty('Category').isNotEmpty
            ? firstNonEmpty('Category')
            : (old?.category ?? ''),
        brand: firstNonEmpty('Brand').isNotEmpty
            ? firstNonEmpty('Brand')
            : (old?.brand ?? ''),
        stockUnit: stockUnit,
        sellingPrice: roundQty(variants.first.sellingPrice / f),
        purchasePrice: roundQty(variants.first.purchasePrice / f),
        minStock: _num(minText) ?? old?.minStock ?? 0,
        stockQty: _num(stockText) ?? old?.stockQty ?? 0,
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
        variants: variants,
      ),
    );
    if (old != null) updated++;
  }
  return ImportResult(out, problems, updated);
}

Unit _baseUnit(Unit u) => switch (u) {
  Unit.gram || Unit.kg => Unit.kg,
  Unit.ml || Unit.litre => Unit.litre,
  _ => u,
};

String _capitalise(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
