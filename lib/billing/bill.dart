import '../catalogue/product.dart';
import '../core/units.dart';

enum EntryMethod { voice, scan, typed, tap }

enum PaymentMode {
  cash('CASH', 'Cash'),
  upi('UPI', 'UPI'),
  credit('CREDIT', 'Credit');

  const PaymentMode(this.code, this.label);
  final String code;
  final String label;
}

/// One line on the bill.
class BillLine {
  BillLine({
    required this.product,
    required this.variant,
    required this.count,
    required this.enteredBy,
    this.spokenText,
  });

  final Product product;

  /// Null for a loose sale counted in the product's stock unit.
  final ProductVariant? variant;

  /// Number of [variant]s, or amount of the stock unit when loose.
  final double count;
  final EntryMethod enteredBy;
  final String? spokenText;

  double get unitPrice => variant?.sellingPrice ?? product.sellingPrice;

  double get total => (unitPrice * count * 100).roundToDouble() / 100;

  /// What this line cost the shop, for profit reports.
  double get costTotal =>
      ((variant?.purchasePrice ?? product.purchasePrice) * count * 100)
          .roundToDouble() /
      100;

  /// How much the product's stock goes down, in its stock unit.
  /// 1 x Groundnut 250 GRAM with stock in KG reduces stock by 0.25.
  double get stockDelta => roundQty(count * (variant?.stockFactor ?? 1));

  /// "1 KG", "250 GRAM" or "0.75 KG (loose)".
  String get unitLabel => variant?.label ?? '${product.stockUnit.code} (loose)';

  /// "× 2" for counted lines, "0.75 KG" for loose lines.
  String get quantityLabel => variant == null
      ? product.stockUnit.format(count)
      : '× ${formatQty(count)}';

  BillLine withCount(double c) => BillLine(
    product: product,
    variant: variant,
    count: c,
    enteredBy: enteredBy,
    spokenText: spokenText,
  );

  BillLine withVariant(ProductVariant? v) => BillLine(
    product: product,
    variant: v,
    count: count,
    enteredBy: enteredBy,
    spokenText: spokenText,
  );
}

class Bill {
  final List<BillLine> lines = [];

  /// Rupees taken off the whole bill.
  double discount = 0;

  /// The customer the bill is for. Needed for credit (kadan) bills.
  String? customerId;
  String customerName = '';
  String customerPhone = '';

  /// Sum of the lines before discount.
  double get subtotal =>
      (lines.fold<double>(0, (s, l) => s + l.total) * 100).roundToDouble() /
      100;

  /// What the customer pays.
  double get total {
    final t = subtotal - discount;
    return t <= 0 ? 0 : (t * 100).roundToDouble() / 100;
  }

  /// Adds [line], merging with an identical product and variant already on
  /// the bill so repeated scans increase the count.
  void add(BillLine line) {
    final i = lines.indexWhere(
      (l) =>
          l.product.id == line.product.id && l.variant?.id == line.variant?.id,
    );
    if (i >= 0) {
      lines[i] = lines[i].withCount(roundQty(lines[i].count + line.count));
    } else {
      lines.add(line);
    }
  }
}
