/// Selling and stock units supported by Smart Kadai.
///
/// Units in the same [UnitFamily] convert to each other with a fixed factor
/// (1 KG = 1000 GRAM, 1 LITRE = 1000 ML, 1 DOZEN = 12 PIECE). PACKET, BOX and
/// BAG hold a different amount for every product, so their conversion is
/// stored on each product variant instead (see `ProductVariant.stockFactor`).
enum Unit {
  kg('KG', 'கிலோ', UnitFamily.mass, 1000),
  gram('GRAM', 'கிராம்', UnitFamily.mass, 1),
  litre('LITRE', 'லிட்டர்', UnitFamily.volume, 1000),
  ml('ML', 'மி.லி', UnitFamily.volume, 1),
  piece('PIECE', 'பீஸ்', UnitFamily.count, 1),
  dozen('DOZEN', 'டஜன்', UnitFamily.count, 12),
  packet('PACKET', 'பாக்கெட்', UnitFamily.pack, 1),
  box('BOX', 'பெட்டி', UnitFamily.pack, 1),
  bag('BAG', 'மூட்டை', UnitFamily.pack, 1);

  const Unit(this.code, this.tamil, this.family, this.toBase);

  /// Upper-case code stored in the database, for example `KG`.
  final String code;

  /// Tamil label shown next to the code.
  final String tamil;

  final UnitFamily family;

  /// How many base units (gram, ml or piece) one of this unit holds.
  /// Only meaningful for [UnitFamily.mass], [UnitFamily.volume] and
  /// [UnitFamily.count].
  final double toBase;

  static Unit fromCode(String code) => Unit.values.firstWhere(
    (u) => u.code == code.toUpperCase(),
    orElse: () => throw ArgumentError('Unknown unit: $code'),
  );

  /// True when [quantity] of this unit can be converted to [other] without
  /// product-specific information.
  bool convertibleTo(Unit other) =>
      this == other || (family == other.family && family != UnitFamily.pack);

  /// Converts [quantity] of this unit into [target].
  ///
  /// Returns null when the two units cannot be converted without knowing the
  /// product (for example BOX to PIECE).
  double? convert(double quantity, Unit target) {
    if (this == target) return quantity;
    if (!convertibleTo(target)) return null;
    return roundQty(quantity * toBase / target.toBase);
  }

  /// Short label for a quantity, for example `250 GRAM` or `1 KG`.
  String format(double quantity) => '${formatQty(quantity)} $code';
}

enum UnitFamily { mass, volume, count, pack }

/// Rounds to 4 decimal places so 0.1 + 0.2 style float noise never reaches
/// stock figures.
double roundQty(double v) => (v * 10000).roundToDouble() / 10000;

/// Formats a quantity without trailing zeros: 1, 0.25, 2.5.
String formatQty(double v) {
  final r = roundQty(v);
  if (r == r.truncateToDouble()) return r.toInt().toString();
  return r.toString();
}
