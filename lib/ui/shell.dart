import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import 'billing_screen.dart';
import 'customers_screen.dart';
import 'phones_section.dart';
import 'products_screen.dart';
import 'purchases_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';
import 'theme.dart';

/// Left menu plus the open screen, as in the desktop designs.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  /// Menu items: English, Tamil, icon, owner only.
  static const _all = [
    ('Billing', 'பில்', Icons.point_of_sale_outlined, false),
    ('Credit book', 'கடன்', Icons.menu_book_outlined, false),
    ('Products', 'பொருட்கள்', Icons.inventory_2_outlined, false),
    ('Stock', 'இருப்பு', Icons.warehouse_outlined, false),
    ('Purchases', 'கொள்முதல்', Icons.local_shipping_outlined, true),
    ('Reports', 'அறிக்கை', Icons.bar_chart_outlined, true),
    ('Settings', 'அமைப்பு', Icons.settings_outlined, true),
  ];

  /// A phone billing through the PC leaves stock, purchases and reports
  /// to the PC.
  static const _pcOnly = {'Stock', 'Purchases', 'Reports'};

  List<(String, String, IconData, bool)> get _items => [
    for (final i in _all)
      if ((!i.$4 || (widget.state.user?.isOwner ?? false)) &&
          !(widget.state.isLinkedPhone && _pcOnly.contains(i.$1)))
        i,
  ];

  Widget _screen(String name) => switch (name) {
    'Billing' => BillingScreen(state: widget.state),
    'Credit book' => CustomersScreen(state: widget.state),
    'Products' => ProductsScreen(state: widget.state),
    'Stock' => StockScreen(state: widget.state),
    'Purchases' => PurchasesScreen(state: widget.state),
    'Reports' => ReportsScreen(state: widget.state),
    _ => SettingsScreen(state: widget.state),
  };

  /// Below this width (a phone) the menu moves into a drawer.
  static const phoneWidth = 720.0;

  void _open(int i, {bool closeDrawer = false}) {
    setState(() => _tab = i);
    if (closeDrawer) Navigator.of(context).pop();
  }

  Widget _logo() => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: KadaiColors.green,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'SK',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Text(
          'Smart Kadai',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  Widget _stockBadge() => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final n = widget.state.lowStock.length;
      if (n == 0) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: KadaiColors.warn,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$n',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    },
  );

  List<Widget> _menuItems(
    List<(String, String, IconData, bool)> items, {
    bool phone = false,
  }) => [
    for (var i = 0; i < items.length; i++)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: i == _tab ? KadaiColors.greenTint : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _open(i, closeDrawer: phone),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: phone
                    ? 14
                    : _short
                    ? 5
                    : 10,
              ),
              child: Row(
                children: [
                  Icon(
                    items[i].$3,
                    color: i == _tab
                        ? KadaiColors.greenDark
                        : KadaiColors.quiet,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TwoLang(
                      items[i].$1,
                      items[i].$2,
                      size: phone ? 17 : 16,
                      color: i == _tab ? KadaiColors.greenDark : null,
                    ),
                  ),
                  if (items[i].$1 == 'Stock') _stockBadge(),
                ],
              ),
            ),
          ),
        ),
      ),
  ];

  /// A laptop screen (1366 × 768 less the taskbar): the menu is made
  /// tighter so every item shows without scrolling.
  bool get _short => MediaQuery.sizeOf(context).height < 860;

  Widget _today() => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => _short
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: KadaiColors.ground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${t('Today', 'இன்று')} ${rupees(widget.state.today.total)} · '
              '${widget.state.today.bills} ${t('bills', 'பில்')}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        : Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KadaiColors.ground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bi('Today · இன்று'),
                  style: TextStyle(fontSize: 13, color: KadaiColors.quiet),
                ),
                Text(
                  rupees(widget.state.today.total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${widget.state.today.bills} ${t('bills', 'பில்')}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: KadaiColors.quiet,
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _user() => Row(
    children: [
      const Icon(Icons.person_outline, color: KadaiColors.quiet),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          widget.state.user?.name ?? '',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      IconButton(
        tooltip: bi('Lock · பூட்டு'),
        icon: const Icon(Icons.lock_outline),
        onPressed: widget.state.lock,
      ),
    ],
  );

  /// The whole menu. Items scroll when the text is large.
  Widget _menu(
    List<(String, String, IconData, bool)> items, {
    bool phone = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _logo(),
      SizedBox(height: _short && !phone ? 10 : 20),
      Expanded(
        child: ListView(
          padding: EdgeInsets.zero,
          children: _menuItems(items, phone: phone),
        ),
      ),
      const SizedBox(height: 8),
      if (widget.state.isLinkedPhone) ...[
        ListenableBuilder(
          listenable: widget.state,
          builder: (_, _) => PcStatus(state: widget.state),
        ),
        const SizedBox(height: 8),
      ],
      _today(),
      const SizedBox(height: 8),
      ViewControls(state: widget.state),
      const SizedBox(height: 4),
      _user(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final tab = _tab.clamp(0, items.length - 1);
    final body = IndexedStack(
      index: tab,
      children: [for (final i in items) _screen(i.$1)],
    );
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    if (phone) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          titleSpacing: 0,
          title: TwoLang(items[tab].$1, items[tab].$2, size: 18),
          actions: [
            if (widget.state.isLinkedPhone)
              ListenableBuilder(
                listenable: widget.state,
                builder: (_, _) {
                  final l = widget.state.link!;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: l.online
                          ? t('PC connected', 'கணினி இணைப்பில்')
                          : t('PC not reachable', 'கணினி கிடைக்கவில்லை'),
                      child: Badge(
                        isLabelVisible: l.waitingBills > 0,
                        label: Text('${l.waitingBills}'),
                        child: Icon(
                          l.online
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                          color: l.online
                              ? KadaiColors.green
                              : KadaiColors.warn,
                        ),
                      ),
                    ),
                  );
                },
              ),
            IconButton(
              tooltip: bi('Lock · பூட்டு'),
              icon: const Icon(Icons.lock_outline),
              onPressed: widget.state.lock,
            ),
          ],
        ),
        drawer: Drawer(
          backgroundColor: Colors.white,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
              child: _menu(items, phone: true),
            ),
          ),
        ),
        body: SafeArea(top: false, child: body),
      );
    }
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 210,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE1E4DC))),
            ),
            padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
            child: _menu(items),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
