import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../config.dart';
import 'login_screen.dart';
import 'inventory_screen.dart';
import 'new_sale_screen.dart';
import 'invoices_screen.dart';
import 'customers_screen.dart';
import 'reports_screen.dart';
import 'barcode_scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  late final List<_NavItem> _items = [
    _NavItem(
      label: 'Scanner',
      icon: Icons.qr_code_scanner,
      screen: const BarcodeScannerScreen(),
    ),
    _NavItem(
      label: 'New Sale',
      icon: Icons.point_of_sale,
      screen: const NewSaleScreen(),
    ),
    _NavItem(
      label: 'Inventory',
      icon: Icons.inventory_2_outlined,
      screen: const InventoryScreen(),
    ),
    _NavItem(
      label: 'Invoices',
      icon: Icons.receipt_long,
      screen: const InvoicesScreen(),
    ),
    _NavItem(
      label: 'Customers',
      icon: Icons.people_outline,
      screen: const CustomersScreen(),
    ),
    if (AuthService.isManager)
      _NavItem(
        label: 'Reports',
        icon: Icons.bar_chart,
        screen: const ReportsScreen(),
      ),
  ];

  void _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppConfig.storeName),
        actions: [
          // Role badge
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AuthService.isManager
                  ? Colors.blue.shade100
                  : Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${AuthService.username} (${AuthService.role})',
              style: TextStyle(
                fontSize: 12,
                color: AuthService.isManager
                    ? Colors.blue.shade800
                    : Colors.green.shade800,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
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
  const _NavItem(
      {required this.label, required this.icon, required this.screen});
}
