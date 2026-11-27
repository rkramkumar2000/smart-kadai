import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'theme.dart';

/// UPI payment link with the amount filled in. Any UPI app (GPay, PhonePe,
/// Paytm, BHIM) can scan it.
String upiLink(String upiId, String payee, double amount, String note) => Uri(
  scheme: 'upi',
  host: 'pay',
  queryParameters: {
    'pa': upiId,
    'pn': payee,
    'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    'tn': note,
  },
).toString();

/// Shows the shop's UPI QR with the bill amount. True when the owner says
/// the money came.
Future<bool> showUpiQr(
  BuildContext context, {
  required String upiId,
  required String payee,
  required double amount,
  required String note,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Scan to pay · UPI'),
      content: SizedBox(
        width: 340,
        // Scrolls on a small phone with big text.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rupees(amount),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: upiLink(upiId, payee, amount, note),
                  size: 260,
                ),
              ),
              const SizedBox(height: 8),
              Text(upiId, style: const TextStyle(color: KadaiColors.quiet)),
              const SizedBox(height: 4),
              const Text(
                'Check that the money reached your phone before you press Paid.',
                textAlign: TextAlign.center,
                style: TextStyle(color: KadaiColors.quiet),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Paid · பணம் வந்தது'),
        ),
      ],
    ),
  );
  return ok == true;
}
