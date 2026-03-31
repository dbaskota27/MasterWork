import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../services/database_service.dart';
import '../services/worker_service.dart';

class SalesTargetsScreen extends StatefulWidget {
  const SalesTargetsScreen({super.key});

  @override
  State<SalesTargetsScreen> createState() => _SalesTargetsScreenState();
}

class _SalesTargetsScreenState extends State<SalesTargetsScreen> {
  List<Map<String, dynamic>> _targets = [];
  Map<int, double> _actualSales = {};
  bool _loading = true;

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);
  final _dateFmt = DateFormat('MMM d, y');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final targets = await DatabaseService.getSalesTargets();
      final Map<int, double> sales = {};

      for (final t in targets) {
        final id = (t['id'] as num).toInt();
        final workerName = t['worker_name'] as String?;
        if (workerName != null) {
          final periodStart = DateTime.parse(t['period_start'] as String);
          final periodEnd = DateTime.parse(t['period_end'] as String)
              .add(const Duration(days: 1));
          final actual = await DatabaseService.getWorkerSales(
            workerName: workerName,
            from: periodStart,
            to: periodEnd,
          );
          sales[id] = actual;
        }
      }

      setState(() {
        _targets = targets;
        _actualSales = sales;
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
      appBar: AppBar(title: const Text('Sales Targets')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _targets.isEmpty
              ? const Center(child: Text('No sales targets set.'))
              : RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _targets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final t = _targets[i];
                      final id = (t['id'] as num).toInt();
                      final workerName =
                          t['worker_name'] as String? ?? 'Unknown';
                      final periodType =
                          t['period_type'] as String? ?? 'daily';
                      final target =
                          (t['target_amount'] as num?)?.toDouble() ?? 0;
                      final periodStart =
                          DateTime.parse(t['period_start'] as String);
                      final periodEnd =
                          DateTime.parse(t['period_end'] as String);
                      final actual = _actualSales[id] ?? 0;
                      final progress =
                          target > 0 ? (actual / target).clamp(0.0, 1.0) : 0.0;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    child: Text(
                                        workerName.isNotEmpty
                                            ? workerName[0].toUpperCase()
                                            : '?',
                                        style:
                                            const TextStyle(fontSize: 14)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(workerName,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        Text(
                                          '${periodType == 'daily' ? 'Daily' : 'Monthly'}  ·  '
                                          '${_dateFmt.format(periodStart)} - ${_dateFmt.format(periodEnd)}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (WorkerService.isManager)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red, size: 20),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title:
                                                const Text('Delete Target?'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, false),
                                                  child:
                                                      const Text('Cancel')),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, true),
                                                  child:
                                                      const Text('Delete')),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await DatabaseService
                                              .deleteSalesTarget(id);
                                          _reload();
                                        }
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      '${_money.format(actual)} / ${_money.format(target)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                  Text(
                                    '${(progress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: progress >= 1.0
                                          ? Colors.green
                                          : progress >= 0.5
                                              ? Colors.orange
                                              : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: progress.toDouble(),
                                  minHeight: 8,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation(
                                    progress >= 1.0
                                        ? Colors.green
                                        : progress >= 0.5
                                            ? Colors.orange
                                            : Colors.red.shade400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: WorkerService.isManager
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New Target'),
              onPressed: _showAddDialog,
            )
          : null,
    );
  }

  void _showAddDialog() {
    final amountCtrl = TextEditingController();
    String periodType = 'daily';
    String? selectedWorkerName;
    int? selectedWorkerId;
    DateTime periodStart = DateTime.now();
    DateTime periodEnd = DateTime.now();
    bool saving = false;
    List<Map<String, dynamic>> workers = [];
    bool workersLoaded = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          if (!workersLoaded) {
            workersLoaded = true;
            WorkerService.listWorkers().then((w) {
              setSheetState(() => workers = w);
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('New Sales Target',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 16),

                  // Worker dropdown
                  DropdownButtonFormField<int>(
                    value: selectedWorkerId,
                    decoration:
                        const InputDecoration(labelText: 'Worker'),
                    items: workers
                        .map((w) => DropdownMenuItem<int>(
                              value: (w['id'] as num).toInt(),
                              child: Text(
                                  w['display_name'] as String? ??
                                      'Unknown'),
                            ))
                        .toList(),
                    onChanged: (id) {
                      final w = workers.firstWhere(
                          (w) => (w['id'] as num).toInt() == id);
                      setSheetState(() {
                        selectedWorkerId = id;
                        selectedWorkerName =
                            w['display_name'] as String?;
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Period type
                  Row(children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Daily'),
                        value: 'daily',
                        groupValue: periodType,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) =>
                            setSheetState(() => periodType = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Monthly'),
                        value: 'monthly',
                        groupValue: periodType,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) =>
                            setSheetState(() => periodType = v!),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // Amount
                  TextField(
                    controller: amountCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Target Amount'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                  const SizedBox(height: 12),

                  // Date range
                  Row(children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Start',
                            style: TextStyle(fontSize: 12)),
                        subtitle: Text(_dateFmt.format(periodStart)),
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: periodStart,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) {
                            setSheetState(() => periodStart = d);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('End',
                            style: TextStyle(fontSize: 12)),
                        subtitle: Text(_dateFmt.format(periodEnd)),
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: periodEnd,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) {
                            setSheetState(() => periodEnd = d);
                          }
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final amount =
                                    double.tryParse(amountCtrl.text) ?? 0;
                                if (amount <= 0 ||
                                    selectedWorkerName == null) return;
                                setSheetState(() => saving = true);
                                try {
                                  await DatabaseService.createSalesTarget(
                                    workerId: selectedWorkerId,
                                    workerName: selectedWorkerName,
                                    periodType: periodType,
                                    targetAmount: amount,
                                    periodStart: periodStart,
                                    periodEnd: periodEnd,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _reload();
                                } catch (e) {
                                  setSheetState(() => saving = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                            content:
                                                Text('Error: $e')));
                                  }
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Text('Create'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
