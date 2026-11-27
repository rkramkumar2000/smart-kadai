import 'package:material_ui/material_ui.dart';

import '../app_state.dart';

/// Which language the screen shows. "Both" shows English with Tamil beside
/// it, as before. "Tamil" shows Tamil only, for owners who read Tamil best.
enum UiLang {
  both('both', 'English + தமிழ்'),
  tamil('tamil', 'தமிழ் மட்டும்'),
  english('english', 'English only');

  const UiLang(this.code, this.label);
  final String code;
  final String label;

  static UiLang fromCode(String c) =>
      values.firstWhere((l) => l.code == c, orElse: () => UiLang.both);
}

/// The screen's language and text size, shared by every screen.
class UiPrefs {
  static final lang = ValueNotifier<UiLang>(UiLang.both);

  /// 1.0 is normal; A+ goes up to 1.4.
  static final textScale = ValueNotifier<double>(1.0);

  static const minScale = 1.0;
  static const maxScale = 1.4;
}

/// Text for a label written in English with a Tamil translation.
/// Shows the English (both, english) or the Tamil (tamil).
String t(String en, String ta) => UiPrefs.lang.value == UiLang.tamil ? ta : en;

/// A label written "English · Tamil". Shows both, or only one part.
String bi(String both) {
  final i = both.indexOf(' · ');
  if (i < 0) return both;
  return switch (UiPrefs.lang.value) {
    UiLang.both => both,
    UiLang.tamil => both.substring(i + 3),
    UiLang.english => both.substring(0, i),
  };
}

/// A label shown as "English · Tamil" in both mode, else one language.
String tt(String en, String ta) => switch (UiPrefs.lang.value) {
  UiLang.both => '$en · $ta',
  UiLang.tamil => ta,
  UiLang.english => en,
};

void setUiLang(AppState s, UiLang l) {
  s.repo.setSetting('ui_lang', l.code);
  UiPrefs.lang.value = l;
}

/// A+ and A− change the text size in steps of 10%.
void stepTextSize(AppState s, int step) {
  final v = (UiPrefs.textScale.value + step * 0.1).clamp(
    UiPrefs.minScale,
    UiPrefs.maxScale,
  );
  final r = (v * 10).roundToDouble() / 10;
  s.repo.setSetting('text_scale', '$r');
  UiPrefs.textScale.value = r;
}

/// Language and text size buttons, for the menu and the PIN screen.
class ViewControls extends StatelessWidget {
  const ViewControls({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final lang = UiPrefs.lang.value;
    final next = switch (lang) {
      UiLang.both => UiLang.tamil,
      UiLang.tamil => UiLang.english,
      UiLang.english => UiLang.both,
    };
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      children: [
        Tooltip(
          message: t('Change language', 'மொழி மாற்று'),
          child: OutlinedButton(
            onPressed: () => setUiLang(state, next),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(52, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(switch (lang) {
              UiLang.both => 'EN+த',
              UiLang.tamil => 'தமிழ்',
              UiLang.english => 'EN',
            }),
          ),
        ),
        IconButton(
          tooltip: t('Smaller text', 'சிறிய எழுத்து'),
          onPressed: UiPrefs.textScale.value <= UiPrefs.minScale
              ? null
              : () => stepTextSize(state, -1),
          icon: const Text(
            'A−',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: t('Bigger text', 'பெரிய எழுத்து'),
          onPressed: UiPrefs.textScale.value >= UiPrefs.maxScale
              ? null
              : () => stepTextSize(state, 1),
          icon: const Text(
            'A+',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
