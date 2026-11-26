import '../core/units.dart';

enum ProductStatus {
  active('ACTIVE', 'Active'),
  inactive('INACTIVE', 'Not selling');

  const ProductStatus(this.code, this.label);
  final String code;
  final String label;

  static ProductStatus fromCode(String c) => ProductStatus.values.firstWhere(
    (s) => s.code == c,
    orElse: () => ProductStatus.active,
  );
}

/// One way a product is sold, for example Groundnut 250 GRAM or Hamam Soap
/// 1 BOX.
class ProductVariant {
  ProductVariant({
    required this.id,
    required this.productId,
    required this.unit,
    required this.quantity,
    required this.stockFactor,
    required this.sellingPrice,
    this.purchasePrice = 0,
    this.wholesalePrice = 0,
    this.barcode,
    this.isDefault = false,
    this.sort = 0,
  });

  final String id;
  final String productId;

  /// Unit of this variant, for example GRAM.
  final Unit unit;

  /// Size of this variant in [unit], for example 250.
  final double quantity;

  /// How much of the product's stock unit one of this variant uses up.
  /// Groundnut 250 GRAM with stock kept in KG has a factor of 0.25.
  /// Hamam Soap 1 BOX with stock kept in PIECE might have a factor of 12.
  final double stockFactor;

  final double sellingPrice;
  final double purchasePrice;

  /// Price for wholesale customers. 0 means the same as [sellingPrice].
  final double wholesalePrice;

  /// Selling price for a retail or wholesale bill.
  double priceFor({required bool wholesale}) =>
      wholesale && wholesalePrice > 0 ? wholesalePrice : sellingPrice;
  final String? barcode;
  final bool isDefault;
  final int sort;

  /// Label such as `250 GRAM` or `1 BOX`.
  String get label => unit.format(quantity);

  /// Size of this variant expressed in a convertible [target] unit, or null.
  double? sizeIn(Unit target) => unit.convert(quantity, target);

  ProductVariant copyWith({
    String? id,
    String? productId,
    Unit? unit,
    double? quantity,
    double? stockFactor,
    double? sellingPrice,
    double? purchasePrice,
    double? wholesalePrice,
    String? barcode,
    bool? isDefault,
    int? sort,
  }) => ProductVariant(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    stockFactor: stockFactor ?? this.stockFactor,
    sellingPrice: sellingPrice ?? this.sellingPrice,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    wholesalePrice: wholesalePrice ?? this.wholesalePrice,
    barcode: barcode ?? this.barcode,
    isDefault: isDefault ?? this.isDefault,
    sort: sort ?? this.sort,
  );

  /// Works out [stockFactor] when the variant unit converts to the stock unit
  /// by a fixed rule. Returns null for PACKET, BOX and BAG to another unit,
  /// which the owner must enter.
  static double? autoStockFactor(
    Unit variantUnit,
    double variantQty,
    Unit stockUnit,
  ) => variantUnit.convert(variantQty, stockUnit);
}

class Product {
  Product({
    required this.id,
    required this.code,
    required this.nameEn,
    required this.nameTa,
    required this.nameTanglish,
    required this.stockUnit,
    this.category = '',
    this.brand = '',
    this.description = '',
    this.barcode,
    this.purchasePrice = 0,
    this.sellingPrice = 0,
    this.wholesalePrice = 0,
    this.minStock = 0,
    this.stockQty = 0,
    this.status = ProductStatus.active,
    required this.createdAt,
    required this.updatedAt,
    this.variants = const [],
  });

  final String id;

  /// Short product ID shown to the owner, for example P0001.
  final String code;
  final String nameEn;
  final String nameTa;
  final String nameTanglish;
  final String category;
  final String brand;
  final String description;

  /// Barcode of the base product (variants can have their own).
  final String? barcode;

  /// Purchase price per one [stockUnit].
  final double purchasePrice;

  /// Selling price per one [stockUnit]; used for loose quantities.
  final double sellingPrice;

  /// Wholesale price per one [stockUnit]. 0 means the same as retail.
  final double wholesalePrice;

  /// Loose price for a retail or wholesale bill.
  double priceFor({required bool wholesale}) =>
      wholesale && wholesalePrice > 0 ? wholesalePrice : sellingPrice;

  /// Alert when [stockQty] falls below this, in [stockUnit].
  final double minStock;

  /// Unit stock is counted in, for example KG for groundnut.
  final Unit stockUnit;
  final double stockQty;
  final ProductStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProductVariant> variants;

  bool get isLowStock => stockQty < minStock;

  ProductVariant? get defaultVariant {
    if (variants.isEmpty) return null;
    return variants.firstWhere(
      (v) => v.isDefault,
      orElse: () => variants.first,
    );
  }

  Product copyWith({
    String? code,
    String? nameEn,
    String? nameTa,
    String? nameTanglish,
    String? category,
    String? brand,
    String? description,
    String? barcode,
    double? purchasePrice,
    double? sellingPrice,
    double? wholesalePrice,
    double? minStock,
    Unit? stockUnit,
    double? stockQty,
    ProductStatus? status,
    DateTime? updatedAt,
    List<ProductVariant>? variants,
  }) => Product(
    id: id,
    code: code ?? this.code,
    nameEn: nameEn ?? this.nameEn,
    nameTa: nameTa ?? this.nameTa,
    nameTanglish: nameTanglish ?? this.nameTanglish,
    category: category ?? this.category,
    brand: brand ?? this.brand,
    description: description ?? this.description,
    barcode: barcode ?? this.barcode,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    sellingPrice: sellingPrice ?? this.sellingPrice,
    wholesalePrice: wholesalePrice ?? this.wholesalePrice,
    minStock: minStock ?? this.minStock,
    stockUnit: stockUnit ?? this.stockUnit,
    stockQty: stockQty ?? this.stockQty,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    variants: variants ?? this.variants,
  );
}
