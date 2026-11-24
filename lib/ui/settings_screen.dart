import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../auth/auth.dart';
import '../billing/bill.dart';
import '../printing/bill_printer.dart';
import 'theme.dart';

/// Owner only: shop details on the bill, printer, logins, AI key and backup.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppState get s => widget.state;

  late final Map<String, TextEditingController> _shop = {
    'shop_name': TextEditingController(text: s.shopName),
    'shop_address': TextEditingController(text: s.repo.setting('shop_address')),
    'shop_phone': TextEditingController(text: s.repo.setting('shop_phone')),
    'shop_gstin': TextEditingController(text: s.repo.setting('shop_gstin')),
    'upi_id': TextEditingController(text: s.repo.setting('upi_id')),
    'bill_footer': TextEditingController(
      text: s.repo.setting('bill_footer', 'Thank you. Visit again!'),
    ),
  };
  late final _aiKey = TextEditingController(text: s.repo.setting('ai_key'));
  bool _showKey = false;

  @override
  void dispose() {
    for (final c in _shop.values) {
      c.dispose();
    }
    _aiKey.dispose();
    super.dispose();
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(t, style: const TextStyle(fontSize: 15))),
  );

  void _saveShop() {
    for (final e in _shop.entries) {
      s.repo.setSetting(e.key, e.value.text.trim());
    }
    s.refresh();
    _snack('Shop details saved');
  }

  Future<void> _testPrint() async {
    final b = Bill();
    final p = s.activeProducts.first;
    b.add(
      BillLine(
        product: p,
        variant: p.defaultVariant,
        count: 1,
        enteredBy: EntryMethod.tap,
      ),
    );
    await printBill(
      s,
      SavedBill(
        number: 0,
        bill: b,
        mode: PaymentMode.cash,
        at: DateTime.now(),
        cashier: s.user?.name ?? '',
      ),
    );
  }

  Future<void> _backup() async {
    final d = DateTime.now();
    final loc = await getSaveLocation(
      suggestedName:
          'smart-kadai-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.db',
    );
    if (loc == null) return;
    final f = File(loc.path);
    if (f.existsSync()) f.deleteSync();
    s.repo.db.execute('VACUUM INTO ?', [loc.path]);
    _snack('Backup saved to ${loc.path}. Keep a copy on a pen drive.');
  }

  /// Add a login, or change one's PIN. Returns true when saved.
  Future<void> _userDialog([AppUser? u]) async {
    final name = TextEditingController(text: u?.name ?? '');
    final pin = TextEditingController();
    var role = u?.role ?? Role.staff;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(u == null ? 'Add a login' : 'Change ${u.name}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: u == null,
                  decoration: const InputDecoration(labelText: 'Name · பெயர்'),
                ),
                const SizedBox(height: 12),
                if (u == null)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final r in Role.values)
                        ChoiceChip(
                          label: Text(r.label),
                          selected: role == r,
                          onSelected: (_) => setLocal(() => role = r),
                        ),
                    ],
                  ),
                if (u == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Staff can bill and see stock. They cannot see profit, '
                      'change prices, purchases or settings.',
                      style: TextStyle(color: KadaiColors.quiet),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: pin,
                  maxLength: 4,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: u == null
                        ? '4-digit PIN'
                        : 'New 4-digit PIN (leave empty to keep)',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: KadaiColors.danger),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final n = name.text.trim();
                final p = pin.text.trim();
                if (n.isEmpty) {
                  setLocal(() => error = 'Type a name');
                  return;
                }
                if ((u == null || p.isNotEmpty) &&
                    !AuthRepository.isValidPin(p)) {
                  setLocal(() => error = 'PIN must be 4 digits');
                  return;
                }
                if (u == null) {
                  s.auth.createUser(n, role, p);
                } else {
                  if (n != u.name) s.auth.rename(u.id, n);
                  if (p.isNotEmpty) s.auth.changePin(u.id, p);
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    pin.dispose();
    setState(() {});
  }

  void _remove(AppUser u) {
    try {
      s.auth.setActive(u.id, false);
      setState(() {});
      _snack('${u.name} can no longer log in');
    } on StateError {
      _snack('The shop needs at least one owner login.');
    }
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );

  Widget _field(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: _shop[key],
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final paper = BillPaper.fromCode(s.repo.setting('bill_paper', '80mm'));
    final autoPrint = s.repo.setting('auto_print') == '1';
    final users = s.auth.users();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TwoLang('Settings', 'அமைப்பு', size: 24),
              const SizedBox(height: 14),
              _section('Shop details on the bill', [
                _field('shop_name', 'Shop name · கடை பெயர்'),
                _field('shop_address', 'Address'),
                Row(
                  children: [
                    Expanded(child: _field('shop_phone', 'Phone')),
                    const SizedBox(width: 12),
                    Expanded(child: _field('shop_gstin', 'GSTIN (if any)')),
                  ],
                ),
                _field(
                  'upi_id',
                  'Shop UPI ID, like ramstores@okaxis (for the pay QR code)',
                ),
                _field('bill_footer', 'Line at the bottom of the bill'),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _saveShop,
                    child: const Text('Save shop details'),
                  ),
                ),
              ]),
              _section('Bill printing', [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in BillPaper.values)
                      ChoiceChip(
                        label: Text(p.label),
                        selected: paper == p,
                        onSelected: (_) => setState(
                          () => s.repo.setSetting('bill_paper', p.code),
                        ),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Print every bill when it is saved'),
                  subtitle: const Text(
                    'Otherwise press "Print bill" after saving.',
                  ),
                  value: autoPrint,
                  onChanged: (v) => setState(
                    () => s.repo.setSetting('auto_print', v ? '1' : '0'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _testPrint,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print a test bill'),
                  ),
                ),
              ]),
              _section('Logins · உள்நுழைவு', [
                for (final u in users)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      u.isOwner ? Icons.verified_user_outlined : Icons.person,
                    ),
                    title: Text(u.name, style: const TextStyle(fontSize: 16)),
                    subtitle: Text(u.role.label),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _userDialog(u),
                          child: const Text('Change PIN'),
                        ),
                        if (u.id != s.user?.id)
                          TextButton(
                            onPressed: () => _remove(u),
                            style: TextButton.styleFrom(
                              foregroundColor: KadaiColors.danger,
                            ),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _userDialog(),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add a login'),
                  ),
                ),
              ]),
              _section('Reading supplier bill photos', [
                const Text(
                  'Bill photos are read by Claude, an AI service from '
                  'Anthropic. It needs an API key from console.anthropic.com '
                  'and an internet connection. Each bill costs a few rupees. '
                  'Everything else in Smart Kadai works without internet.',
                  style: TextStyle(color: KadaiColors.quiet),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _aiKey,
                        obscureText: !_showKey,
                        decoration: InputDecoration(
                          labelText: 'API key',
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _showKey = !_showKey),
                            icon: Icon(
                              _showKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        s.repo.setSetting('ai_key', _aiKey.text.trim());
                        _snack('AI key saved');
                      },
                      child: const Text('Save key'),
                    ),
                  ],
                ),
              ]),
              _section('Backup', [
                const Text(
                  'Save a copy of all products, bills and purchases. '
                  'Do this every week and keep it on a pen drive.',
                  style: TextStyle(color: KadaiColors.quiet),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _backup,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Back up now'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
