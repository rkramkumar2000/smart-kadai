import '../core/units.dart';
import 'phonetic.dart';
import 'vocabulary.dart';

/// A product said aloud on the Products screen, for example
/// "Aavin milk 500 ml 28 rupees" or "ஆச்சி மிளகாய் தூள் 100 கிராம் 45 ரூபாய்".
class SpokenProduct {
  SpokenProduct({
    required this.name,
    required this.isTamil,
    this.size,
    this.unit,
    this.price,
  });

  /// The product name as heard, numbers, sizes and prices removed.
  final String name;

  /// The name was heard in Tamil letters.
  final bool isTamil;
  final double? size;
  final Unit? unit;
  final double? price;
}

final _tamil = RegExp('[஀-௿]');

/// Words that mark a price: "28 rupees", "28 ரூபாய்", "vilai 28".
const _rupeeWords = {
  'rupees', 'rupee', 'rs', 'rs.', 'inr', 'rupa', 'rubai', 'roobai', 'rupai', //
  'ரூபாய்', 'ருபாய்', 'ரூபா', 'ரூ', 'ரூ.', '₹',
};
const _priceWords = {'vilai', 'velai', 'price', 'rate', 'விலை', 'ரேட்'};

bool _isRupee(String w) => _rupeeWords.contains(w.toLowerCase());

/// Reads a spoken product into its name, size and price.
SpokenProduct parseSpokenProduct(String text) {
  final v = Vocabulary.instance;
  final words = splitWords(text.replaceAll('₹', ' ₹ '));
  final name = <String>[];
  double? size, price;
  Unit? unit;
  var priceNext = false;

  double? numberAt(int i) {
    final k = wordKey(words[i]);
    return v.fractions[k] ?? v.number(k);
  }

  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final key = wordKey(w);
    if (w == ',' || v.joins.contains(key) || v.fillers.contains(key)) continue;
    if (_isRupee(w)) {
      priceNext = true; // "₹ 28", "rs 28"
      continue;
    }
    if (_priceWords.contains(w.toLowerCase())) {
      priceNext = true;
      continue;
    }
    final n = numberAt(i);
    if (n != null) {
      final next = i + 1 < words.length ? words[i + 1] : '';
      final nextUnit = next.isEmpty ? null : v.unit(next, wordKey(next));
      if (priceNext || _isRupee(next)) {
        price = n;
        priceNext = false;
        if (_isRupee(next)) i++;
      } else if (nextUnit != null && size == null) {
        size = n;
        unit = nextUnit;
        i++;
      } else if (size != null || price == null) {
        // A last number with no word after it is the price.
        price = n;
      }
      continue;
    }
    final u = v.unit(w, key);
    if (u != null && size == null && unit == null) {
      // "kilo" alone means 1 kilo.
      unit = u;
      size = 1;
      continue;
    }
    name.add(w);
  }
  final n = name.join(' ').trim();
  return SpokenProduct(
    name: n,
    isTamil: _tamil.hasMatch(n),
    size: size,
    unit: unit,
    price: price,
  );
}
