import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';

/// Chrome's Tamil recogniser writes English product names in Tamil letters.
/// These must go straight on the bill without a question.
void main() {
  late AppState s;
  setUp(() {
    s = AppState(ShopRepository(AppDatabase.inMemory())..seedIfEmpty());
  });

  const heard = {
    'சன் ஃபிளவர் ஆயில்': 'Sunflower Oil',
    'சன்ஃபிளவர் ஆயில்': 'Sunflower Oil',
    'டீ பவுடர்': 'Tea Powder',
    'ரைஸ்': 'Ponni Rice',
    'டொமேட்டோ': 'Tomato',
    'டிடர்ஜென்ட் சோப்': 'Detergent Soap',
    'கிரவுண்ட்நட்': 'Groundnut',
    'கிரவுண்ட் நட்': 'Groundnut',
    'ஹமாம் சோப்': 'Hamam Soap',
    'சாக்லேட்': 'Chocolate',
    'ஷுகர்': 'Sugar',
    'சால்ட்': 'Salt',
    'மில்க்': 'Aavin Milk',
  };

  heard.forEach((said, product) {
    test('$said is $product', () {
      s.handleSpoken(said, EntryMethod.voice);
      expect(s.pending, isEmpty);
      expect(s.bill.lines.single.product.nameEn, product);
    });
  });

  test('a stray sound asks nothing', () {
    s.handleSpoken('ஜி', EntryMethod.voice);
    expect(s.pending, isEmpty);
    expect(s.bill.lines, isEmpty);
  });

  test('a whole order in Tamil letters with ok', () {
    s.handleSpoken(
      'ஓகே ஷுகர் 1 கிலோ ஓகே சன் ஃபிளவர் ஆயில் 1 லிட்டர் ஓகே டீ பவுடர்',
      EntryMethod.voice,
    );
    expect(s.pending, isEmpty);
    expect(s.bill.lines.map((l) => l.product.nameEn), [
      'Sugar',
      'Sunflower Oil',
      'Tea Powder',
    ]);
  });
}
