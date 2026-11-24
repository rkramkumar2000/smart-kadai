import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../catalogue/product.dart';
import 'product_form.dart';
import 'product_import_dialog.dart';
import 'theme.dart';

/// Product catalogue: search in English, Tamil, Tanglish or by barcode,
/// filter by category, and add or edit products with their variants.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _query = '';
  String? _category;
  bool _showInactive = false;

  AppState get s => widget.state;

  List<Product> _filtered() {
    final q = _query.trim().toLowerCase();
    return s.products.where((p) {
      if (!_showInactive && p.status != ProductStatus.active) return false;
      if (_category != null && p.category != _category) return false;
      if (q.isEmpty) return true;
      return p.nameEn.toLowerCase().contains(q) ||
          p.nameTanglish.toLowerCase().contains(q) ||
          p.nameTa.contains(_query.trim()) ||
          p.code.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.barcode == _query.trim() ||
          p.variants.any((v) => v.barcode == _query.trim());
    }).toList();
  }

  Future<void> _edit(Product? p) async {
    final result = await showDialog<Product>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ProductForm(repo: s.repo, product: p, categories: _categories()),
    );
    if (result != null) {
      s.saveProduct(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${result.nameEn}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        );
      }
    }
  }

  List<String> _categories() {
    final set = s.products.map((p) => p.category).where((c) => c.isNotEmpty);
    return set.toSet().toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final rows = _filtered();
        final cats = _categories();
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const TwoLang('Products', 'பொருட்கள்', size: 24),
                  const SizedBox(width: 16),
                  Text(
                    '${s.activeProducts.length} selling',
                    style: const TextStyle(color: KadaiColors.quiet),
                  ),
                  const Spacer(),
                  if (s.user?.canEditProducts != false) ...[
                    TextButton.icon(
                      onPressed: () => saveProductTemplate(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Sample sheet'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => importProductsFlow(context, s),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import from Excel'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  FilledButton.icon(
                    onPressed: s.user?.canEditProducts == false
                        ? null
                        : () => _edit(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add product'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by English, Tamil or Tanglish name, ID or barcode',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final c in cats)
                    ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  FilterChip(
                    label: const Text('Show not selling'),
                    selected: _showInactive,
                    onSelected: (v) => setState(() => _showInactive = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: rows.isEmpty
                      ? const Center(
                          child: Text(
                            'No products match',
                            style: TextStyle(
                              fontSize: 17,
                              color: KadaiColors.quiet,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              showCheckboxColumn: false,
                              headingTextStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: KadaiColors.quiet,
                                fontSize: 14,
                              ),
                              dataRowMinHeight: 56,
                              dataRowMaxHeight: 64,
                              columns: const [
                                DataColumn(label: Text('ID')),
                                DataColumn(label: Text('Product')),
                                DataColumn(label: Text('Tanglish')),
                                DataColumn(label: Text('Category')),
                                DataColumn(label: Text('Brand')),
                                DataColumn(label: Text('Sold as')),
                                DataColumn(label: Text('Price'), numeric: true),
                                DataColumn(label: Text('Stock'), numeric: true),
                                DataColumn(label: Text('Status')),
                              ],
                              rows: [
                                for (final p in rows)
                                  DataRow(
                                    onSelectChanged:
                                        s.user?.canEditProducts == false
                                        ? null
                                        : (_) => _edit(p),
                                    cells: [
                                      DataCell(Text(p.code)),
                                      DataCell(
                                        TwoLang(p.nameEn, p.nameTa, size: 15),
                                      ),
                                      DataCell(Text(p.nameTanglish)),
                                      DataCell(Text(p.category)),
                                      DataCell(Text(p.brand)),
                                      DataCell(
                                        Text(
                                          p.variants
                                              .map((v) => v.label)
                                              .join(', '),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${rupees(p.sellingPrice)} / ${p.stockUnit.code}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          p.stockUnit.format(p.stockQty),
                                          style: TextStyle(
                                            fontWeight: p.isLowStock
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            color: p.isLowStock
                                                ? KadaiColors.warn
                                                : null,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(p.status.label)),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
