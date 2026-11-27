import '../core/units.dart';
import 'phonetic.dart';

/// Number words heard at a kadai counter, in Tamil script, Tanglish and
/// English. Keys are normalised with [wordKey] when first used, so any
/// spelling that sounds the same also works.
const Map<String, double> _numberWords = {
  // Tamil script
  'ஒன்று': 1, 'ஒண்ணு': 1, 'ஒன்னு': 1, 'ஒரு': 1, 'ஓர்': 1,
  'இரண்டு': 2, 'ரெண்டு': 2, 'இரெண்டு': 2,
  'மூன்று': 3, 'மூணு': 3, 'மூனு': 3,
  'நான்கு': 4, 'நாலு': 4,
  'ஐந்து': 5, 'அஞ்சு': 5, 'அஞ்சி': 5,
  'ஆறு': 6, 'ஏழு': 7, 'எட்டு': 8,
  'ஒன்பது': 9, 'ஒம்பது': 9,
  'பத்து': 10, 'பதினொன்று': 11, 'பதினொண்ணு': 11,
  'பன்னிரண்டு': 12, 'பன்னெண்டு': 12,
  'பதினஞ்சு': 15, 'பதினைந்து': 15,
  'இருபது': 20, 'இருவது': 20, 'இருபத்தஞ்சு': 25,
  'முப்பது': 30, 'நாப்பது': 40, 'நாற்பது': 40,
  'ஐம்பது': 50, 'அம்பது': 50, 'நூறு': 100,
  'இருநூறு': 200, 'எறநூறு': 200, 'முன்னூறு': 300,
  'ஐநூறு': 500, 'ஐநூத்தி': 500,
  // Tanglish
  'onnu': 1, 'ondru': 1, 'onru': 1, 'oru': 1, 'orey': 1,
  'rendu': 2, 'randu': 2, 'irandu': 2, 'rend': 2,
  'moonu': 3, 'munu': 3, 'moondru': 3,
  'naalu': 4, 'nalu': 4, 'naangu': 4,
  'anju': 5, 'anji': 5, 'ainthu': 5, 'aindhu': 5,
  'aaru': 6, 'ezhu': 7, 'elu': 7, 'ettu': 8,
  'onbadhu': 9, 'ombodhu': 9, 'ombadhu': 9,
  'pathu': 10, 'padhu': 10,
  'pathinonnu': 11, 'pannendu': 12, 'pannirendu': 12,
  'pathinanju': 15, 'irupathu': 20, 'iruvathu': 20,
  'irubathanju': 25, 'muppathu': 30, 'naapathu': 40,
  'aimbathu': 50, 'ambathu': 50, 'nooru': 100,
  'irunooru': 200, 'munnooru': 300, 'ainooru': 500,
  // English
  'one': 1, 'a': 1, 'an': 1, 'two': 2, 'to': 2, 'too': 2,
  'three': 3, 'four': 4, 'for': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
  'eleven': 11, 'twelve': 12, 'fifteen': 15, 'twenty': 20,
  'twentyfive': 25, 'thirty': 30, 'forty': 40, 'fifty': 50,
  'hundred': 100,
};

/// Fractions said before a unit: அரை கிலோ, kaal kilo, half kg.
const Map<String, double> _fractionWords = {
  'அரை': 0.5,
  'arai': 0.5,
  'ara': 0.5,
  'half': 0.5,
  'கால்': 0.25,
  'kaal': 0.25,
  'kal': 0.25,
  'quarter': 0.25,
  'முக்கால்': 0.75,
  'mukkaal': 0.75,
  'mukkal': 0.75,
  'ஒன்றரை': 1.5,
  'ஒன்னரை': 1.5,
  'onnarai': 1.5,
  'ondrarai': 1.5,
  'ரெண்டரை': 2.5,
  'rendarai': 2.5,
};

const Map<String, Unit> _unitWords = {
  'கிலோ': Unit.kg,
  'kilo': Unit.kg,
  'kilogram': Unit.kg,
  'kilograms': Unit.kg,
  'kilos': Unit.kg,
  'கிராம்': Unit.gram,
  'gram': Unit.gram,
  'grams': Unit.gram,
  'லிட்டர்': Unit.litre,
  'litre': Unit.litre,
  'liter': Unit.litre,
  'litres': Unit.litre,
  'liters': Unit.litre,
  'மில்லி': Unit.ml,
  'milli': Unit.ml,
  'millilitre': Unit.ml,
  'பீஸ்': Unit.piece,
  'piece': Unit.piece,
  'pieces': Unit.piece,
  'peace': Unit.piece,
  'டஜன்': Unit.dozen,
  'dozen': Unit.dozen,
  'dasan': Unit.dozen,
  'பாக்கெட்': Unit.packet,
  'packet': Unit.packet,
  'packets': Unit.packet,
  'pocket': Unit.packet,
  'pack': Unit.packet,
  'பாக்ஸ்': Unit.box,
  'பெட்டி': Unit.box,
  'box': Unit.box,
  'boxes': Unit.box,
  'petti': Unit.box,
  'bag': Unit.bag,
  'bags': Unit.bag,
};

/// Short unit abbreviations, matched on the raw lower-case word because
/// sound keys would mix them up (g and kg sound-fold to the same key).
/// மூட்டை (sack) is here too: its sound key is the same as முட்டை (egg).
const Map<String, Unit> abbreviationUnits = {
  'மூட்டை': Unit.bag,
  'mootai': Unit.bag,
  'moottai': Unit.bag,
  'kg': Unit.kg,
  'kgs': Unit.kg,
  'g': Unit.gram,
  'gm': Unit.gram,
  'gms': Unit.gram,
  'gr': Unit.gram,
  'l': Unit.litre,
  'ltr': Unit.litre,
  'lt': Unit.litre,
  'ml': Unit.ml,
  'pc': Unit.piece,
  'pcs': Unit.piece,
  'pkt': Unit.packet,
  'doz': Unit.dozen,
};

/// Words that only join items: "and", "apram" (then), "um", and "ok",
/// which owners say before each item: "ok hamam 1 packet ok salt 1 kg".
const List<String> _joinWords = [
  'ok',
  'okay',
  'okey',
  'okk',
  'okie',
  'next',
  'sari',
  'ஓகே',
  'ஓக்கே',
  'ஓகோ',
  'சரி',
  'and',
  'then',
  'also',
  'plus',
  'apram',
  'aprom',
  'appuram',
  'apparam',
  'matrum',
  'mathiri',
  'um',
  'அப்புறம்',
  'அப்றம்',
  'மற்றும்',
  'அப்பறம்',
  ',',
];

/// Filler words dropped from product names.
const List<String> _fillerWords = [
  'kudunga',
  'kudu',
  'venum',
  'vendum',
  'please',
  'give',
  'me',
  'of',
  'kodunga',
  'podunga',
  'podu',
  'add',
  'கொடுங்க',
  'குடுங்க',
  'வேணும்',
  'போடுங்க',
  'the',
];

class Vocabulary {
  Vocabulary._() {
    _numberWords.forEach((k, v) => numbers[wordKey(k)] = v);
    _fractionWords.forEach((k, v) => fractions[wordKey(k)] = v);
    _unitWords.forEach((k, v) => units[wordKey(k)] = v);
    for (final w in _joinWords) {
      joins.add(w == ',' ? ',' : wordKey(w));
    }
    for (final w in _fillerWords) {
      fillers.add(wordKey(w));
    }
  }

  static final Vocabulary instance = Vocabulary._();

  final Map<String, double> numbers = {};
  final Map<String, double> fractions = {};
  final Map<String, Unit> units = {};
  final Set<String> joins = {};
  final Set<String> fillers = {};

  /// Unit for a spoken word, checking abbreviations on the raw word first.
  Unit? unit(String rawWord, String key) =>
      abbreviationUnits[rawWord.toLowerCase().replaceAll('.', '')] ??
      units[key];

  /// Reads a number word or digits. Returns null when [key] is not a number.
  double? number(String key) {
    final digits = double.tryParse(key);
    if (digits != null) return digits;
    return numbers[key];
  }
}
