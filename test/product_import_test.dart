import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/catalogue/product.dart';
import 'package:smart_kadai/catalogue/product_import.dart';
import 'package:smart_kadai/core/units.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';

void main() {
  late AppState s;
  setUp(() {
    s = AppState(ShopRepository(AppDatabase.inMemory())..seedIfEmpty());
  });

  Product byName(String n) => s.products.firstWhere((p) => p.nameEn == n);

  test('CSV reader handles quotes, commas and Tamil', () {
    final rows = parseCsv(
      '﻿English name,Tamil name\r\n"Rice, Ponni",பொன்னி அரிசி\r\n"Say ""hi""",x',
    );
    expect(rows[1], ['Rice, Ponni', 'பொன்னி அரிசி']);
    expect(rows[2], ['Say "hi"', 'x']);
  });

  test('the sample sheet imports: new products, sizes and update', () {
    final r = s.readProductSheet(parseCsv(importTemplateCsv()));
    expect(r.problems, isEmpty);
    expect(r.products, hasLength(3));
    expect(r.updated, 1); // Groundnut is already in the shop

    final before = byName('Groundnut');
    s.importProducts(r);
    final g = byName('Groundnut');
    expect(g.id, before.id);
    expect(g.variants.map((v) => v.label), ['1 KG', '500 GRAM', '250 GRAM']);
    expect(g.variants[1].stockFactor, 0.5);
    expect(g.stockQty, 25);
    expect(s.repo.stockHistory(g.id).first.note, 'Opening stock');

    final dove = byName('Dove Soap');
    expect(dove.code, startsWith('P'));
    expect(dove.stockQty, 24);
    expect(dove.variants.single.barcode, '8901030000000');
    final chilli = byName('Aachi Chilli Powder');
    expect(chilli.stockUnit, Unit.packet);

    // Voice and barcode know the new products at once.
    s.handleSpoken('ரெண்டு டவ் சோப்', EntryMethod.voice);
    expect(s.bill.lines.single.product.nameEn, 'Dove Soap');
    s.handleTyped('8901030000000');
    expect(s.bill.lines.single.count, 3);
  });

  test('Tanglish is filled from Tamil, and bad rows are listed', () {
    final r = s.readProductSheet([
      importColumns,
      [
        'Gingelly Oil',
        'நல்லெண்ணெய்',
        '',
        '',
        '',
        'LITRE',
        '1',
        'LITRE',
        '320',
        '',
        '',
        '',
        '',
      ],
      ['Bad Unit', '', '', '', '', '', '1', 'TIN', '10', '', '', '', ''],
      ['No Price', '', '', '', '', '', '1', 'PIECE', '', '', '', '', ''],
      ['', '', '', '', '', '', '', '', '', '', '', '', ''],
    ]);
    expect(r.products.single.nameTanglish, 'Nallenney');
    expect(r.problems, hasLength(2));
    expect(r.problems.first, contains('TIN'));
  });

  test('stop selling products that are not in the sheet', () {
    final r = s.readProductSheet(parseCsv(importTemplateCsv()));
    s.importProducts(r, hideOthers: true);
    expect(s.activeProducts.map((p) => p.nameEn).toSet(), {
      'Groundnut',
      'Dove Soap',
      'Aachi Chilli Powder',
    });
  });

  test('reads an Excel .xlsx file', () {
    const shared =
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<si><t>English name</t></si><si><t>Selling price</t></si>'
        '<si><t>Size unit</t></si><si><t>Boost</t></si><si><t>PACKET</t></si></sst>';
    const sheet =
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>'
        '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2"><v>245</v></c><c r="C2" t="s"><v>4</v></c></row>'
        '</sheetData></worksheet>';
    final a = Archive()
      ..addFile(ArchiveFile.string('xl/sharedStrings.xml', shared))
      ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet));
    final rows = parseXlsx(ZipEncoder().encode(a));
    expect(rows[1], ['Boost', '245', 'PACKET']);
    final r = s.readProductSheet(rows);
    expect(r.products.single.variants.single.sellingPrice, 245);
    expect(utf8.encode('ok'), isNotEmpty);
  });
}
