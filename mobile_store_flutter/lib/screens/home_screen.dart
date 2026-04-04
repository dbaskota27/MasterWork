import 'package:flutter/material.dart';
import '../services/worker_service.dart';
import 'dashboard_screen.dart';
import 'new_sale_screen.dart';
import 'barcode_scanner_screen.dart';
import 'inventory_screen.dart';
import 'invoices_screen.dart';
import 'customers_screen.dart';
import 'expenses_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'worker_login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  static const int _maxBottomItems = 6;

  late final List<_NavItem> _allItems = [
    if (WorkerService.hasPermission('dashboard'))
      _NavItem(label: 'Home',      icon: Icons.dashboard_outlined,    screen: const DashboardScreen()),
    if (WorkerService.hasPermission('sales'))
      _NavItem(label: 'New Sale',  icon: Icons.point_of_sale,         screen: const NewSaleScreen()),
    if (WorkerService.hasPermission('sales'))
      _NavItem(label: 'Scanner',   icon: Icons.qr_code_scanner,       screen: const BarcodeScannerScreen()),
    if (WorkerService.hasPermission('inventory_view'))
      _NavItem(label: 'Inventory', icon: Icons.inventory_2_outlined,  screen: const InventoryScreen()),
    if (WorkerService.hasPermission('invoices_view'))
      _NavItem(label: 'Invoices',  icon: Icons.receipt_long,          screen: const InvoicesScreen()),
    if (WorkerService.hasPermission('customers_view'))
      _NavItem(label: 'Customers', icon: Icons.people_outline,        screen: const CustomersScreen()),
    if (WorkerService.hasPermission('expenses_view'))
      _NavItem(label: 'Expenses', icon: Icons.money_off_outlined,   screen: const ExpensesScreen()),
    if (WorkerService.hasPermission('reports'))
      _NavItem(label: 'Reports',  icon: Icons.bar_chart,            screen: const ReportsScreen()),
    _NavItem(label: 'Settings',  icon: Icons.settings_outlined,     screen: const SettingsScreen()),
  ];

  bool get _needsMoreTab => _allItems.length > _maxBottomItems + 1;

  List<_NavItem> get _bottomItems =>
      _needsMoreTab ? _allItems.sublist(0, _maxBottomItems) : _allItems;

  List<_NavItem> get _overflowItems =>
      _needsMoreTab ? _allItems.sublist(_maxBottomItems) : [];

  int get _effectiveIndex {
    if (!_needsMoreTab) return _selectedIndex;
    if (_selectedIndex < _maxBottomItems) return _selectedIndex;
    return _maxBottomItems; // "More" tab
  }

  Widget get _currentScreen {
    if (_selectedIndex < _allItems.length) return _allItems[_selectedIndex].screen;
    return const SizedBox.shrink();
  }

  String get _currentTitle {
    if (_selectedIndex < _allItems.length) return _allItems[_selectedIndex].label;
    return 'More';
  }

  void _switchUser() {
    WorkerService.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WorkerLoginScreen()),
    );
  }

  Widget _buildMoreGrid() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: _overflowItems.map((item) {
          final globalIndex = _allItems.indexOf(item);
          final isSelected = _selectedIndex == globalIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedIndex = globalIndex),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: 32,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(item.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showMoreScreen = _needsMoreTab && _selectedIndex >= _maxBottomItems;

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTitle),
        actions: [
          GestureDetector(
            onTap: _switchUser,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: WorkerService.isManager
                    ? Colors.blue.shade100
                    : Colors.green.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${WorkerService.workerName ?? "?"} · ${WorkerService.workerRole ?? ""}',
                    style: TextStyle(
                      fontSize: 11,
                      color: WorkerService.isManager
                          ? Colors.blue.shade800
                          : Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.swap_horiz, size: 14,
                      color: WorkerService.isManager
                          ? Colors.blue.shade800
                          : Colors.green.shade800),
                ],
              ),
            ),
          ),
        ],
      ),
      body: showMoreScreen ? _buildMoreGrid() : _currentScreen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _effectiveIndex,
        onDestinationSelected: (i) {
          if (_needsMoreTab && i == _maxBottomItems) {
            // Tapped "More" — show the grid but keep _selectedIndex
            // so we can highlight the active overflow item
            setState(() {
              // If already viewing an overflow item, stay there;
              // otherwise jump to the first overflow item index to show grid
              if (_selectedIndex < _maxBottomItems) {
                _selectedIndex = _maxBottomItems;
              }
            });
          } else {
            setState(() => _selectedIndex = i);
          }
        },
        destinations: [
          ..._bottomItems.map((item) => NavigationDestination(
                icon: Icon(item.icon),
                label: item.label,
              )),
          if (_needsMoreTab)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final Widget screen;
  const _NavItem({required this.label, required this.icon, required this.screen});
}
