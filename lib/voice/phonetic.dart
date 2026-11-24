/// Turns Tamil script, Tanglish and English words into one comparable
/// Latin "sound key", so that கடலை, kadalai and Kadalai all become `katalai`.
///
/// Tamil does not separate k/g, t/d, p/b or s/ch/j in writing, and Tanglish
/// spellings vary a lot (thakkali, thakali, takkali), so the key folds those
/// differences away.
library;

const _vowels = {
  'அ': 'a', 'ஆ': 'aa', 'இ': 'i', 'ஈ': 'ii', 'உ': 'u', 'ஊ': 'uu', //
  'எ': 'e', 'ஏ': 'ee', 'ஐ': 'ai', 'ஒ': 'o', 'ஓ': 'oo', 'ஔ': 'au',
  'ஃ': 'k',
};

const _consonants = {
  'க': 'k', 'ங': 'ng', 'ச': 's', 'ஞ': 'nj', 'ட': 't', 'ண': 'n', //
  'த': 'th', 'ந': 'n', 'ப': 'p', 'ம': 'm', 'ய': 'y', 'ர': 'r',
  'ல': 'l', 'வ': 'v', 'ழ': 'zh', 'ள': 'l', 'ற': 'r', 'ன': 'n',
  'ஜ': 'j', 'ஷ': 'sh', 'ஸ': 's', 'ஹ': 'h',
};

const _signs = {
  'ா': 'aa', 'ி': 'i', 'ீ': 'ii', 'ு': 'u', 'ூ': 'uu', 'ெ': 'e', //
  'ே': 'ee', 'ை': 'ai', 'ொ': 'o', 'ோ': 'oo', 'ௌ': 'au',
};

const _pulli = '்';

/// Writes Tamil script in Latin letters. Non-Tamil characters pass through.
String transliterateTamil(String input) {
  final out = StringBuffer();
  final chars = input.runes.map(String.fromCharCode).toList();
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    final next = i + 1 < chars.length ? chars[i + 1] : '';
    if (_consonants.containsKey(c)) {
      out.write(_consonants[c]);
      if (next == _pulli) {
        i++;
      } else if (_signs.containsKey(next)) {
        out.write(_signs[next]);
        i++;
      } else {
        out.write('a');
      }
    } else if (_vowels.containsKey(c)) {
      out.write(_vowels[c]);
    } else if (_signs.containsKey(c) || c == _pulli) {
      // Stray sign without a consonant: keep the vowel sound.
      out.write(_signs[c] ?? '');
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

final _nonLetters = RegExp(r'[^a-z0-9\s]');
final _spaces = RegExp(r'\s+');

/// Sound key for one word.
String wordKey(String word) {
  var w = transliterateTamil(word).toLowerCase();
  w = w.replaceAll(_nonLetters, '');
  if (w.isEmpty) return w;
  if (RegExp(r'^[0-9.]+$').hasMatch(w)) return w;
  const pairs = [
    ['zh', 'l'], ['nj', 'n'], ['ch', 's'], ['sh', 's'], ['th', 't'], //
    ['dh', 'd'], ['ph', 'p'], ['bh', 'b'], ['kh', 'k'], ['gh', 'g'],
    ['ck', 'k'], ['x', 'ks'], ['q', 'k'], ['c', 'k'], ['w', 'v'],
    ['z', 's'], ['j', 's'], ['g', 'k'], ['d', 't'], ['b', 'p'],
    ['f', 'p'], ['ee', 'i'], ['oo', 'u'], ['y', 'i'],
  ];
  for (final p in pairs) {
    w = w.replaceAll(p[0], p[1]);
  }
  // Collapse doubled letters: thakkali -> takali, mittaay -> mitai.
  final sb = StringBuffer();
  for (var i = 0; i < w.length; i++) {
    if (i > 0 && w[i] == w[i - 1]) continue;
    sb.write(w[i]);
  }
  w = sb.toString();
  // Word-final "ai" and "ei" sound alike in speech-to-text output.
  if (w.endsWith('ei')) w = '${w.substring(0, w.length - 2)}ai';
  return w;
}

/// Splits raw text into words, separating digits stuck to letters
/// ("250g" -> "250 g") and dropping punctuation.
List<String> splitWords(String text) {
  final spaced = text
      .replaceAllMapped(RegExp(r'(\d)([^\d\s.,])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([^\d\s.,])(\d)'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[,;!?।]'), ' , ');
  return spaced
      .split(_spaces)
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();
}

/// Sound key for a whole phrase, words joined by single spaces.
String phraseKey(String text) =>
    splitWords(text).map(wordKey).where((w) => w.isNotEmpty).join(' ');
