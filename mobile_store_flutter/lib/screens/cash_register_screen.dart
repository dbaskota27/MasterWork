import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/cash_register.dart';
import '../services/database_service.dart';

class CashRegisterScreen extends StatefulWidget {
  const CashRegisterScreen({super.key});

  @override
  State<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends State<CashRegisterScreen> {
  CashRegister? _register;
  List<CashAdjustment> _adjustments = [];
  bool _loading = true;

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);
  final _timeFmt = DateFormat('h:mm a');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final reg = await DatabaseService.getOpenRegister();
      List<CashAdjustment> adj = [];
      if (reg != null) {
        adj = await DatabaseService.getCashAdjustments(reg.id);
      }
      setState(() {
        _register = reg;
        _adjustments = adj;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Register')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _register == null
              ? _buildNoRegister(theme)
              : _buildOpenRegister(theme),
    );
  }

  Widget _buildNoRegister(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.point_of_sale,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No register is open.',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Open a register to start tracking cash flow.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text('Open Register'),
              onPressed: _showOpenDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenRegister(ThemeData theme) {
    final reg = _register!;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_open, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text('Register Open',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                              fontSize: 16)),
                      const Spacer(),
                      if (reg.workerName != null)
                        Text(reg.workerName!,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  if (reg.openedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          'Opened at ${_timeFmt.format(reg.openedAt!)}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Balance summary
          Row(children: [
            Expanded(
              child: _InfoCard(
                label: 'Opening',
                value: _money.format(reg.openingBalance),
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InfoCard(
                label: 'Cash In',
                value: _money.format(reg.cashIn),
                color: Colors.green,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _InfoCard(
                label: 'Cash Out',
                value: _money.format(reg.cashOut),
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InfoCard(
                label: 'Expected',
                value: _money.format(reg.expectedBalance),
                color: Colors.purple,
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Action buttons
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                label: const Text('Cash In'),
                onPressed: () => _showAdjustmentDialog('in'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                label: const Text('Cash Out'),
                onPressed: () => _showAdjustmentDialog('out'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.lock_outline),
              label: const Text('Close Register'),
              onPressed: _showCloseDialog,
            ),
          ),
          const SizedBox(height: 20),

          // Adjustments log
          if (_adjustments.isNotEmpty) ...[
            Text('Adjustments', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: _adjustments.map((adj) {
                  final isIn = adj.type == 'in';
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isIn ? Icons.add_circle : Icons.remove_circle,
                      color: isIn ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    title: Text(
                      '${isIn ? "+" : "-"}${_money.format(adj.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isIn ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    subtitle: Text(adj.reason ?? 'No reason'),
                    trailing: Text(
                      adj.createdAt != null
                          ? _timeFmt.format(adj.createdAt!)
                          : '',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showOpenDialog() {
    final ctrl = TextEditingController(text: '0.00');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open Register'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Opening Balance'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(ctrl.text) ?? 0;
              Navigator.pop(ctx);
              await DatabaseService.openRegister(amount);
              _reload();
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  void _showCloseDialog() {
    final ctrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final reg = _register!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Register'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Expected balance: ${_money.format(reg.expectedBalance)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration:
                  const InputDecoration(labelText: 'Actual Closing Balance'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(ctrl.text) ?? 0;
              Navigator.pop(ctx);
              await DatabaseService.closeRegister(reg.id, amount,
                  notes: notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim());
              _reload();
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAdjustmentDialog(String type) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final isIn = type == 'in';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isIn ? 'Cash In' : 'Cash Out'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;
              Navigator.pop(ctx);
              await DatabaseService.addCashAdjustment(
                registerId: _register!.id,
                type: type,
                amount: amount,
                reason: reasonCtrl.text.trim().isEmpty
                    ? null
                    : reasonCtrl.text.trim(),
              );
              _reload();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
