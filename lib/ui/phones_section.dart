import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../sync/phone_link.dart';
import '../sync/shop_server.dart';
import 'barcode_scan.dart';
import 'theme.dart';

String _ago(DateTime? at) {
  if (at == null) return t('not yet', 'இன்னும் இல்லை');
  final d = DateTime.now().difference(at);
  if (d.inSeconds < 60) return t('just now', 'இப்போது');
  if (d.inMinutes < 60) {
    return t('${d.inMinutes} min ago', '${d.inMinutes} நிமிடம் முன்');
  }
  if (d.inHours < 24) {
    return t('${d.inHours} hours ago', '${d.inHours} மணி முன்');
  }
  return '${at.day}-${at.month}-${at.year}';
}

// ======================================================================= PC

/// Settings on the shop PC: let staff phones bill through it.
class PcPhonesSection extends StatefulWidget {
  const PcPhonesSection({super.key, required this.state});
  final AppState state;

  @override
  State<PcPhonesSection> createState() => _PcPhonesSectionState();
}

class _PcPhonesSectionState extends State<PcPhonesSection> {
  AppState get s => widget.state;
  bool _busy = false;

  Future<void> _turn(bool on) async {
    setState(() => _busy = true);
    final err = await s.setPhonesOn(on);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Could not start. Another copy of Smart Kadai may be open on this PC. ($err)',
              'தொடங்க முடியவில்லை. இந்த கணினியில் Smart Kadai இன்னொன்று திறந்திருக்கலாம்.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _pair() async {
    if (!s.phonesOn || s.server?.running != true) await _turn(true);
    if (!mounted || s.server?.running != true) return;
    final hosts = await ShopServer.addresses();
    if (!mounted) return;
    final code = s.server!.newPairingCode();
    final info = PairInfo(hosts, s.server!.port, code);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Pair a phone', 'போனை இணை')),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    'On the phone: open Smart Kadai, press "Connect to shop PC" and scan this code. The phone must be on the same Wi-Fi as this PC.',
                    'போனில் Smart Kadai திறந்து "கடை கணினியுடன் இணை" அழுத்தி இந்த QR-ஐ ஸ்கேன் செய்யுங்கள். போனும் கணினியும் ஒரே Wi-Fi-ல் இருக்க வேண்டும்.',
                  ),
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 12),
                if (hosts.isEmpty)
                  Text(
                    t(
                      'This PC is not on a network. Connect it to the shop Wi-Fi first.',
                      'இந்த கணினி Wi-Fi-ல் இல்லை. முதலில் Wi-Fi-ல் இணையுங்கள்.',
                    ),
                    style: const TextStyle(
                      color: KadaiColors.danger,
                      fontSize: 16,
                    ),
                  )
                else ...[
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: QrImageView(data: info.encode(), size: 240),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    '${t('Or type', 'அல்லது தட்டச்சு')}: ${hosts.first}   ${t('Code', 'குறியீடு')}: $code',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t(
                      'The code works for 15 minutes. If Windows asks, press "Allow access".',
                      'குறியீடு 15 நிமிடம் வேலை செய்யும். Windows கேட்டால் "Allow access" அழுத்துங்கள்.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: KadaiColors.quiet),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Done', 'முடிந்தது')),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _remove(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Remove $name?', '$name நீக்கவா?')),
        content: Text(
          t(
            'This phone can no longer send bills. Its bills already sent stay in the reports.',
            'இந்த போன் இனி பில் அனுப்ப முடியாது. அனுப்பிய பில்கள் அறிக்கையில் இருக்கும்.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Keep', 'வேண்டாம்')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: KadaiColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Remove', 'நீக்கு')),
          ),
        ],
      ),
    );
    if (ok == true) {
      s.sync.removeDevice(id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final phones = s.sync.devices();
    final on = s.phonesOn && s.server?.running == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            t(
              'Phones can bill through this PC',
              'போன்கள் இந்த கணினி வழியாக பில் போடலாம்',
            ),
          ),
          subtitle: Text(
            t(
              'Staff phones on the shop Wi-Fi send every bill here. One stock, one set of reports. No internet needed.',
              'கடை Wi-Fi-ல் உள்ள போன்களின் பில்கள் இங்கு வரும். ஒரே இருப்பு, ஒரே அறிக்கை. இணையம் தேவையில்லை.',
            ),
          ),
          value: on,
          onChanged: _busy ? null : _turn,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            t('Print phone bills on this PC', 'போன் பில்களை இங்கு அச்சிடு'),
          ),
          subtitle: Text(
            t(
              'Each bill from a phone prints on this PC\'s bill printer.',
              'போனிலிருந்து வரும் ஒவ்வொரு பில்லும் இந்த கணினியின் பிரிண்டரில் வரும்.',
            ),
          ),
          value: s.repo.setting('print_phone_bills') == '1',
          onChanged: (v) => setState(
            () => s.repo.setSetting('print_phone_bills', v ? '1' : '0'),
          ),
        ),
        const SizedBox(height: 8),
        for (final p in phones)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smartphone, color: KadaiColors.green),
            title: Text(
              p.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${t('Today', 'இன்று')}: ${p.billsToday} ${t('bills', 'பில்')} · ${rupees(p.salesToday)} · '
              '${t('last seen', 'கடைசியாக')} ${_ago(p.lastSeen)}',
            ),
            trailing: IconButton(
              tooltip: t('Remove phone', 'போனை நீக்கு'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _remove(p.id, p.name),
            ),
          ),
        if (phones.isEmpty)
          Text(
            t('No phones paired yet.', 'இன்னும் போன் இணைக்கவில்லை.'),
            style: const TextStyle(color: KadaiColors.quiet),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy ? null : _pair,
            icon: const Icon(Icons.qr_code_2),
            label: Text(t('Pair a phone', 'போனை இணை')),
          ),
        ),
      ],
    );
  }
}

// ==================================================================== phone

/// Scans the PC's QR code (or takes the typed address and code), pairs
/// this phone and switches it to the shop PC's products and staff.
Future<void> connectToPc(
  BuildContext context,
  AppState s, {
  bool typed = false,
}) async {
  final host = s.host;
  if (host == null) return;
  PairInfo? info;
  if (typed) {
    info = await _typeCode(context);
  } else {
    final text = await scanBarcode(context);
    if (text == null || !context.mounted) return;
    info = PairInfo.parse(text);
    if (info == null) {
      await _problem(
        context,
        t(
          'That is not the shop PC\'s code. On the PC open Settings, press "Pair a phone" and scan the code it shows.',
          'இது கடை கணினியின் QR இல்லை. கணினியில் அமைப்பு > "Pair a phone" அழுத்தி வரும் QR-ஐ ஸ்கேன் செய்யுங்கள்.',
        ),
      );
      return;
    }
  }
  if (info == null || !context.mounted) return;
  final name = await _askName(context);
  if (name == null || !context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              t('Connecting to the shop PC…', 'கடை கணினியுடன் இணைக்கிறது…'),
            ),
          ),
        ],
      ),
    ),
  );
  String? error;
  try {
    final d = await PhoneLink.pair(info, name);
    await host.connect(d);
  } on LinkException catch (e) {
    error = t(e.en, e.ta);
  } on Object catch (e) {
    error = '$e';
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (error != null) await _problem(context, error);
}

Future<void> _problem(BuildContext context, String text) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(t('Not connected', 'இணையவில்லை')),
    content: Text(text, style: const TextStyle(fontSize: 16)),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK'),
      ),
    ],
  ),
);

Future<String?> _askName(BuildContext context) {
  final c = TextEditingController(text: t('Counter phone', 'கவுண்டர் போன்'));
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t('Name this phone', 'இந்த போனுக்கு பெயர்')),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(
          labelText: t(
            'Shown on the PC, like "Kumar phone"',
            'கணினியில் தெரியும், "குமார் போன்" போல',
          ),
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Cancel', 'வேண்டாம்')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text.trim()),
          child: Text(t('Connect', 'இணை')),
        ),
      ],
    ),
  );
}

Future<PairInfo?> _typeCode(BuildContext context) {
  final addr = TextEditingController(), code = TextEditingController();
  return showDialog<PairInfo>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        t(
          'Type the PC\'s address and code',
          'கணினியின் முகவரி மற்றும் குறியீடு',
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: addr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'PC address, like 192.168.1.5',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: code,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t('6-digit code', '6 இலக்க குறியீடு'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Cancel', 'வேண்டாம்')),
        ),
        FilledButton(
          onPressed: () {
            final a = addr.text.trim(), c = code.text.trim();
            if (a.isEmpty || c.isEmpty) return;
            final parts = a.split(':');
            Navigator.pop(
              context,
              PairInfo(
                [parts.first],
                parts.length > 1
                    ? int.tryParse(parts[1]) ?? ShopServer.defaultPort
                    : ShopServer.defaultPort,
                c,
              ),
            );
          },
          child: Text(t('Next', 'அடுத்து')),
        ),
      ],
    ),
  );
}

/// The two buttons a phone shows to join the shop PC.
class ConnectToPcButtons extends StatelessWidget {
  const ConnectToPcButtons({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [
      FilledButton.tonalIcon(
        onPressed: () => connectToPc(context, state),
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(t('Connect to shop PC', 'கடை கணினியுடன் இணை')),
      ),
      TextButton(
        onPressed: () => connectToPc(context, state, typed: true),
        child: Text(t('Type code instead', 'குறியீட்டை தட்டச்சு செய்')),
      ),
    ],
  );
}

/// One line saying whether the phone reaches the PC and what is waiting.
class PcStatus extends StatelessWidget {
  const PcStatus({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l = state.link;
    if (l == null) return const SizedBox.shrink();
    final waiting = l.waitingBills;
    final (color, text) = l.removed
        ? (
            KadaiColors.danger,
            t(
              'Removed on the PC. Pair again.',
              'கணினியில் நீக்கப்பட்டது. மீண்டும் இணையுங்கள்.',
            ),
          )
        : l.online
        ? (
            KadaiColors.green,
            waiting == 0
                ? t('PC connected', 'கணினி இணைப்பில்')
                : t(
                    'PC connected · sending $waiting',
                    'கணினி இணைப்பில் · $waiting அனுப்புகிறது',
                  ),
          )
        : (
            KadaiColors.warn,
            waiting == 0
                ? t('PC not reachable', 'கணினி கிடைக்கவில்லை')
                : t(
                    'No PC · $waiting bills waiting',
                    'கணினி இல்லை · $waiting பில் காத்திருக்கிறது',
                  ),
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          l.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Settings on a phone that bills through the PC.
class ShopPcSection extends StatefulWidget {
  const ShopPcSection({super.key, required this.state});
  final AppState state;

  @override
  State<ShopPcSection> createState() => _ShopPcSectionState();
}

class _ShopPcSectionState extends State<ShopPcSection> {
  AppState get s => widget.state;
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    await s.link!.syncNow(pull: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _leave() async {
    final waiting = s.link!.waitingBills;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t('Stop billing through the PC?', 'கணினி வழி பில்லை நிறுத்தவா?'),
        ),
        content: Text(
          waiting > 0
              ? t(
                  '$waiting bills have not reached the PC yet. They stay on this phone and are sent when you connect again.',
                  '$waiting பில்கள் இன்னும் கணினிக்கு போகவில்லை. மீண்டும் இணைத்ததும் அனுப்பப்படும்.',
                )
              : t(
                  'The phone goes back to its own products and bills.',
                  'போன் தன் சொந்த பொருட்கள் மற்றும் பில்களுக்கு திரும்பும்.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Keep', 'வேண்டாம்')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Stop', 'நிறுத்து')),
          ),
        ],
      ),
    );
    if (ok == true) await s.host?.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final l = s.link!;
    return ListenableBuilder(
      listenable: l,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(
              'This phone bills through ${l.pcShop}\'s PC as "${l.phoneName}".',
              'இந்த போன் ${l.pcShop} கணினி வழியாக "${l.phoneName}" என பில் போடுகிறது.',
            ),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 8),
          PcStatus(state: s),
          const SizedBox(height: 4),
          Text(
            '${t('Last sent', 'கடைசியாக அனுப்பியது')}: ${_ago(l.lastSync)}',
            style: const TextStyle(color: KadaiColors.quiet),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _leave,
                icon: const Icon(Icons.link_off),
                label: Text(
                  t('Stop billing through PC', 'கணினி இணைப்பை நிறுத்து'),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.sync),
                label: Text(t('Send now', 'இப்போது அனுப்பு')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
