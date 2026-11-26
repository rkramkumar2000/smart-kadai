import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../auth/auth.dart';
import 'theme.dart';

/// First run: create the owner's login. After that: pick your name and type
/// your 4-digit PIN on a big keypad (or the keyboard).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  String _pin = '';
  String? _firstPin; // setup: the PIN typed once, waiting to be repeated
  String? _error;
  AppUser? _selected;

  AuthRepository get auth => widget.state.auth;
  bool get _setup => !auth.hasOwner;

  @override
  void initState() {
    super.initState();
    final users = auth.users();
    if (users.length == 1) _selected = users.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _digit(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    if (_setup) {
      if (_name.text.trim().isEmpty) {
        setState(() {
          _error = tt('Type your name first', 'முதலில் உங்கள் பெயர்');
          _pin = '';
        });
        return;
      }
      if (_firstPin == null) {
        setState(() {
          _firstPin = _pin;
          _pin = '';
        });
        return;
      }
      if (_firstPin != _pin) {
        setState(() {
          _error = t(
            'PINs did not match. Start again.',
            'PIN பொருந்தவில்லை. மீண்டும் தொடங்குங்கள்.',
          );
          _firstPin = null;
          _pin = '';
        });
        return;
      }
      final u = auth.createUser(_name.text, Role.owner, _pin);
      widget.state.login(u);
      return;
    }
    final u = _selected;
    if (u == null) {
      setState(() {
        _error = t('Pick your name first', 'முதலில் உங்கள் பெயரை தொடுங்கள்');
        _pin = '';
      });
      return;
    }
    try {
      final ok = auth.verify(u.id, _pin);
      if (ok != null) {
        widget.state.login(ok);
        return;
      }
      setState(() {
        _error = bi('Wrong PIN · தவறான PIN');
        _pin = '';
      });
    } on PinLockedException catch (e) {
      setState(() {
        _error = t(
          'Too many wrong PINs. Wait ${e.waitSeconds} seconds.',
          'பல முறை தவறு. ${e.waitSeconds} விநாடி காத்திருங்கள்.',
        );
        _pin = '';
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _digit(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final users = _setup ? <AppUser>[] : auth.users();
    final title = _setup
        ? (_firstPin == null
              ? t('Set your 4-digit PIN', '4 இலக்க PIN அமையுங்கள்')
              : t('Type the PIN again', 'PIN-ஐ மீண்டும் அழுத்துங்கள்'))
        : t('Enter your PIN', 'உங்கள் PIN அழுத்துங்கள்');
    return Scaffold(
      body: Focus(
        focusNode: _focus,
        autofocus: !_setup,
        onKeyEvent: _onKey,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: KadaiColors.green,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'SK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_setup) ...[
                        Text(
                          t(
                            'Welcome to Smart Kadai',
                            'ஸ்மார்ட் கடைக்கு வரவேற்கிறோம்',
                          ),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bi('Create the owner login · உரிமையாளர்'),
                          style: TextStyle(color: KadaiColors.quiet),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _name,
                          autofocus: true,
                          style: const TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            labelText: bi('Your name · உங்கள் பெயர்'),
                          ),
                          onSubmitted: (_) => _focus.requestFocus(),
                        ),
                      ] else ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final u in users)
                              ChoiceChip(
                                label: Text(
                                  '${u.name} · ${u.role.label}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                selected: _selected?.id == u.id,
                                onSelected: (_) => setState(() {
                                  _selected = u;
                                  _pin = '';
                                  _error = null;
                                  _focus.requestFocus();
                                }),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      ViewControls(state: widget.state),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 4; i++)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _pin.length
                                    ? KadaiColors.green
                                    : Colors.transparent,
                                border: Border.all(
                                  color: i < _pin.length
                                      ? KadaiColors.green
                                      : KadaiColors.quiet,
                                  width: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: KadaiColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.7,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final d in '123456789'.split(''))
                            _key(d, () => _digit(d)),
                          _key('⌫', _back, label: 'Delete'),
                          _key('0', () => _digit('0')),
                          _key(
                            'C',
                            () => setState(() => _pin = ''),
                            label: 'Clear',
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

  Widget _key(String text, VoidCallback onTap, {String? label}) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          padding: EdgeInsets.zero,
        ),
        child: Text(
          text,
          semanticsLabel: label,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
      );
}
