import 'package:material_ui/material_ui.dart';

import '../catalogue/product.dart';
import '../core/units.dart';
import '../data/shop_repository.dart';
import '../voice/phonetic.dart';
import 'barcode_scan.dart';
import 'save_file.dart' show isPhone;
import 'theme.dart';

/// Add or edit one product and the units it is sold in.
class ProductForm extends StatefulWidget {
  const ProductForm({
    super.key,
    required this.repo,
    required this.product,
    required this.categories,
  });

  final ShopRepository repo;
  final Product? product;
  final List<String> categories;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _VariantDraft {
  _VariantDraft({
    required this.id,
    required this.unit,
    required String qty,
    required String price,
    required String cost,
    String wholesale = '',
    required String barcode,
    required String factor,
    required this.isDefault,
  }) : qty = TextEditingController(text: qty),
       price = TextEditingController(text: price),
       cost = TextEditingController(text: cost),
       wholesale = TextEditingController(text: wholesale),
       barcode = TextEditingController(text: barcode),
       factor = TextEditingController(text: factor);

  final String id;
  Unit unit;
  bool isDefault;
  final TextEditingController qty, price, cost, wholesale, barcode, factor;

  void dispose() {
    for (final c in [qty, price, cost, wholesale, barcode, factor]) {
      c.dispose();
    }
  }
}

class _ProductFormState extends State<ProductForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _en,
      _ta,
      _tanglish,
      _category,
      _brand,
      _desc,
      _barcode,
      _cost,
      _price,
      _wholesale,
      _min,
      _stock;
  late Unit _stockUnit;
  late ProductStatus _status;
  late String _code;
  final List<_VariantDraft> _variants = [];
  String? _error;

  bool get _isNew => widget.product == null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _code = p?.code ?? widget.repo.nextProductCode();
    _en = TextEditingController(text: p?.nameEn ?? '');
    _ta = TextEditingController(text: p?.nameTa ?? '');
    _tanglish = TextEditingController(text: p?.nameTanglish ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _desc = TextEditingController(text: p?.description ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _cost = TextEditingController(text: _num(p?.purchasePrice));
    _price = TextEditingController(text: _num(p?.sellingPrice));
    _wholesale = TextEditingController(text: _num(p?.wholesalePrice));
    _min = TextEditingController(text: _num(p?.minStock));
    _stock = TextEditingController(text: _num(p?.stockQty));
    _stockUnit = p?.stockUnit ?? Unit.piece;
    _status = p?.status ?? ProductStatus.active;
    for (final v in p?.variants ?? const <ProductVariant>[]) {
      _variants.add(
        _VariantDraft(
          id: v.id,
          unit: v.unit,
          qty: formatQty(v.quantity),
          price: _num(v.sellingPrice),
          cost: _num(v.purchasePrice),
          wholesale: _num(v.wholesalePrice),
          barcode: v.barcode ?? '',
          factor: formatQty(v.stockFactor),
          isDefault: v.isDefault,
        ),
      );
    }
    if (_variants.isEmpty) _addVariant();
  }

  @override
  void dispose() {
    for (final c in [
      _en, _ta, _tanglish, _category, _brand, _desc, _barcode, _cost, //
      _price, _wholesale, _min, _stock,
    ]) {
      c.dispose();
    }
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  static String _num(double? v) => v == null || v == 0 ? '' : formatQty(v);
  static double _parse(String s) => double.tryParse(s.trim()) ?? 0;

  /// Category, brand, barcode, description and status are hidden until
  /// asked for, so adding a product needs only the name, price and size.
  late bool _more =
      widget.product != null &&
      (widget.product!.category.isNotEmpty ||
          widget.product!.brand.isNotEmpty ||
          (widget.product!.barcode ?? '').isNotEmpty ||
          widget.product!.description.isNotEmpty ||
          widget.product!.status != ProductStatus.active);

  void _addVariant() {
    setState(() {
      _variants.add(
        _VariantDraft(
          id: widget.repo.newId(),
          unit: _stockUnit,
          qty: '1',
          price: _price.text,
          cost: _cost.text,
          wholesale: _wholesale.text,
          barcode: '',
          factor: '1',
          isDefault: _variants.isEmpty,
        ),
      );
    });
  }

  /// Stock used by one of this variant, worked out when the units convert.
  double? _autoFactor(_VariantDraft v) =>
      ProductVariant.autoStockFactor(v.unit, _parse(v.qty.text), _stockUnit);

  void _save() {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final now = DateTime.now();
    final id = widget.product?.id ?? widget.repo.newId();

    // Barcodes must be unique across the shop.
    final codes = <String>[
      if (_barcode.text.trim().isNotEmpty) _barcode.text.trim(),
      for (final v in _variants)
        if (v.barcode.text.trim().isNotEmpty) v.barcode.text.trim(),
    ];
    if (codes.toSet().length != codes.length) {
      setState(() => _error = 'The same barcode is used twice.');
      return;
    }
    for (final c in codes) {
      if (widget.repo.barcodeInUse(c, exceptProductId: id)) {
        setState(
          () => _error = 'Barcode $c is already used by another product.',
        );
        return;
      }
    }

    final variants = <ProductVariant>[];
    for (final (i, d) in _variants.indexed) {
      final qty = _parse(d.qty.text);
      final factor = _autoFactor(d) ?? _parse(d.factor.text);
      if (qty <= 0 || factor <= 0) {
        setState(
          () => _error =
              'Variant ${i + 1}: enter its size and how much stock it uses.',
        );
        return;
      }
      variants.add(
        ProductVariant(
          id: d.id,
          productId: id,
          unit: d.unit,
          quantity: qty,
          stockFactor: factor,
          sellingPrice: _parse(d.price.text),
          purchasePrice: _parse(d.cost.text),
          wholesalePrice: _parse(d.wholesale.text),
          barcode: d.barcode.text.trim(),
          isDefault: d.isDefault,
          sort: i,
        ),
      );
    }
    if (variants.isNotEmpty && !variants.any((v) => v.isDefault)) {
      variants[0] = variants[0].copyWith(isDefault: true);
    }

    // Fill what the owner left empty: the price per stock unit comes from the
    // usual size, a size without a price gets it from the stock-unit price,
    // and Tanglish comes from the Tamil (or English) name.
    var price = _parse(_price.text);
    var cost = _parse(_cost.text);
    var wholesale = _parse(_wholesale.text);
    final usual = variants.isEmpty
        ? null
        : variants.firstWhere((v) => v.isDefault, orElse: () => variants[0]);
    if (usual != null && usual.stockFactor > 0) {
      if (price == 0) price = roundQty(usual.sellingPrice / usual.stockFactor);
      if (cost == 0) cost = roundQty(usual.purchasePrice / usual.stockFactor);
      if (wholesale == 0) {
        wholesale = roundQty(usual.wholesalePrice / usual.stockFactor);
      }
    }
    for (final (i, v) in variants.indexed) {
      variants[i] = v.copyWith(
        sellingPrice: v.sellingPrice == 0
            ? roundQty(price * v.stockFactor)
            : v.sellingPrice,
        purchasePrice: v.purchasePrice == 0
            ? roundQty(cost * v.stockFactor)
            : v.purchasePrice,
        wholesalePrice: v.wholesalePrice == 0
            ? roundQty(wholesale * v.stockFactor)
            : v.wholesalePrice,
      );
    }
    if (price == 0 && variants.every((v) => v.sellingPrice == 0)) {
      setState(() => _error = 'Enter a selling price.');
      return;
    }
    var tanglish = _tanglish.text.trim();
    if (tanglish.isEmpty) {
      tanglish = _ta.text.trim().isNotEmpty
          ? transliterateTamil(_ta.text.trim())
          : _en.text.trim();
    }

    final base = widget.product;
    final product = Product(
      id: id,
      code: _code,
      nameEn: _en.text.trim(),
      nameTa: _ta.text.trim(),
      nameTanglish: tanglish,
      category: _category.text.trim(),
      brand: _brand.text.trim(),
      description: _desc.text.trim(),
      barcode: _barcode.text.trim(),
      purchasePrice: cost,
      sellingPrice: price,
      wholesalePrice: wholesale,
      minStock: _parse(_min.text),
      stockUnit: _stockUnit,
      stockQty: base?.stockQty ?? _parse(_stock.text),
      status: _status,
      createdAt: base?.createdAt ?? now,
      updatedAt: now,
      variants: variants,
    );
    Navigator.of(context).pop(product);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    _narrow = isNarrow(context);
    return Dialog(
      insetPadding: _narrow ? EdgeInsets.zero : const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 860),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(_pad, 20, _pad, 8),
                child: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _isNew ? 'Add product' : 'Edit product',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'ID $_code',
                      style: const TextStyle(color: KadaiColors.quiet),
                    ),
                    if (p != null)
                      Text(
                        'Created ${_date(p.createdAt)} · Updated ${_date(p.updatedAt)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: KadaiColors.quiet,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(_pad, 8, _pad, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row([
                        _field(_en, 'English name *', required: true),
                        _field(_ta, 'Tamil name · தமிழ் பெயர்'),
                        _field(
                          _tanglish,
                          'Tanglish (optional, filled for you)',
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _row([
                        DropdownButtonFormField<Unit>(
                          isExpanded: true,
                          initialValue: _stockUnit,
                          decoration: const InputDecoration(
                            labelText: 'Stock counted in',
                          ),
                          items: [
                            for (final u in Unit.values)
                              DropdownMenuItem(
                                value: u,
                                child: Text('${u.code} · ${u.tamil}'),
                              ),
                          ],
                          onChanged: (u) =>
                              setState(() => _stockUnit = u ?? _stockUnit),
                        ),
                        _field(
                          _cost,
                          'Purchase price per $_unitName (₹)',
                          number: true,
                        ),
                        _field(
                          _price,
                          'Selling price per $_unitName (₹)',
                          number: true,
                        ),
                        _field(
                          _wholesale,
                          'Wholesale price per $_unitName (₹, optional)',
                          number: true,
                        ),
                      ]),
                      _row([
                        _field(
                          _min,
                          'Minimum stock ($_unitName)',
                          number: true,
                        ),
                        _isNew
                            ? _field(
                                _stock,
                                'Opening stock ($_unitName)',
                                number: true,
                              )
                            : InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Current stock',
                                ),
                                child: Text(_stockUnit.format(p!.stockQty)),
                              ),
                        const SizedBox.shrink(),
                      ]),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _more = !_more),
                          icon: Icon(
                            _more ? Icons.expand_less : Icons.expand_more,
                          ),
                          label: Text(
                            _more ? 'Fewer details' : 'More details: category, brand, barcode, status',
                          ),
                        ),
                      ),
                      if (_more) ...[
                        _row([
                          Autocomplete<String>(
                            initialValue: _category.value,
                            optionsBuilder: (v) => widget.categories.where(
                              (c) => c.toLowerCase().contains(
                                v.text.toLowerCase(),
                              ),
                            ),
                            onSelected: (c) => _category.text = c,
                            fieldViewBuilder: (context, c, f, _) {
                              c.addListener(() => _category.text = c.text);
                              return TextFormField(
                                controller: c,
                                focusNode: f,
                                decoration: const InputDecoration(
                                  labelText: 'Category',
                                ),
                              );
                            },
                          ),
                          _field(_brand, 'Brand'),
                          _field(_barcode, 'Barcode', scan: true),
                        ]),
                        _field(_desc, 'Description', lines: 2),
                        _row([
                          DropdownButtonFormField<ProductStatus>(
                            isExpanded: true,
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                            items: [
                              for (final s in ProductStatus.values)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text(s.label),
                                ),
                            ],
                            onChanged: (s) =>
                                setState(() => _status = s ?? _status),
                          ),
                          const SizedBox.shrink(),
                          const SizedBox.shrink(),
                        ]),
                      ],
                      const SizedBox(height: 16),
                      ScreenHeader(
                        title: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TwoLang('Sold as', 'விற்கும் அளவுகள்', size: 18),
                            Text(
                              'For example 250 GRAM, 1 KG, 1 BOX. The one marked with a star is used when only a number is said.',
                              style: TextStyle(
                                fontSize: 13,
                                color: KadaiColors.quiet,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          OutlinedButton.icon(
                            onPressed: _addVariant,
                            icon: const Icon(Icons.add),
                            label: const Text('Add size'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final (i, v) in _variants.indexed) _variantRow(i, v),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: _pad),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: KadaiColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(_pad, 12, _pad, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(140, 52),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _unitName => _stockUnit.code;

  Widget _variantRow(int i, _VariantDraft v) {
    if (_narrow) return _phoneVariant(i, v);
    final auto = _autoFactor(v);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: _field(
              v.qty,
              'Size',
              number: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<Unit>(
              isExpanded: true,
              initialValue: v.unit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: [
                for (final u in Unit.values)
                  DropdownMenuItem(value: u, child: Text(u.code)),
              ],
              onChanged: (u) => setState(() => v.unit = u ?? v.unit),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _field(v.price, 'Selling ₹', number: true)),
          const SizedBox(width: 8),
          Expanded(child: _field(v.wholesale, 'Wholesale ₹', number: true)),
          const SizedBox(width: 8),
          Expanded(child: _field(v.cost, 'Purchase ₹', number: true)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _field(v.barcode, 'Barcode', scan: true)),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: auto != null
                ? InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Uses stock ($_unitName)',
                    ),
                    child: Text(formatQty(auto)),
                  )
                : _field(
                    v.factor,
                    '$_unitName in 1 ${v.unit.code}',
                    number: true,
                  ),
          ),
          const SizedBox(width: 4),
          Column(
            children: [
              const Text('Usual', style: TextStyle(fontSize: 12)),
              IconButton(
                tooltip: 'Use this size when only a number is said',
                onPressed: () => setState(() {
                  for (final d in _variants) {
                    d.isDefault = d == v;
                  }
                }),
                icon: Icon(
                  v.isDefault ? Icons.star : Icons.star_border,
                  color: v.isDefault ? KadaiColors.green : KadaiColors.quiet,
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Remove size',
            onPressed: _variants.length == 1
                ? null
                : () => setState(() {
                    _variants.removeAt(i).dispose();
                    if (!_variants.any((d) => d.isDefault)) {
                      _variants.first.isDefault = true;
                    }
                  }),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  void _makeUsual(_VariantDraft v) => setState(() {
    for (final d in _variants) {
      d.isDefault = d == v;
    }
  });

  void _removeVariant(int i) => setState(() {
    _variants.removeAt(i).dispose();
    if (!_variants.any((d) => d.isDefault)) {
      _variants.first.isDefault = true;
    }
  });

  /// One size on a phone, as a small card of fields.
  Widget _phoneVariant(int i, _VariantDraft v) {
    final auto = _autoFactor(v);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: _field(
                    v.qty,
                    'Size',
                    number: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<Unit>(
                    isExpanded: true,
                    initialValue: v.unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: [
                      for (final u in Unit.values)
                        DropdownMenuItem(value: u, child: Text(u.code)),
                    ],
                    onChanged: (u) => setState(() => v.unit = u ?? v.unit),
                  ),
                ),
                IconButton(
                  tooltip: 'Use this size when only a number is said',
                  onPressed: () => _makeUsual(v),
                  icon: Icon(
                    v.isDefault ? Icons.star : Icons.star_border,
                    color: v.isDefault ? KadaiColors.green : KadaiColors.quiet,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove size',
                  onPressed: _variants.length == 1
                      ? null
                      : () => _removeVariant(i),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _field(v.price, 'Selling ₹', number: true)),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(v.wholesale, 'Wholesale ₹', number: true),
                ),
                const SizedBox(width: 8),
                Expanded(child: _field(v.cost, 'Purchase ₹', number: true)),
                const SizedBox(width: 4),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _field(v.barcode, 'Barcode', scan: true),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: auto != null
                  ? InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Uses stock ($_unitName)',
                      ),
                      child: Text(formatQty(auto)),
                    )
                  : _field(
                      v.factor,
                      '$_unitName in 1 ${v.unit.code}',
                      number: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _narrow = false;
  double get _pad => _narrow ? 14 : 24;

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _narrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in children)
                if (c is! SizedBox) ...[c, const SizedBox(height: 12)],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, c) in children.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: c),
              ],
            ],
          ),
  );

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    bool number = false,
    int lines = 1,
    ValueChanged<String>? onChanged,
    bool scan = false,
  }) => TextFormField(
    controller: c,
    maxLines: lines,
    onChanged: onChanged,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: scan && isPhone
          ? IconButton(
              tooltip: tt('Scan barcode', 'பார்கோடு ஸ்கேன்'),
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final code = await scanBarcode(context);
                if (code != null) c.text = code;
              },
            )
          : null,
    ),
    validator: (v) {
      if (required && (v == null || v.trim().isEmpty)) return 'Required';
      if (number &&
          v != null &&
          v.trim().isNotEmpty &&
          double.tryParse(v.trim()) == null) {
        return 'Enter a number';
      }
      return null;
    },
  );

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}
