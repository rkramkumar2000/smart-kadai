import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import 'lang.dart';

/// "Hold to speak": in a noisy shop the mic listens only while the button
/// is held down, like a walkie-talkie. In tap mode [child] works as usual.
class HoldMic extends StatefulWidget {
  const HoldMic({
    super.key,
    required this.state,
    required this.child,
    this.onHoldStart,
    this.onHoldEnd,
  });

  final AppState state;
  final Widget child;

  /// Runs before the mic starts, and after it stops.
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  @override
  State<HoldMic> createState() => _HoldMicState();
}

class _HoldMicState extends State<HoldMic> {
  DateTime? _down;

  void _start() {
    _down = DateTime.now();
    widget.onHoldStart?.call();
    widget.state.holdStart();
  }

  void _end() {
    final down = _down;
    if (down == null) return;
    _down = null;
    widget.state.holdEnd();
    widget.onHoldEnd?.call();
    if (DateTime.now().difference(down) < const Duration(milliseconds: 400)) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Keep holding the mic while you speak, then let go.',
                'பேசும் வரை மைக்கை அழுத்திப் பிடியுங்கள், பிறகு விடுங்கள்.',
              ),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.state.holdToSpeak) return widget.child;
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: widget.child,
    );
  }
}
