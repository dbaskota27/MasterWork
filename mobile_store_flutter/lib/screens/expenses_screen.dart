import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/expense.dart';
import '../services/database_service.dart';
import '../services/worker_service.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<List<Expense>> _future;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);
  final _dateFmt = DateFormat('MMM d, y');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() =>
        _future = DatabaseService.getExpenses(from: _from, to: _to));
  }

  Future<void> _pickRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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
    return Scaffold(
      body: Column(
        children: [
          // Date range
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(
                    '${_dateFmt.format(_from)}  ->  ${_dateFmt.format(_to)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickRange,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Expense>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final expenses = snap.data ?? [];
                if (expenses.isEmpty) {
                  return const Center(child: Text('No expenses found.'));
                }

                final total = expenses.fold<double>(0, (s, e) => s + e.amount);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total: ${_money.format(total)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('${expenses.length} entries',
                              style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: expenses.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (ctx, i) {
                            final e = expenses[i];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _categoryColor(e.category)
                                      .withOpacity(0.15),
                                  child: Icon(_categoryIcon(e.category),
                                      color: _categoryColor(e.category),
                                      size: 20),
                                ),
                                title: Text(e.description ?? e.category),
                                subtitle: Text(
                                    '${_capitalize(e.category)}  ·  ${_dateFmt.format(e.date)}'
                                    '${e.workerName != null ? "  ·  ${e.workerName}" : ""}'),
                                trailing: Text(
                                  _money.format(e.amount),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700),
                                ),
                                onTap: WorkerService.isManager
                                    ? () => _showEditDialog(e)
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: WorkerService.isManager
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
              onPressed: () => _showAddDialog(),
            )
          : null,
    );
  }

  void _showAddDialog() {
    _showExpenseForm(null);
  }

  void _showEditDialog(Expense expense) {
    _showExpenseForm(expense);
  }

  void _showExpenseForm(Expense? existing) {
    final amountCtrl = TextEditingController(
        text: existing != null ? existing.amount.toStringAsFixed(2) : '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    String category = existing?.category ?? 'other';
    DateTime date = existing?.date ?? DateTime.now();
    bool saving = false;

    final categories = ['rent', 'utilities', 'supplies', 'salary', 'other'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(existing == null ? 'Add Expense' : 'Edit Expense',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: category,
                decoration:
                    const InputDecoration(labelText: 'Category'),
                items: categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(_capitalize(c)),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setSheetState(() => category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Amount *'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(_dateFmt.format(date)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) {
                    setSheetState(() => date = picked);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(children: [
                if (existing != null)
                  IconButton.filled(
                    icon: const Icon(Icons.delete_outline),
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade50),
                    color: Colors.red,
                    onPressed: () async {
                      await DatabaseService.deleteExpense(existing.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _reload();
                    },
                  ),
                const Spacer(),
                OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final amount =
                              double.tryParse(amountCtrl.text) ?? 0;
                          if (amount <= 0) return;
                          setSheetState(() => saving = true);
                          try {
                            if (existing == null) {
                              await DatabaseService.addExpense(Expense(
                                id: 0,
                                category: category,
                                amount: amount,
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                                date: date,
                                workerName: WorkerService.workerName,
                              ));
                            } else {
                              await DatabaseService.updateExpense(
                                  existing.id, {
                                'category': category,
                                'amount': amount,
                                'description': descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                                'date': date
                                    .toIso8601String()
                                    .split('T')
                                    .first,
                              });
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            _reload();
                          } catch (e) {
                            setSheetState(() => saving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('Error: $e')));
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(existing == null ? 'Add' : 'Save'),
                ),
              ]),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static IconData _categoryIcon(String cat) {
    switch (cat) {
      case 'rent':
        return Icons.home_outlined;
      case 'utilities':
        return Icons.bolt_outlined;
      case 'supplies':
        return Icons.inventory_2_outlined;
      case 'salary':
        return Icons.people_outline;
      default:
        return Icons.receipt_outlined;
    }
  }

  static Color _categoryColor(String cat) {
    switch (cat) {
      case 'rent':
        return Colors.indigo;
      case 'utilities':
        return Colors.amber.shade800;
      case 'supplies':
        return Colors.teal;
      case 'salary':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
