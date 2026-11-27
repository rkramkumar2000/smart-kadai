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
    'ஆனியன்': 'Onion',
    'ஆவின் மில்க்': 'Aavin Milk',
    'ஆவின்': 'Aavin Milk',
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

  // Ram's screenshot: "ஆனியன் 1கே ஜி" was put down as Aavin Milk.
  for (final said in ['ஆனியன் 1கே ஜி', 'ஆனியன் 1 கே.ஜி', 'ஆனியன் 1 கேஜி']) {
    test('$said is 1 kg onion', () {
      s.handleSpoken(said, EntryMethod.voice);
      expect(s.pending, isEmpty);
      final l = s.bill.lines.single;
      expect(
        '${l.product.nameEn} ${l.unitLabel} x${l.count}',
        'Onion 1 KG x1.0',
      );
    });
  }

  test('one wrong tap does not make onion Aavin for ever', () {
    final p = s.products.firstWhere((p) => p.nameEn == 'Aavin Milk');
    s.repo.saveAlias('anian', p.id);
    s.refresh();
    s.handleSpoken('ஆனியன் 1 கிலோ', EntryMethod.voice);
    expect(s.bill.lines.single.product.nameEn, 'Onion');
  });

  // Ram: "முட்டை" (egg) was heard but nothing was added, because it sounds
  // like மூட்டை (a sack).
  for (final (said, count) in [
    ('முட்டை', 1.0),
    ('muttai', 1.0),
    ('10 முட்டை', 10.0),
    ('ரெண்டு முட்டை', 2.0),
  ]) {
    test('$said is egg x$count', () {
      s.handleSpoken(said, EntryMethod.voice);
      expect(s.pending, isEmpty);
      final l = s.bill.lines.single;
      expect(l.product.nameEn, 'Egg');
      expect(l.count, count);
    });
  }

  test('a sack of rice is still a sack', () {
    s.handleSpoken('ஒரு மூட்டை அரிசி', EntryMethod.voice);
    expect(s.bill.lines.single.product.nameEn, 'Ponni Rice');
  });
}
