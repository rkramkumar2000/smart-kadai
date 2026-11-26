import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../catalogue/product.dart';
import '../core/units.dart';
import '../purchases/invoice_reader.dart';
import '../purchases/purchases.dart';
import 'theme.dart';

/// Supplier bills: suppliers and what the shop owes them, recent purchases,
/// a new purchase typed in, or read from a photo of the bill.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.state});

  final AppState state;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  AppState get s => widget.state;
  PurchaseRepository get buy => s.purchases;

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text, style: const TextStyle(fontSize: 15))),
  );

  Future<void> _newPurchase([InvoiceDraft? draft, String? imagePath]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            PurchaseFormPage(state: s, draft: draft, imagePath: imagePath),
      ),
    );
    if (saved == true) {
      s.refresh();
      setState(() {});
      _snack('Purchase saved. Stock is updated.');
    }
  }

  Future<void> _readPhoto() async {
    final key = s.repo.setting('ai_key', '');
    if (key.isEmpty) {
      _snack('Add the AI key in Settings first to read bill photos.');
      return;
    }
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Bill photo or PDF',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    final ext = file.name.split('.').last.toLowerCase();
    final type = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => 'image/jpeg',
    };
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(
              child: Text(
                'Reading the bill. This takes about half a minute.',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
    final reader = InvoiceReader(key);
    InvoiceDraft? draft;
    String? error;
    try {
      draft = await reader.read(bytes, type);
    } on InvoiceReadException catch (e) {
      error = e.message;
    } finally {
      reader.close();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (draft == null) {
      _snack(error ?? 'Could not read the bill.');
      return;
    }
    await _newPurchase(draft, file.path);
  }

  Future<void> _pay(Supplier sup) async {
    final amt = TextEditingController(text: formatQty(sup.balance));
    var mode = 'CASH';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Pay ${sup.name}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You owe ${rupees(sup.balance)}',
                  style: const TextStyle(color: KadaiColors.quiet),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amt,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount ₹'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const ['CASH', 'UPI', 'BANK'])
                      ChoiceChip(
                        label: Text(m),
                        selected: mode == m,
                        onSelected: (_) => setLocal(() => mode = m),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save payment'),
            ),
          ],
        ),
      ),
    );
    final v = double.tryParse(amt.text.trim());
    amt.dispose();
    if (ok != true || v == null || v <= 0) return;
    buy.paySupplier(sup.id, v, mode);
    setState(() {});
    _snack('Paid ${rupees(v)} to ${sup.name}');
  }

  Future<void> _editSupplier([Supplier? sup]) async {
    final saved = await showSupplierDialog(context, buy, sup);
    if (saved != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = buy.suppliers();
    final recent = buy.recentPurchases(limit: 50);
    final owed = suppliers.fold<double>(0, (t, x) => t + x.balance);
    final suppliersCard = Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: const Text(
              'Suppliers · வியாபாரிகள்',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            subtitle: Text('You owe ${rupees(owed)} in all'),
            trailing: TextButton.icon(
              onPressed: () => _editSupplier(),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: suppliers.isEmpty
                ? const Center(
                    child: Text(
                      'No suppliers yet',
                      style: TextStyle(color: KadaiColors.quiet),
                    ),
                  )
                : ListView(
                    children: [
                      for (final sup in suppliers)
                        ListTile(
                          onTap: () => _editSupplier(sup),
                          title: Text(
                            sup.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (sup.phone.isNotEmpty) sup.phone,
                              if (sup.gstin.isNotEmpty) sup.gstin,
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                rupees(sup.balance),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: sup.balance > 0
                                      ? KadaiColors.danger
                                      : KadaiColors.quiet,
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: sup.balance > 0
                                    ? () => _pay(sup)
                                    : null,
                                child: const Text('Pay'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
    final billsCard = Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            title: Text(
              'Recent supplier bills',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: recent.isEmpty
                ? const Center(
                    child: Text(
                      'No purchases yet',
                      style: TextStyle(color: KadaiColors.quiet),
                    ),
                  )
                : ListView(
                    children: [
                      for (final p in recent)
                        ListTile(
                          leading: Icon(
                            p.source == 'OCR'
                                ? Icons.photo_camera_outlined
                                : Icons.receipt_long_outlined,
                            color: KadaiColors.quiet,
                          ),
                          title: Text(p.supplierName),
                          subtitle: Text(
                            '${_day(p.date)}'
                            '${p.invoiceNo.isEmpty ? '' : ' · Bill ${p.invoiceNo}'}'
                            ' · ${p.itemCount} items',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                rupees(p.total),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (p.due > 0)
                                Text(
                                  'Due ${rupees(p.due)}',
                                  style: const TextStyle(
                                    color: KadaiColors.danger,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
    return Padding(
      padding: screenPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: const TwoLang('Purchases', 'கொள்முதல்', size: 24),
            actions: [
              OutlinedButton.icon(
                onPressed: _readPhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Read bill photo'),
              ),
              FilledButton.icon(
                onPressed: () => _newPurchase(),
                icon: const Icon(Icons.add),
                label: const Text('New purchase'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: isNarrow(context)
                ? DefaultTabController(
                    length: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          tabs: [
                            Tab(text: t('Suppliers', 'வியாபாரிகள்')),
                            Tab(text: t('Bills', 'பில்கள்')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            children: [suppliersCard, billsCard],
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: suppliersCard),
                      const SizedBox(width: 14),
                      Expanded(flex: 5, child: billsCard),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

/// Add or edit a supplier. Returns the saved supplier.
Future<Supplier?> showSupplierDialog(
  BuildContext context,
  PurchaseRepository buy, [
  Supplier? sup,
  String name = '',
  String gstin = '',
]) async {
  final n = TextEditingController(text: sup?.name ?? name);
  final ph = TextEditingController(text: sup?.phone ?? '');
  final g = TextEditingController(text: sup?.gstin ?? gstin);
  final a = TextEditingController(text: sup?.address ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(sup == null ? 'Add supplier' : 'Edit supplier'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: n,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name · பெயர்'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ph,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: g,
              decoration: const InputDecoration(labelText: 'GSTIN (if any)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: a,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (n.text.trim().isEmpty) return;
            Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  Supplier? saved;
  if (ok == true) {
    saved = buy.saveSupplier(
      Supplier(
        id: sup?.id ?? buy.shop.newId(),
        name: n.text.trim(),
        phone: ph.text.trim(),
        gstin: g.text.trim().toUpperCase(),
        address: a.text.trim(),
        balance: sup?.balance ?? 0,
      ),
    );
  }
  for (final c in [n, ph, g, a]) {
    c.dispose();
  }
  return saved;
}

class _LineEdit {
  _LineEdit({
    this.product,
    this.variant,
    this.readName = '',
    double count = 1,
    double cost = 0,
    double gst = 0,
  }) : count = TextEditingController(text: formatQty(count)),
       cost = TextEditingController(text: cost == 0 ? '' : formatQty(cost)),
       gst = TextEditingController(text: formatQty(gst));

  Product? product;
  ProductVariant? variant;
  final String readName;
  final TextEditingController count;
  final TextEditingController cost;
  final TextEditingController gst;

  double get countV => double.tryParse(count.text.trim()) ?? 0;
  double get costV => double.tryParse(cost.text.trim()) ?? 0;
  double get gstV => double.tryParse(gst.text.trim()) ?? 0;
  double get total => countV * costV * (1 + gstV / 100);

  void dispose() {
    count.dispose();
    cost.dispose();
    gst.dispose();
  }
}

/// Type in a supplier bill, or check one read from a photo, then save it.
class PurchaseFormPage extends StatefulWidget {
  const PurchaseFormPage({
    super.key,
    required this.state,
    this.draft,
    this.imagePath,
  });

  final AppState state;
  final InvoiceDraft? draft;
  final String? imagePath;

  @override
  State<PurchaseFormPage> createState() => _PurchaseFormPageState();
}

class _PurchaseFormPageState extends State<PurchaseFormPage> {
  AppState get s => widget.state;
  PurchaseRepository get buy => s.purchases;

  Supplier? _supplier;
  final _invoiceNo = TextEditingController();
  final _paid = TextEditingController(text: '0');
  DateTime _date = DateTime.now();
  final List<_LineEdit> _lines = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d == null) {
      _lines.add(_LineEdit());
      return;
    }
    _supplier = buy.findSupplier(gstin: d.gstin, name: d.supplierName);
    _invoiceNo.text = d.invoiceNo;
    if (d.date != null) _date = d.date!;
    for (final l in d.lines) {
      final guess = s.guessProduct(l.name);
      _lines.add(
        _LineEdit(
          product: guess?.$1,
          variant: guess?.$2,
          readName: l.name,
          count: l.quantity == 0 ? 1 : l.quantity,
          cost: l.rate,
          gst: l.gstPercent,
        ),
      );
    }
    if (_lines.isEmpty) _lines.add(_LineEdit());
  }

  @override
  void dispose() {
    _invoiceNo.dispose();
    _paid.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _total => _lines.fold<double>(0, (t, l) => t + l.total);

  Future<void> _pickSupplier() async {
    final d = widget.draft;
    final sup = await showSupplierDialog(
      context,
      buy,
      null,
      d?.supplierName ?? '',
      d?.gstin ?? '',
    );
    if (sup != null) setState(() => _supplier = sup);
  }

  void _save() {
    final sup = _supplier;
    if (sup == null) {
      setState(() => _error = 'Pick the supplier first.');
      return;
    }
    final lines = <PurchaseLine>[];
    for (final l in _lines) {
      if (l.product == null && l.countV == 0) continue;
      if (l.product == null) {
        setState(() => _error = 'Pick a product for every line.');
        return;
      }
      if (l.countV <= 0) {
        setState(() => _error = 'Quantity must be more than 0.');
        return;
      }
      lines.add(
        PurchaseLine(
          product: l.product!,
          variant: l.variant,
          count: l.countV,
          unitCost: l.costV,
          gstPercent: l.gstV,
        ),
      );
    }
    if (lines.isEmpty) {
      setState(() => _error = 'Add at least one item.');
      return;
    }
    buy.savePurchase(
      supplier: sup,
      lines: lines,
      invoiceDate: _date,
      invoiceNo: _invoiceNo.text,
      paid: double.tryParse(_paid.text.trim()) ?? 0,
      source: widget.draft == null ? 'MANUAL' : 'OCR',
      imagePath: widget.imagePath,
      userId: s.user?.id,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = buy.suppliers();
    final products = s.activeProducts;
    final draft = widget.draft;
    final diff = draft == null ? 0.0 : (draft.total - _total);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          draft == null ? 'New purchase' : 'Check the bill that was read',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (draft != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: KadaiColors.warnTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Please check every line against the paper bill. '
                  'Lines in orange need a product picked.',
                  style: TextStyle(color: KadaiColors.warnInk, fontSize: 15),
                ),
              ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _supplier?.id,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: [
                      for (final x in suppliers)
                        DropdownMenuItem(value: x.id, child: Text(x.name)),
                    ],
                    onChanged: (id) => setState(
                      () => _supplier = suppliers.firstWhere((x) => x.id == id),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _pickSupplier,
                  icon: const Icon(Icons.add),
                  label: Text(
                    draft != null &&
                            _supplier == null &&
                            draft.supplierName.isNotEmpty
                        ? 'Add "${draft.supplierName}"'
                        : 'New supplier',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _invoiceNo,
                    decoration: const InputDecoration(labelText: 'Bill no'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(_day(_date)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(flex: 5, child: Text('Product')),
                  SizedBox(width: 8),
                  Expanded(flex: 3, child: Text('Size')),
                  SizedBox(width: 8),
                  Expanded(flex: 2, child: Text('Quantity')),
                  SizedBox(width: 8),
                  Expanded(flex: 2, child: Text('Cost each ₹')),
                  SizedBox(width: 8),
                  Expanded(flex: 1, child: Text('GST %')),
                  SizedBox(width: 8),
                  Expanded(flex: 2, child: Text('Amount')),
                  SizedBox(width: 48),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Card(
                child: ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final l = _lines[i];
                    final missing = l.product == null;
                    return Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: missing && l.readName.isNotEmpty
                            ? KadaiColors.warnTint
                            : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (l.readName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'On the bill: ${l.readName}',
                                style: const TextStyle(
                                  color: KadaiColors.quiet,
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: l.product?.id,
                                  hint: const Text('Pick product'),
                                  items: [
                                    for (final p in products)
                                      DropdownMenuItem(
                                        value: p.id,
                                        child: Text(
                                          '${p.nameEn} · ${p.nameTa}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (id) => setState(() {
                                    l.product = products.firstWhere(
                                      (p) => p.id == id,
                                    );
                                    l.variant = l.product!.defaultVariant;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('v${l.product?.id}'),
                                  isExpanded: true,
                                  initialValue: l.variant?.id ?? '',
                                  items: [
                                    if (l.product != null)
                                      DropdownMenuItem(
                                        value: '',
                                        child: Text(
                                          '1 ${l.product!.stockUnit.code} loose',
                                        ),
                                      ),
                                    for (final v
                                        in l.product?.variants ??
                                            const <ProductVariant>[])
                                      DropdownMenuItem(
                                        value: v.id,
                                        child: Text(v.label),
                                      ),
                                  ],
                                  onChanged: (id) => setState(
                                    () => l.variant = id == ''
                                        ? null
                                        : l.product!.variants.firstWhere(
                                            (v) => v.id == id,
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(flex: 2, child: _num(l.count)),
                              const SizedBox(width: 8),
                              Expanded(flex: 2, child: _num(l.cost)),
                              const SizedBox(width: 8),
                              Expanded(flex: 1, child: _num(l.gst)),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  rupees(l.total),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove line',
                                onPressed: () => setState(() {
                                  _lines.removeAt(i).dispose();
                                }),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _lines.add(_LineEdit())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add line'),
                ),
                const SizedBox(width: 16),
                if (draft != null && diff.abs() >= 1)
                  Expanded(
                    child: Text(
                      'Bill total says ${rupees(draft.total)}. '
                      'Lines add up to ${rupees(_total)}.',
                      style: const TextStyle(
                        color: KadaiColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                Text(
                  'Total ${rupees(_total)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _paid,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Paid now ₹'),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Save purchase'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: KadaiColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _num(TextEditingController c) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => setState(() {}),
  );
}
