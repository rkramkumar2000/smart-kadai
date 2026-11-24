import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/printing/bill_printer.dart';
import 'package:smart_kadai/purchases/invoice_reader.dart';

void main() {
  late AppState state;

  setUp(() {
    state = AppState(ShopRepository(AppDatabase.inMemory())..seedIfEmpty());
  });

  test('bill photo reply becomes a draft', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.headers['x-api-key'], 'k');
      final draft = {
        'supplier_name': 'Murugan Traders',
        'supplier_gstin': '33ABCDE1234F1Z5',
        'invoice_no': 'INV-9',
        'invoice_date': '2026-11-20',
        'total': 2310,
        'lines': [
          {
            'name': 'Groundnut 10 KG',
            'quantity': 2,
            'unit': 'BAG',
            'rate': 1100,
            'gst_percent': 5,
            'amount': 2310,
          },
        ],
      };
      return http.Response(
        jsonEncode({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': jsonEncode(draft)},
          ],
        }),
        200,
      );
    });
    final d = await InvoiceReader(
      'k',
      client: client,
    ).read([1, 2, 3], 'image/jpeg');
    expect(sent['model'], 'claude-opus-5-5');
    expect((sent['messages'] as List).first['content'].first['type'], 'image');
    expect(d.supplierName, 'Murugan Traders');
    expect(d.date, DateTime(2026, 11, 20));
    expect(d.lines.single.quantity, 2);

    final guess = state.guessProduct(d.lines.single.name);
    expect(guess?.$1.nameEn, 'Groundnut');
    expect(guess?.$2?.label, '10 KG');
  });

  test('a wrong key gives a plain message', () async {
    final client = MockClient((_) async => http.Response('{}', 401));
    expect(
      () => InvoiceReader('bad', client: client).read([1], 'image/png'),
      throwsA(
        isA<InvoiceReadException>().having(
          (e) => e.message,
          'message',
          contains('Settings'),
        ),
      ),
    );
  });

  test('bill PDF builds for every paper size', () async {
    state.handleTyped('rendu kadalai mittai oru kilo kadalai');
    state.completeBill(PaymentMode.cash);
    final b = state.lastBill!;
    for (final p in BillPaper.values) {
      final bytes = await buildBillPdf(b, ShopHeader(name: 'Ram Stores'), p);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });
}
