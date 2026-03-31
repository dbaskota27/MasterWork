import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);
  final _dateFmt = DateFormat('MMM d, h:mm a');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _future = _loadData());
  }

  Future<_DashboardData> _loadData() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final summary = await DatabaseService.getSummary(
      from: todayStart,
      to: todayEnd,
    );
    final lowStock = await DatabaseService.getLowStockProducts();
    final allInvoices = await DatabaseService.getInvoices();
    final recent = allInvoices.take(5).toList();

    return _DashboardData(
      revenue: summary['total_revenue'] as double,
      transactions: summary['total_transactions'] as int,
      profit: summary['total_profit'] as double,
      lowStockProducts: lowStock,
      recentInvoices: recent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final data = snap.data!;

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text("Today's Summary",
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),

              // Stat cards
              Row(children: [
                Expanded(
                  child: _StatCard(
                    label: 'Revenue',
                    value: _money.format(data.revenue),
                    icon: Icons.attach_money,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Transactions',
                    value: '${data.transactions}',
                    icon: Icons.receipt_long,
                    color: Colors.blue,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _StatCard(
                    label: 'Profit',
                    value: _money.format(data.profit),
                    icon: Icons.trending_up,
                    color: data.profit >= 0 ? Colors.teal : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ]),
              const SizedBox(height: 20),

              // Low stock alerts
              if (data.lowStockProducts.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 6),
                    Text('Low Stock Alerts (${data.lowStockProducts.length})',
                        style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: data.lowStockProducts.map((p) {
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: p.stock == 0
                              ? Colors.red.shade100
                              : Colors.orange.shade100,
                          child: Text('${p.stock}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: p.stock == 0
                                    ? Colors.red.shade800
                                    : Colors.orange.shade800,
                              )),
                        ),
                        title: Text(p.name),
                        subtitle: Text(
                            'Threshold: ${p.lowStockThreshold}  ·  ${p.category ?? ""}'),
                        trailing: p.stock == 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('OUT',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade700)),
                              )
                            : null,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Recent invoices
              Text('Recent Invoices', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (data.recentInvoices.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('No invoices yet.')),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: data.recentInvoices.map((inv) {
                      final itemsSummary = inv.items
                          .map((e) => '${e.productName} x${e.qty}')
                          .join(', ');
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          child: Text('#${inv.id}',
                              style: const TextStyle(fontSize: 10)),
                        ),
                        title: Text(
                          itemsSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_dateFmt.format(inv.createdAt),
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text(_money.format(inv.customerPays),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardData {
  final double revenue;
  final int transactions;
  final double profit;
  final List<Product> lowStockProducts;
  final List<Invoice> recentInvoices;

  const _DashboardData({
    required this.revenue,
    required this.transactions,
    required this.profit,
    required this.lowStockProducts,
    required this.recentInvoices,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  Text(value,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
