import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../core/units.dart';
import '../customers/customers.dart';
import 'theme.dart';
import 'whatsapp.dart';

/// The credit book (kadan): who owes the shop, payments received, and
/// reminders on WhatsApp.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.state});

  final AppState state;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _query = '';
  Customer? _open;

  AppState get s => widget.state;
  CustomerRepository get repo => s.customers;

  Future<void> _receive(Customer c) async {
    final amt = TextEditingController(text: formatQty(c.balance));
    var mode = 'CASH';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Money from ${c.name}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Owes ${rupees(c.balance)}',
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
                    for (final m in const ['CASH', 'UPI'])
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final v = double.tryParse(amt.text.trim());
    amt.dispose();
    if (ok != true || v == null || v <= 0) return;
    repo.receivePayment(c.id, v, mode, userId: s.user?.id);
    setState(() => _open = repo.byId(c.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Received ${rupees(v)} from ${c.name}')),
    );
  }

  void _remind(Customer c) => sendOnWhatsApp(
    context,
    CustomerRepository.reminderText(c, s.shopName, s.repo.setting('upi_id')),
    phone: c.phone,
  );

  Future<void> _edit([Customer? c]) async {
    final saved = await showCustomerDialog(context, s, c);
    if (saved != null) setState(() => _open = saved);
  }

  @override
  Widget build(BuildContext context) {
    final list = repo.customers(query: _query);
    final due = repo.totalDue();
    final open = _open;
    final narrow = isNarrow(context);
    final listCard = Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Name or phone',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'No customers yet. Credit bills add them here.',
                      style: TextStyle(color: KadaiColors.quiet),
                    ),
                  )
                : ListView(
                    children: [
                      for (final c in list)
                        ListTile(
                          selected: open?.id == c.id,
                          selectedTileColor: KadaiColors.greenTint,
                          onTap: () => setState(() => _open = c),
                          title: Text(
                            c.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(c.phone),
                          trailing: Text(
                            rupees(c.balance),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: c.balance > 0
                                  ? KadaiColors.danger
                                  : KadaiColors.quiet,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
    final accountCard = Card(
      child: open == null
          ? const Center(
              child: Text(
                'Pick a customer to see their account',
                style: TextStyle(color: KadaiColors.quiet),
              ),
            )
          : _account(open),
    );
    return Padding(
      padding: screenPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: const TwoLang('Credit book', 'கடன் புத்தகம்', size: 24),
            actions: [
              Text(
                'Customers owe ${rupees(due)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KadaiColors.danger,
                ),
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add customer'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: !narrow
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: listCard),
                      const SizedBox(width: 14),
                      Expanded(flex: 5, child: accountCard),
                    ],
                  )
                : open == null
                ? listCard
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _open = null),
                          icon: const Icon(Icons.arrow_back),
                          label: Text(
                            t('All customers', 'எல்லா வாடிக்கையாளர்'),
                          ),
                        ),
                      ),
                      Expanded(child: accountCard),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _account(Customer c) {
    final rows = repo.ledger(c.id);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (c.phone.isNotEmpty)
                      Text(
                        c.phone,
                        style: const TextStyle(color: KadaiColors.quiet),
                      ),
                  ],
                ),
              ),
              TextButton(onPressed: () => _edit(c), child: const Text('Edit')),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Owes ${rupees(c.balance)}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: c.balance > 0 ? KadaiColors.danger : KadaiColors.green,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: c.balance > 0 ? () => _receive(c) : null,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Money received'),
              ),
              OutlinedButton.icon(
                onPressed: c.balance > 0 ? () => _remind(c) : null,
                icon: const Icon(Icons.send),
                label: const Text('Remind on WhatsApp'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'No credit bills or payments yet',
                      style: TextStyle(color: KadaiColors.quiet),
                    ),
                  )
                : ListView(
                    children: [
                      for (final r in rows)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            r.isPayment ? Icons.south_west : Icons.north_east,
                            color: r.isPayment
                                ? KadaiColors.green
                                : KadaiColors.danger,
                          ),
                          title: Text(r.label),
                          subtitle: Text(_when(r.at)),
                          trailing: Text(
                            '${r.isPayment ? '−' : '+'} ${rupees(r.amount)}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: r.isPayment
                                  ? KadaiColors.green
                                  : KadaiColors.danger,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _when(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Add or edit a customer. Returns the saved customer.
Future<Customer?> showCustomerDialog(
  BuildContext context,
  AppState s, [
  Customer? c,
  String name = '',
]) async {
  final n = TextEditingController(text: c?.name ?? name);
  final ph = TextEditingController(text: c?.phone ?? '');
  final a = TextEditingController(text: c?.address ?? '');
  var wholesale = c?.isWholesale ?? false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(c == null ? 'Add customer' : 'Edit customer'),
        content: SizedBox(
          width: 400,
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
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number (for WhatsApp)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: a,
                decoration: const InputDecoration(labelText: 'Street or area'),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tt('Wholesale customer', 'மொத்த வியாபாரி')),
                subtitle: Text(
                  t(
                    'Their bills use wholesale prices.',
                    'இவருக்கு மொத்த விலை.',
                  ),
                ),
                value: wholesale,
                onChanged: (v) => setLocal(() => wholesale = v),
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
    ),
  );
  Customer? saved;
  if (ok == true) {
    saved = s.customers.save(
      Customer(
        id: c?.id ?? s.repo.newId(),
        name: n.text,
        phone: ph.text,
        address: a.text,
        balance: c?.balance ?? 0,
        isWholesale: wholesale,
      ),
    );
  }
  for (final x in [n, ph, a]) {
    x.dispose();
  }
  return saved;
}

/// Pick the customer for a bill: search by name or phone, or add a new one.
Future<Customer?> pickCustomer(BuildContext context, AppState s) =>
    showDialog<Customer>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setLocal) {
            final list = s.customers.customers(query: query);
            return AlertDialog(
              title: const Text('Customer · வாடிக்கையாளர்'),
              content: SizedBox(
                width: 460,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(fontSize: 17),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Name or phone',
                      ),
                      onChanged: (v) => setLocal(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final c in list)
                            ListTile(
                              title: Text(c.name),
                              subtitle: Text(c.phone),
                              trailing: c.balance > 0
                                  ? Text(
                                      'Owes ${rupees(c.balance)}',
                                      style: const TextStyle(
                                        color: KadaiColors.danger,
                                      ),
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, c),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final c = await showCustomerDialog(context, s, null, query);
                    if (c != null && context.mounted) {
                      Navigator.pop(context, c);
                    }
                  },
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('New customer'),
                ),
              ],
            );
          },
        );
      },
    );
