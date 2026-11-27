import 'dart:convert';

import 'package:http/http.dart' as http;

/// One line read from a supplier bill photo, before the owner checks it.
class InvoiceLineDraft {
  InvoiceLineDraft({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.rate,
    required this.gstPercent,
    required this.amount,
  });

  final String name;
  final double quantity;
  final String unit;
  final double rate;
  final double gstPercent;
  final double amount;

  factory InvoiceLineDraft.fromJson(Map<String, dynamic> j) => InvoiceLineDraft(
    name: '${j['name'] ?? ''}',
    quantity: _num(j['quantity']),
    unit: '${j['unit'] ?? ''}',
    rate: _num(j['rate']),
    gstPercent: _num(j['gst_percent']),
    amount: _num(j['amount']),
  );
}

/// What was read from a supplier bill.
class InvoiceDraft {
  InvoiceDraft({
    required this.supplierName,
    required this.gstin,
    required this.invoiceNo,
    required this.date,
    required this.total,
    required this.lines,
  });

  final String supplierName;
  final String gstin;
  final String invoiceNo;
  final DateTime? date;
  final double total;
  final List<InvoiceLineDraft> lines;

  factory InvoiceDraft.fromJson(Map<String, dynamic> j) => InvoiceDraft(
    supplierName: '${j['supplier_name'] ?? ''}',
    gstin: '${j['supplier_gstin'] ?? ''}',
    invoiceNo: '${j['invoice_no'] ?? ''}',
    date: DateTime.tryParse('${j['invoice_date'] ?? ''}'),
    total: _num(j['total']),
    lines: [
      for (final l in (j['lines'] as List? ?? const []))
        InvoiceLineDraft.fromJson(l as Map<String, dynamic>),
    ],
  );
}

class InvoiceReadException implements Exception {
  InvoiceReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

double _num(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s.replaceAll(',', '')) ?? 0,
  _ => 0,
};

/// Reads a photo or PDF of a supplier bill with Claude and returns its lines.
/// The owner always checks the result before anything is saved.
class InvoiceReader {
  InvoiceReader(this.apiKey, {http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const model = 'claude-opus-5-5';
  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  static const _schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'supplier_name',
      'supplier_gstin',
      'invoice_no',
      'invoice_date',
      'total',
      'lines',
    ],
    'properties': {
      'supplier_name': {'type': 'string'},
      'supplier_gstin': {'type': 'string'},
      'invoice_no': {'type': 'string'},
      'invoice_date': {
        'type': 'string',
        'description': 'YYYY-MM-DD, or empty if not printed',
      },
      'total': {'type': 'number'},
      'lines': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'name',
            'quantity',
            'unit',
            'rate',
            'gst_percent',
            'amount',
          ],
          'properties': {
            'name': {'type': 'string'},
            'quantity': {'type': 'number'},
            'unit': {'type': 'string'},
            'rate': {'type': 'number'},
            'gst_percent': {'type': 'number'},
            'amount': {'type': 'number'},
          },
        },
      },
    },
  };

  static const _prompt = '''
This is a supplier bill (purchase invoice) for a grocery shop in Tamil Nadu. It may be printed or handwritten, in English or Tamil.

Read every item line. For each line give:
- name: the product name as written, including the pack size if it is part of the name (for example "Groundnut 10 KG" or "Hamam Soap Box").
- quantity: how many packs or units were bought, as a number.
- unit: the unit of that quantity as written (KG, BAG, BOX, PCS, LTR and so on), or empty.
- rate: price for one unit before GST. If only a rate including GST is shown, give that and set gst_percent to 0.
- gst_percent: GST rate for the line, 0 if not shown.
- amount: the line amount as printed.

Also give the supplier name, the supplier GSTIN (empty if none), the bill number, the bill date as YYYY-MM-DD, and the bill total as printed.

Use empty strings and 0 for anything you cannot read. Do not guess items that are not on the bill.''';

  /// [mediaType] is image/jpeg, image/png, image/webp or application/pdf.
  Future<InvoiceDraft> read(List<int> bytes, String mediaType) async {
    final data = base64Encode(bytes);
    final source = {'type': 'base64', 'media_type': mediaType, 'data': data};
    final body = {
      'model': model,
      'max_tokens': 16000,
      'output_config': {
        'effort': 'medium',
        'format': {'type': 'json_schema', 'schema': _schema},
      },
      'fallbacks': 'default',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': mediaType == 'application/pdf' ? 'document' : 'image',
              'source': source,
            },
            {'type': 'text', 'text': _prompt},
          ],
        },
      ],
    };
    final http.Response res;
    try {
      res = await _client
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2026-10-21',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 3));
    } on Exception {
      throw InvoiceReadException(
        'Could not reach the internet. Check the connection and try again.',
      );
    }
    if (res.statusCode == 401) {
      throw InvoiceReadException(
        'The AI key is not right. Check it in Settings.',
      );
    }
    if (res.statusCode == 429 || res.statusCode >= 500) {
      throw InvoiceReadException('The AI service is busy. Try again soon.');
    }
    if (res.statusCode != 200) {
      throw InvoiceReadException(
        'Could not read the bill (error ${res.statusCode}).',
      );
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final stop = j['stop_reason'];
    if (stop == 'refusal') {
      throw InvoiceReadException('This picture could not be read.');
    }
    if (stop == 'max_tokens') {
      throw InvoiceReadException(
        'The bill is too long to read in one go. Try a photo of half of it.',
      );
    }
    final text = [
      for (final b in (j['content'] as List? ?? const []))
        if (b is Map && b['type'] == 'text') b['text'] as String,
    ].join();
    try {
      return InvoiceDraft.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on FormatException {
      throw InvoiceReadException(
        'Could not read the bill. Try a clearer photo.',
      );
    }
  }

  void close() => _client.close();
}
