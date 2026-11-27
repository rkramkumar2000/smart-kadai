import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';

/// Owners often say "ok" before every item. It must split items and never
/// become part of a product name.
void main() {
  late AppState s;
  setUp(() {
    s = AppState(ShopRepository(AppDatabase.inMemory())..seedIfEmpty());
  });

  String bill() => s.bill.lines
      .map((l) => '${l.product.nameEn} ${l.unitLabel} x${l.count}')
      .join(' | ');

  for (final phrase in [
    'ok hamam 1 packet ok salt 1 kg ok rice 1 kg',
    'ok hamam 1 packet ok salt 1kg ok rice 1kg',
    'okay hamam one packet okay salt one kg okay rice one kg',
    'ஓகே ஹமாம் 1 பாக்கெட் ஓகே உப்பு 1 கிலோ ஓகே அரிசி 1 கிலோ',
    'சரி ஹமாம் 1 பாக்கெட் சரி உப்பு 1 கிலோ சரி அரிசி 1 கிலோ',
  ]) {
    test(phrase, () {
      s.handleSpoken(phrase, EntryMethod.voice);
      expect(s.pending, isEmpty);
      expect(
        bill(),
        'Hamam Soap 1 PIECE x1.0 | Salt 1 PACKET x1.0 | Ponni Rice 1 KG x1.0',
      );
    });
  }

  test('ok with kg, half kg and packets', () {
    s.handleSpoken(
      'OK sugar 2 kg OK toor dal half kg OK chocolate 2 packet',
      EntryMethod.voice,
    );
    expect(s.pending, isEmpty);
    expect(
      bill(),
      'Sugar 1 KG x2.0 | Toor Dal 500 GRAM x1.0 | Chocolate 1 PACKET x2.0',
    );
  });
}
