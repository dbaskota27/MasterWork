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

  late final List<_NavItem> _items = [
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

  void _switchUser() {
    WorkerService.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WorkerLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_items[_selectedIndex].label),
        actions: [
          // Active worker badge
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
      body: _items[_selectedIndex].screen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: _items
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  label: item.label,
                ))
            .toList(),
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
