import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import 'billing_screen.dart';
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
    ('Products', 'பொருட்கள்', Icons.inventory_2_outlined, false),
    ('Stock', 'இருப்பு', Icons.warehouse_outlined, false),
    ('Purchases', 'கொள்முதல்', Icons.local_shipping_outlined, true),
    ('Reports', 'அறிக்கை', Icons.bar_chart_outlined, true),
    ('Settings', 'அமைப்பு', Icons.settings_outlined, true),
  ];

  List<(String, String, IconData, bool)> get _items => [
    for (final i in _all)
      if (!i.$4 || (widget.state.user?.isOwner ?? false)) i,
  ];

  Widget _screen(String name) => switch (name) {
    'Billing' => BillingScreen(state: widget.state),
    'Products' => ProductsScreen(state: widget.state),
    'Stock' => StockScreen(state: widget.state),
    'Purchases' => PurchasesScreen(state: widget.state),
    'Reports' => ReportsScreen(state: widget.state),
    _ => SettingsScreen(state: widget.state),
  };

  @override
  Widget build(BuildContext context) {
    final items = _items;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
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
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: i == _tab
                          ? KadaiColors.greenTint
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _tab = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
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
                                  size: 16,
                                  color: i == _tab
                                      ? KadaiColors.greenDark
                                      : null,
                                ),
                              ),
                              if (items[i].$1 == 'Stock')
                                ListenableBuilder(
                                  listenable: widget.state,
                                  builder: (context, _) {
                                    final n = widget.state.lowStock.length;
                                    if (n == 0) return const SizedBox.shrink();
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
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
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                ListenableBuilder(
                  listenable: widget.state,
                  builder: (context, _) => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KadaiColors.ground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Today · இன்று',
                          style: TextStyle(
                            fontSize: 13,
                            color: KadaiColors.quiet,
                          ),
                        ),
                        Text(
                          rupees(widget.state.today.total),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${widget.state.today.bills} bills',
                          style: const TextStyle(
                            fontSize: 13,
                            color: KadaiColors.quiet,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
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
                      tooltip: 'Lock · பூட்டு',
                      icon: const Icon(Icons.lock_outline),
                      onPressed: widget.state.lock,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab.clamp(0, items.length - 1),
              children: [for (final i in items) _screen(i.$1)],
            ),
          ),
        ],
      ),
    );
  }
}
