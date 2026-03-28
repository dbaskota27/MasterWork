import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // Date range
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  late Future<Map<String, dynamic>> _future;

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);
  final _dateFmt = DateFormat('MMM d, y');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(
      () => _future = DatabaseService.getSummary(from: _from, to: _to));

  Future<void> _pickRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (result != null) {
      setState(() {
        _from = result.start;
        _to = result.end;
      });
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range picker
          Card(
            child: ListTile(
              leading: const Icon(Icons.date_range),
              title: Text(
                  '${_dateFmt.format(_from)}  →  ${_dateFmt.format(_to)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickRange,
            ),
          ),
          const SizedBox(height: 12),

          FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final data = snap.data!;
              final revenue = data['total_revenue'] as double;
              final discount = data['total_discount'] as double;
              final txns = data['total_transactions'] as int;
              final invoices = data['invoices'] as List<Invoice>;
              final productCounts =
                  data['product_counts'] as Map<String, int>;

              // Sort products by count
              final topProducts = productCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary cards
                  Row(children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Revenue',
                        value: _money.format(revenue),
                        icon: Icons.attach_money,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        label: 'Transactions',
                        value: '$txns',
                        icon: Icons.receipt_long,
                        color: Colors.blue,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Total Discounts',
                        value: _money.format(discount),
                        icon: Icons.discount_outlined,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        label: 'Avg Sale',
                        value: txns > 0
                            ? _money.format(revenue / txns)
                            : _money.format(0),
                        icon: Icons.trending_up,
                        color: Colors.purple,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // Top products
                  if (topProducts.isNotEmpty) ...[
                    Text('Top Products',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: topProducts.take(10).map((e) {
                          final rank =
                              topProducts.indexOf(e) + 1;
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              child: Text('$rank',
                                  style:
                                      const TextStyle(fontSize: 12)),
                            ),
                            title: Text(e.key),
                            trailing: Text('${e.value} sold',
                                style: const TextStyle(
                                    color: Colors.grey)),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Payment breakdown
                  if (invoices.isNotEmpty) ...[
                    Text('Payment Methods',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _paymentBreakdown(invoices),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _paymentBreakdown(List<Invoice> invoices) {
    double cashTotal = 0, qpTotal = 0;
    int cashCount = 0, qpCount = 0;

    for (final inv in invoices) {
      if (inv.paymentType == 'cash') {
        cashTotal += inv.customerPays;
        cashCount++;
      } else {
        qpTotal += inv.customerPays;
        qpCount++;
      }
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Cash'),
            Text('$cashCount txns  ·  ${_money.format(cashTotal)}'),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('QuickPay'),
            Text('$qpCount txns  ·  ${_money.format(qpTotal)}'),
          ],
        ),
      ],
    );
  }
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
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
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
