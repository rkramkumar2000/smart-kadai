import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/core/units.dart';
import 'package:smart_kadai/data/seed.dart';
import 'package:smart_kadai/voice/phonetic.dart';
import 'package:smart_kadai/voice/product_matcher.dart';
import 'package:smart_kadai/voice/utterance_parser.dart';

void main() {
  final products = starterCatalogue(DateTime(2026, 11, 24));
  final parser = UtteranceParser();
  final matcher = ProductMatcher(products);

  VoiceMatch one(String said) {
    final items = parser.parse(said);
    expect(items, hasLength(1), reason: 'items for "$said": $items');
    return matcher.match(items.first);
  }

  group('sound keys', () {
    test('Tamil script and Tanglish give the same key', () {
      expect(wordKey('கடலை'), wordKey('kadalai'));
      expect(wordKey('மிட்டாய்'), wordKey('mittai'));
      expect(wordKey('தக்காளி'), wordKey('thakkali'));
      expect(wordKey('thakali'), wordKey('thakkali'));
    });
    test('digits split from letters', () {
      expect(splitWords('250g kadalai'), ['250', 'g', 'kadalai']);
    });
  });

  group("Ram's voice examples", () {
    test('ரெண்டு கடலை மிட்டாய் -> Groundnut Candy x 2', () {
      final m = one('ரெண்டு கடலை மிட்டாய்');
      expect(m.product!.nameEn, 'Groundnut Candy');
      expect(m.count, 2);
      expect(m.variant!.unit, Unit.piece);
      expect(m.needsConfirmation, isFalse);
    });
    test('Two Hamam soap -> Hamam Soap x 2', () {
      final m = one('Two Hamam soap');
      expect(m.product!.nameEn, 'Hamam Soap');
      expect(m.count, 2);
      expect(m.needsConfirmation, isFalse);
    });
    test('அஞ்சு சாக்லேட் -> Chocolate x 5', () {
      final m = one('அஞ்சு சாக்லேட்');
      expect(m.product!.nameEn, 'Chocolate');
      expect(m.count, 5);
      expect(m.needsConfirmation, isFalse);
    });
    test('Oru kilo kadalai -> Groundnut x 1 KG', () {
      final m = one('Oru kilo kadalai');
      expect(m.product!.nameEn, 'Groundnut');
      expect(m.variant!.label, '1 KG');
      expect(m.count, 1);
      expect(m.needsConfirmation, isFalse);
    });
    test('அரை கிலோ கடலை -> Groundnut x 500 GRAM', () {
      final m = one('அரை கிலோ கடலை');
      expect(m.product!.nameEn, 'Groundnut');
      expect(m.variant!.label, '500 GRAM');
      expect(m.count, 1);
    });
    test('Two packet chocolate -> Chocolate x 2 Packets', () {
      final m = one('Two packet chocolate');
      expect(m.product!.nameEn, 'Chocolate');
      expect(m.variant!.unit, Unit.packet);
      expect(m.count, 2);
    });
  });

  group('harder speech', () {
    test('several items in one breath, no pauses', () {
      final items = parser.parse(
        'rendu kadalai mittai oru kilo kadalai anju chocolate',
      );
      expect(items, hasLength(3));
      final names = items.map((i) => matcher.match(i).product!.nameEn).toList();
      expect(names, ['Groundnut Candy', 'Groundnut', 'Chocolate']);
    });
    test('quantity after the name', () {
      final items = parser.parse('kadalai mittai rendu hamam soap moonu');
      expect(items, hasLength(2));
      expect(matcher.match(items[0]).count, 2);
      expect(matcher.match(items[1]).product!.nameEn, 'Hamam Soap');
      expect(matcher.match(items[1]).count, 3);
    });
    test('short name: "hamam" is enough', () {
      expect(one('rendu hamam').product!.nameEn, 'Hamam Soap');
    });
    test('different spelling: thakali, tomatto', () {
      expect(one('arai kilo thakali').product!.nameEn, 'Tomato');
      expect(one('oru kilo tomatto').product!.nameEn, 'Tomato');
    });
    test('filler words are ignored', () {
      final m = one('rendu kadalai mittai kudunga');
      expect(m.product!.nameEn, 'Groundnut Candy');
    });
    test('2 kilo uses the 1 KG variant twice', () {
      final m = one('rendu kilo kadalai');
      expect(m.variant!.label, '1 KG');
      expect(m.count, 2);
    });
    test('750 gram uses the 250 GRAM variant three times', () {
      final m = one('750 gram kadalai');
      expect(m.variant!.label, '250 GRAM');
      expect(m.count, 3);
    });
    test('700 gram with no fitting variant is sold loose in KG', () {
      final m = one('700 gram kadalai');
      expect(m.variant, isNull);
      expect(m.count, 0.7);
    });
    test('unknown product asks the owner', () {
      final m = one('rendu xylophone');
      expect(m.needsConfirmation, isTrue);
    });
    test('soap alone is unsure between two soaps', () {
      final m = one('oru soap');
      expect(m.needsConfirmation, isTrue);
      expect(m.candidates.length, greaterThanOrEqualTo(2));
    });
    test('a learned correction becomes a sure match', () {
      final local = ProductMatcher(products);
      final item = parser.parse('oru soap').first;
      final hamam = products.firstWhere((p) => p.nameEn == 'Hamam Soap');
      local.learn(item.nameWords, hamam);
      final m = local.match(item);
      expect(m.product!.nameEn, 'Hamam Soap');
      expect(m.needsConfirmation, isFalse);
    });
  });

  group('stock', () {
    test('250 GRAM sale reduces KG stock by 0.25', () {
      final g = products.firstWhere((p) => p.nameEn == 'Groundnut');
      final v = g.variants.firstWhere((v) => v.label == '250 GRAM');
      final line = BillLine(
        product: g,
        variant: v,
        count: 1,
        enteredBy: EntryMethod.voice,
      );
      expect(line.stockDelta, 0.25);
      expect(line.total, 35);
    });
    test('1 BOX of Hamam reduces PIECE stock by the box size', () {
      final h = products.firstWhere((p) => p.nameEn == 'Hamam Soap');
      final box = h.variants.firstWhere((v) => v.unit == Unit.box);
      final line = BillLine(
        product: h,
        variant: box,
        count: 2,
        enteredBy: EntryMethod.tap,
      );
      expect(line.stockDelta, 2 * box.stockFactor);
    });
    test('unit conversion', () {
      expect(Unit.kg.convert(1, Unit.gram), 1000);
      expect(Unit.gram.convert(250, Unit.kg), 0.25);
      expect(Unit.ml.convert(500, Unit.litre), 0.5);
      expect(Unit.dozen.convert(2, Unit.piece), 24);
      expect(Unit.box.convert(1, Unit.piece), isNull);
    });
  });
}
