import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../printing/bill_printer.dart';
import 'product_import_dialog.dart';
import 'theme.dart';

/// True when the owner has not finished the first-day guide. Shops that
/// already have bills skip it.
bool needsSetup(AppState s) {
  if (!(s.user?.isOwner ?? false)) return false;
  if (s.repo.setting('setup_done') == '1') return false;
  final bills =
      s.repo.db.select('SELECT COUNT(*) AS n FROM sales').first['n'] as int;
  return bills == 0;
}

/// First day: shop details, UPI, bill paper and products, one step at a time.
class SetupGuide extends StatefulWidget {
  const SetupGuide({super.key, required this.state});

  final AppState state;

  @override
  State<SetupGuide> createState() => _SetupGuideState();
}

class _SetupGuideState extends State<SetupGuide> {
  AppState get s => widget.state;
  int _step = 0;

  late final _name = TextEditingController(text: s.shopName);
  late final _phone = TextEditingController(text: s.repo.setting('shop_phone'));
  late final _address = TextEditingController(
    text: s.repo.setting('shop_address'),
  );
  late final _upi = TextEditingController(text: s.repo.setting('upi_id'));

  static const _steps = 4;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _upi.dispose();
    super.dispose();
  }

  void _saveFields() {
    if (_name.text.trim().isNotEmpty) {
      s.repo.setSetting('shop_name', _name.text.trim());
    }
    s.repo.setSetting('shop_phone', _phone.text.trim());
    s.repo.setSetting('shop_address', _address.text.trim());
    s.repo.setSetting('upi_id', _upi.text.trim());
  }

  void _next() {
    _saveFields();
    if (_step < _steps - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _finish() {
    _saveFields();
    s.repo.setSetting('setup_done', '1');
    s.refresh();
  }

  Widget _stepBody() => switch (_step) {
    0 => Column(
      key: const ValueKey('setup-shop'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Your shop', 'உங்கள் கடை'),
        _hint(
          'This is printed at the top of every bill.',
          'இது ஒவ்வொரு பில்லின் மேலும் வரும்.',
        ),
        TextField(
          controller: _name,
          decoration: InputDecoration(labelText: tt('Shop name', 'கடை பெயர்')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: tt('Phone', 'போன்')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _address,
          decoration: InputDecoration(labelText: tt('Address', 'முகவரி')),
        ),
      ],
    ),
    1 => Column(
      key: const ValueKey('setup-upi'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('UPI payments', 'UPI பணம்'),
        _hint(
          'With your UPI ID the app shows a QR code with the bill amount, '
              'so customers pay the exact total. You can leave it empty.',
          'UPI ID கொடுத்தால், பில் தொகையுடன் QR காட்டும். '
              'வேண்டாமென்றால் காலியாக விடலாம்.',
        ),
        TextField(
          controller: _upi,
          decoration: InputDecoration(
            labelText: tt('UPI ID, like ramstores@okaxis', 'UPI ID'),
          ),
        ),
      ],
    ),
    2 => Column(
      key: const ValueKey('setup-paper'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Bill printer', 'பில் பிரிண்டர்'),
        _hint(
          'Pick the paper in your printer. No printer? Pick any one, and '
              'send bills on WhatsApp instead.',
          'பிரிண்டர் பேப்பர் அளவை தேர்ந்தெடுங்கள். பிரிண்டர் இல்லையென்றால் '
              'WhatsApp-ல் பில் அனுப்பலாம்.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in BillPaper.values)
              ChoiceChip(
                label: Text(p.label),
                selected:
                    BillPaper.fromCode(s.repo.setting('bill_paper', '80mm')) ==
                    p,
                onSelected: (_) =>
                    setState(() => s.repo.setSetting('bill_paper', p.code)),
              ),
          ],
        ),
      ],
    ),
    _ => Column(
      key: const ValueKey('setup-products'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Your products', 'உங்கள் பொருட்கள்'),
        _hint(
          'The app already has ${s.activeProducts.length} common products. '
              'If you have a list in Excel, add all of them at once. You can '
              'also do this later from Products.',
          'ஏற்கனவே ${s.activeProducts.length} பொதுவான பொருட்கள் உள்ளன. '
              'Excel பட்டியல் இருந்தால் ஒரே முறையில் சேர்க்கலாம். '
              'பின்னர் "பொருட்கள்" பக்கத்திலும் செய்யலாம்.',
        ),
        OutlinedButton.icon(
          onPressed: () => saveProductTemplate(context),
          icon: const Icon(Icons.download_outlined),
          label: Text(tt('Get the sample sheet', 'மாதிரி பட்டியல்')),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () async {
            await importProductsFlow(context, s);
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(tt('Add products from Excel', 'Excel-லிருந்து சேர்')),
        ),
      ],
    ),
  };

  Widget _title(String en, String ta) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TwoLang(en, ta, size: 22),
  );

  Widget _hint(String en, String ta) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      tt(en, ta).replaceAll(' · ', '\n'),
      style: const TextStyle(fontSize: 15, color: KadaiColors.quiet),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${t('Step', 'படி')} ${_step + 1} / $_steps',
                              style: const TextStyle(
                                color: KadaiColors.quiet,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _finish,
                            child: Text(t('Skip all', 'தவிர்')),
                          ),
                        ],
                      ),
                      LinearProgressIndicator(
                        value: (_step + 1) / _steps,
                        color: KadaiColors.green,
                      ),
                      const SizedBox(height: 20),
                      _stepBody(),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          if (_step > 0)
                            OutlinedButton(
                              onPressed: () => setState(() => _step--),
                              child: Text(t('Back', 'பின்')),
                            ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(150, 52),
                            ),
                            child: Text(
                              _step == _steps - 1
                                  ? t('Start billing', 'பில் போட தொடங்கு')
                                  : t('Next', 'அடுத்து'),
                              style: const TextStyle(fontSize: 17),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
