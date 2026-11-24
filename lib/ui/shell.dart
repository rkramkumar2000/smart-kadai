import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import 'billing_screen.dart';
import 'products_screen.dart';
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

  static const _items = [
    ('Billing', 'பில்', Icons.point_of_sale_outlined),
    ('Products', 'பொருட்கள்', Icons.inventory_2_outlined),
  ];

  @override
  Widget build(BuildContext context) {
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
                for (var i = 0; i < _items.length; i++)
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
                                _items[i].$3,
                                color: i == _tab
                                    ? KadaiColors.greenDark
                                    : KadaiColors.quiet,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TwoLang(
                                  _items[i].$1,
                                  _items[i].$2,
                                  size: 16,
                                  color: i == _tab
                                      ? KadaiColors.greenDark
                                      : null,
                                ),
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
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                BillingScreen(state: widget.state),
                ProductsScreen(state: widget.state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
