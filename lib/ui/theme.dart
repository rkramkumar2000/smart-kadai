import 'package:material_ui/material_ui.dart';

import 'lang.dart';

export 'lang.dart';

/// Colours and sizes from the Smart Kadai screen designs: one green accent,
/// large type and big touch targets for owners who are not comfortable with
/// computers.
class KadaiColors {
  static const green = Color(0xFF1F6B45);
  static const greenDark = Color(0xFF14502F);
  static const greenTint = Color(0xFFDDEEE3);
  static const ground = Color(0xFFF4F5F1);
  static const ink = Color(0xFF1C211B);
  static const quiet = Color(0xFF565E53);
  static const line = Color(0xFFD9DDD4);
  static const warnTint = Color(0xFFFFF6DB);
  static const warn = Color(0xFFB45309);
  static const warnInk = Color(0xFF7A4B00);
  static const danger = Color(0xFF9A2C0E);
}

ThemeData kadaiTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KadaiColors.green,
    primary: KadaiColors.green,
    surface: Colors.white,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: KadaiColors.ground,
    fontFamilyFallback: const ['Nirmala UI', 'Latha', 'Noto Sans Tamil'],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: KadaiColors.ink,
      displayColor: KadaiColors.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: KadaiColors.ink,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: KadaiColors.line),
      ),
    ),
  );
}

/// English label with its Tamil label underneath.
class TwoLang extends StatelessWidget {
  const TwoLang(
    this.en,
    this.ta, {
    super.key,
    this.size = 16,
    this.weight = FontWeight.w600,
    this.color,
  });

  final String en;
  final String ta;
  final double size;
  final FontWeight weight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final lang = UiPrefs.lang.value;
    if (lang != UiLang.both || ta.isEmpty) {
      // One language: the Tamil (or English) name at full size.
      final main = lang == UiLang.tamil && ta.isNotEmpty ? ta : en;
      return Text(
        main,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: size, fontWeight: weight, color: color),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          en,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color),
        ),
        if (ta.isNotEmpty)
          Text(
            ta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: size - 3,
              color: color ?? KadaiColors.quiet,
            ),
          ),
      ],
    );
  }
}

String rupees(double v) {
  final whole = v == v.truncateToDouble();
  return '₹${whole ? v.toInt() : v.toStringAsFixed(2)}';
}

/// Phones and narrow windows get one column and the menu in a drawer.
bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 720;

/// Space around a screen: less on a phone.
EdgeInsets screenPadding(BuildContext context) =>
    EdgeInsets.all(isNarrow(context) ? 12 : 20);

/// A screen's title with its buttons beside it. When there is no room
/// (a phone) the buttons go under the title and wrap.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.actions = const []});

  final Widget title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          ],
        );
      }
      // With big text the buttons wrap onto a second line instead of
      // running off the screen.
      return Row(
        children: [
          Expanded(child: title),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ],
      );
    },
  );
}
