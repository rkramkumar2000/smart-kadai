import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../catalogue/product.dart';
import '../core/units.dart';
import '../voice/product_voice.dart';
import 'product_form.dart';
import 'hold_mic.dart';
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
  final _search = TextEditingController();

  /// Listening for a product name.
  bool _voiceOn = false;

  /// Whether this screen switched the mic on, so it switches it off again.
  bool _startedMic = false;

  /// What was said and what it found.
  SpokenProduct? _spoken;
  List<Product> _found = const [];
  String? _category;
  bool _showInactive = false;

  AppState get s => widget.state;

  @override
  void dispose() {
    if (s.voiceCapture == _onHeard) s.voiceCapture = null;
    _search.dispose();
    super.dispose();
  }

  /// Mic on the Products screen: the next thing said finds a product.
  Future<void> _voice() async {
    if (_voiceOn) {
      await _stopVoice();
      return;
    }
    s.voiceCapture = _onHeard;
    setState(() {
      _voiceOn = true;
      _spoken = null;
      _found = const [];
    });
    if (!s.listening) {
      _startedMic = true;
      await s.toggleListening();
    }
  }

  Future<void> _stopVoice() async {
    if (s.voiceCapture == _onHeard) s.voiceCapture = null;
    if (_startedMic && s.listening) await s.toggleListening();
    _startedMic = false;
    if (mounted) setState(() => _voiceOn = false);
  }

  void _onHeard(String text) {
    final sp = parseSpokenProduct(text);
    final found = sp.name.isEmpty ? <Product>[] : s.findByVoice(sp.name);
    _stopVoice();
    setState(() {
      _spoken = sp;
      _found = found;
      _query = '';
      _search.clear();
    });
  }

  /// What was heard, the products it sounds like, and "Add as new".
  Widget _voiceCard() {
    final sp = _spoken;
    if (!_voiceOn && sp == null) return const SizedBox.shrink();
    return Card(
      color: KadaiColors.greenTint,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.graphic_eq, color: KadaiColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sp == null
                        ? (s.heard.isEmpty || !_voiceOn
                              ? t(
                                  'Say a product name, or a new product with size and price: "Aavin milk 500 ml 28 rupees"',
                                  'பொருளின் பெயரை சொல்லுங்கள். புதிய பொருள்: "ஆவின் பால் 500 மில்லி 28 ரூபாய்"',
                                )
                              : '"${s.heard}"')
                        : '${t('Heard', 'கேட்டது')}: "${sp.name}"'
                              '${sp.size != null ? ' · ${formatQty(sp.size!)} ${sp.unit!.code}' : ''}'
                              '${sp.price != null ? ' · ${rupees(sp.price!)}' : ''}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                IconButton(
                  tooltip: t('Close', 'மூடு'),
                  onPressed: () {
                    _stopVoice();
                    setState(() => _spoken = null);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (sp != null) ...[
              const SizedBox(height: 8),
              if (_found.isNotEmpty)
                Text(
                  t('Tap to change it:', 'மாற்ற தொடுங்கள்:'),
                  style: const TextStyle(color: KadaiColors.quiet),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _found)
                    ActionChip(
                      avatar: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        '${p.nameEn} · ${p.nameTa} · ${rupees(p.sellingPrice)}',
                        style: const TextStyle(fontSize: 15),
                      ),
                      onPressed: s.user?.canEditProducts == false
                          ? null
                          : () => _edit(p),
                    ),
                  if (s.user?.canEditProducts != false && sp.name.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () => _edit(null, spoken: sp),
                      icon: const Icon(Icons.add),
                      label: Text(
                        t(
                          'Add "${sp.name}" as new',
                          '"${sp.name}" புதிதாக சேர்',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

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

  Future<void> _edit(Product? p, {SpokenProduct? spoken}) async {
    final result = await showDialog<Product>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductForm(
        repo: s.repo,
        product: p,
        categories: _categories(),
        spoken: spoken,
      ),
    );
    if (result != null) {
      s.saveProduct(result);
      if (mounted) setState(() => _spoken = null);
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
          padding: screenPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: Row(
                  children: [
                    const Flexible(
                      child: TwoLang('Products', 'பொருட்கள்', size: 24),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${s.activeProducts.length} selling',
                      style: const TextStyle(color: KadaiColors.quiet),
                    ),
                  ],
                ),
                actions: [
                  if (s.user?.canEditProducts != false) ...[
                    TextButton.icon(
                      onPressed: () => saveProductTemplate(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Sample sheet'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => importProductsFlow(context, s),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import from Excel'),
                    ),
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: isNarrow(context)
                            ? t('Search product', 'பொருள் தேடு')
                            : 'Search by English, Tamil or Tanglish name, ID or barcode',
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    width: 64,
                    child: Tooltip(
                      message: t('Find by voice', 'குரலில் தேடு'),
                      child: HoldMic(
                        state: s,
                        // Hold to speak: what is said while held finds the
                        // product. The finding stops once it is heard.
                        onHoldStart: () {
                          s.voiceCapture = _onHeard;
                          setState(() {
                            _voiceOn = true;
                            _spoken = null;
                            _found = const [];
                          });
                        },
                        child: FilledButton(
                          onPressed: s.holdToSpeak ? () {} : _voice,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: _voiceOn
                                ? KadaiColors.danger
                                : KadaiColors.green,
                          ),
                          child: Icon(
                            _voiceOn && !s.holdToSpeak ? Icons.stop : Icons.mic,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _voiceCard(),
              const SizedBox(height: 12),
              _chipRow(context, [
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
              ]),
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
                      : isNarrow(context)
                      ? _phoneList(rows)
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

  /// Filter chips wrap on the PC and scroll sideways on a phone.
  Widget _chipRow(BuildContext context, List<Widget> chips) {
    if (!isNarrow(context)) {
      return Wrap(spacing: 8, runSpacing: 8, children: chips);
    }
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  /// Products as a simple list on a phone: name, price and stock.
  Widget _phoneList(List<Product> rows) => ListView.separated(
    itemCount: rows.length,
    separatorBuilder: (_, _) =>
        const Divider(height: 1, color: Color(0xFFE8EBE4)),
    itemBuilder: (context, i) {
      final p = rows[i];
      return ListTile(
        onTap: s.user?.canEditProducts == false ? null : () => _edit(p),
        title: TwoLang(p.nameEn, p.nameTa, size: 16),
        subtitle: Text(
          '${rupees(p.sellingPrice)} / ${p.stockUnit.code}'
          '${p.status == ProductStatus.active ? '' : ' · ${p.status.label}'}',
        ),
        trailing: Text(
          p.stockUnit.format(p.stockQty),
          style: TextStyle(
            fontWeight: p.isLowStock ? FontWeight.w700 : FontWeight.w400,
            color: p.isLowStock ? KadaiColors.warn : null,
          ),
        ),
      );
    },
  );
}
