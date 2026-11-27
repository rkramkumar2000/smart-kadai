import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../app_state.dart';
import '../billing/bill.dart';
import '../core/units.dart';

/// Paper sizes for the bill: thermal rolls or a normal A5 sheet.
enum BillPaper {
  roll58('58mm', '58 mm roll'),
  roll80('80mm', '80 mm roll'),
  a5('A5', 'A5 sheet');

  const BillPaper(this.code, this.label);
  final String code;
  final String label;

  static BillPaper fromCode(String c) =>
      values.firstWhere((p) => p.code == c, orElse: () => BillPaper.roll80);

  PdfPageFormat get format => switch (this) {
    BillPaper.roll58 => PdfPageFormat.roll57,
    BillPaper.roll80 => PdfPageFormat.roll80,
    BillPaper.a5 => PdfPageFormat.a5,
  };
}

/// Shop details printed at the top of every bill.
class ShopHeader {
  ShopHeader({
    required this.name,
    this.address = '',
    this.phone = '',
    this.gstin = '',
    this.footer = 'Thank you. Visit again!',
    this.upiId = '',
  });

  final String name;
  final String address;
  final String phone;
  final String gstin;
  final String footer;

  /// Printed as a QR code on credit bills so the customer can pay later.
  final String upiId;
}

/// Builds the customer bill as a PDF. Product names are printed in English,
/// which every thermal printer driver renders correctly.
Future<Uint8List> buildBillPdf(
  SavedBill b,
  ShopHeader shop,
  BillPaper paper, {
  double? balanceDue,
}) async {
  final doc = pw.Document();
  final narrow = paper == BillPaper.roll58;
  final small = pw.TextStyle(fontSize: narrow ? 7 : 8);
  final body = pw.TextStyle(fontSize: narrow ? 8 : 9);
  final bold = pw.TextStyle(
    fontSize: narrow ? 8 : 9,
    fontWeight: pw.FontWeight.bold,
  );
  String money(double v) =>
      'Rs.${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';
  final d = b.at;
  final when =
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final margin = paper == BillPaper.a5
      ? const pw.EdgeInsets.all(24)
      : const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8);
  final format = paper.format.copyWith(
    marginLeft: 0,
    marginRight: 0,
    marginTop: 0,
    marginBottom: 0,
  );

  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: margin,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            shop.name,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: narrow ? 11 : 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (shop.address.isNotEmpty)
            pw.Text(shop.address, textAlign: pw.TextAlign.center, style: small),
          if (shop.phone.isNotEmpty)
            pw.Text(
              'Ph: ${shop.phone}',
              textAlign: pw.TextAlign.center,
              style: small,
            ),
          if (shop.gstin.isNotEmpty)
            pw.Text(
              'GSTIN: ${shop.gstin}',
              textAlign: pw.TextAlign.center,
              style: small,
            ),
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Bill ${b.label}', style: bold),
              pw.Text(when, style: small),
            ],
          ),
          if (b.cashier.isNotEmpty) pw.Text('By ${b.cashier}', style: small),
          if (b.bill.customerName.isNotEmpty)
            pw.Text('Customer: ${_latin(b.bill.customerName)}', style: body),
          pw.Divider(thickness: 0.5),
          for (final l in b.bill.lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text('${l.product.nameEn} ${l.unitLabel}', style: body),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '  ${l.variant == null ? l.product.stockUnit.format(l.count) : formatQty(l.count)}'
                        ' x ${money(l.unitPrice)}',
                        style: small,
                      ),
                      pw.Text(money(l.total), style: body),
                    ],
                  ),
                ],
              ),
            ),
          pw.Divider(thickness: 0.5),
          if (b.bill.discount > 0) ...[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Subtotal', style: body),
                pw.Text(money(b.bill.subtotal), style: body),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Discount', style: body),
                pw.Text('- ${money(b.bill.discount)}', style: body),
              ],
            ),
          ],
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  fontSize: narrow ? 10 : 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                money(b.bill.total),
                style: pw.TextStyle(
                  fontSize: narrow ? 10 : 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Text(
            '${b.bill.lines.length} items - Paid by ${b.mode.label}',
            style: small,
          ),
          if (balanceDue != null && balanceDue > 0)
            pw.Text('Total due now: ${money(balanceDue)}', style: bold),
          if (shop.upiId.isNotEmpty && b.mode == PaymentMode.credit) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data:
                    'upi://pay?pa=${Uri.encodeComponent(shop.upiId)}'
                    '&pn=${Uri.encodeComponent(shop.name)}&cu=INR',
                width: narrow ? 70 : 90,
                height: narrow ? 70 : 90,
              ),
            ),
            pw.Text(
              'Pay by UPI: ${shop.upiId}',
              textAlign: pw.TextAlign.center,
              style: small,
            ),
          ],
          pw.SizedBox(height: 6),
          pw.Text(shop.footer, textAlign: pw.TextAlign.center, style: small),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Opens the Windows print dialog for the bill. Pick the thermal printer,
/// or "Microsoft Print to PDF" to save it.
Future<bool> printBill(AppState s, SavedBill b) {
  final shop = ShopHeader(
    name: s.shopName,
    address: s.repo.setting('shop_address'),
    phone: s.repo.setting('shop_phone'),
    gstin: s.repo.setting('shop_gstin'),
    footer: s.repo.setting('bill_footer', 'Thank you. Visit again!'),
    upiId: s.repo.setting('upi_id'),
  );
  final cid = b.bill.customerId;
  final due = cid == null ? null : s.customers.byId(cid)?.balance;
  final paper = BillPaper.fromCode(s.repo.setting('bill_paper', '80mm'));
  return Printing.layoutPdf(
    name: 'Bill ${b.label}',
    format: paper.format,
    onLayout: (_) => buildBillPdf(b, shop, paper, balanceDue: due),
  );
}

/// Prints straight to the PC's default printer with no dialog, for bills
/// sent by staff phones. Opens the print dialog if no printer is set.
Future<bool> printBillDirect(AppState s, SavedBill b) async {
  try {
    final printers = await Printing.listPrinters();
    final def = printers.where((p) => p.isDefault).firstOrNull;
    if (def != null) {
      final paper = BillPaper.fromCode(s.repo.setting('bill_paper', '80mm'));
      final cid = b.bill.customerId;
      return await Printing.directPrintPdf(
        printer: def,
        name: 'Bill ${b.label}',
        format: paper.format,
        onLayout: (_) => buildBillPdf(
          b,
          _shop(s),
          paper,
          balanceDue: cid == null ? null : s.customers.byId(cid)?.balance,
        ),
      );
    }
  } on Object {
    // Fall back to the dialog.
  }
  return printBill(s, b);
}

ShopHeader _shop(AppState s) => ShopHeader(
  name: s.shopName,
  address: s.repo.setting('shop_address'),
  phone: s.repo.setting('shop_phone'),
  gstin: s.repo.setting('shop_gstin'),
  footer: s.repo.setting('bill_footer', 'Thank you. Visit again!'),
  upiId: s.repo.setting('upi_id'),
);

/// Printer fonts have only English letters; other letters become "?".
String _latin(String t) => t.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

/// The bill as a WhatsApp message, in English and Tamil.
String billText(SavedBill b, String shopName) {
  String money(double v) => v == v.roundToDouble()
      ? '₹${v.toStringAsFixed(0)}'
      : '₹${v.toStringAsFixed(2)}';
  final d = b.at;
  final out = StringBuffer()
    ..writeln('*$shopName*')
    ..writeln(
      'Bill ${b.label} · ${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}',
    )
    ..writeln();
  for (final l in b.bill.lines) {
    out.writeln(
      '${l.product.nameEn} (${l.product.nameTa}) ${l.unitLabel} ${l.quantityLabel} = ${money(l.total)}',
    );
  }
  out.writeln();
  if (b.bill.discount > 0) {
    out.writeln('Discount: -${money(b.bill.discount)}');
  }
  out
    ..writeln('*Total · மொத்தம்: ${money(b.bill.total)}* (${b.mode.label})')
    ..write('நன்றி · Thank you');
  return out.toString();
}
