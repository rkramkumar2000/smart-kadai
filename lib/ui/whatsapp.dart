import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens WhatsApp with [text] ready to send, to [phone] when given. The text
/// is also copied, so the owner can paste it if WhatsApp does not open.
Future<void> sendOnWhatsApp(
  BuildContext context,
  String text, {
  String phone = '',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) digits = '91$digits';
  final uri = Uri.parse(
    'https://wa.me/${digits.isEmpty ? '' : digits}?text=${Uri.encodeComponent(text)}',
  );
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        opened
            ? 'Opening WhatsApp. The message is also copied.'
            : 'Message copied. Paste it into WhatsApp.',
        style: const TextStyle(fontSize: 15),
      ),
    ),
  );
}
