import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';

class RefundScreen extends StatefulWidget {
  final Invoice invoice;
  const RefundScreen({super.key, required this.invoice});

  @override
  State<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends State<RefundScreen> {
  late List<int> _returnQtys;
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _returnQtys = List.filled(widget.invoice.items.length, 0);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  double get _refundAmount {
    double total = 0;
    for (int i = 0; i < widget.invoice.items.length; i++) {
      total += _returnQtys[i] * widget.invoice.items[i].unitPrice;
    }
    return total;
  }

  bool get _hasReturns => _returnQtys.any((q) => q > 0);

  bool get _isFullRefund {
    for (int i = 0; i < widget.invoice.items.length; i++) {
      if (_returnQtys[i] != widget.invoice.items[i].qty) return false;
    }
    return true;
  }

  Future<void> _processRefund() async {
    if (!_hasReturns) return;
    setState(() => _saving = true);
    try {
      // Build refund items
      final refundItems = <InvoiceItem>[];
      for (int i = 0; i < widget.invoice.items.length; i++) {
        if (_returnQtys[i] > 0) {
          final original = widget.invoice.items[i];
          refundItems.add(InvoiceItem(
            productName: original.productName,
            qty: _returnQtys[i],
            unitPrice: original.unitPrice,
            costPrice: original.costPrice,
          ));
        }
      }

      // Create the refund record
      await DatabaseService.createRefund(
        invoiceId: widget.invoice.id,
        items: refundItems,
        refundAmount: _refundAmount,
        reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      );

      // Adjust stock back (add returned items)
      final products = await DatabaseService.getProducts();
      for (final item in refundItems) {
        final product = products.where((p) => p.name == item.productName).firstOrNull;
        if (product != null) {
          await DatabaseService.adjustStock(product.id, item.qty);
        }
      }

      // Update invoice status
      final newStatus = _isFullRefund ? 'fully_refunded' : 'partially_refunded';
      await DatabaseService.updateInvoiceStatus(widget.invoice.id, newStatus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Refund of ${_money.format(_refundAmount)} processed')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inv = widget.invoice;

    return Scaffold(
      appBar: AppBar(title: Text('Return - Invoice #${inv.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Select items to return', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),

          // Items with qty spinners
          Card(
            child: Column(
              children: List.generate(inv.items.length, (i) {
                final item = inv.items[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            Text(
                                '${_money.format(item.unitPrice)} x ${item.qty} = ${_money.format(item.total)}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      // Qty spinner
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            iconSize: 20,
                            onPressed: _returnQtys[i] > 0
                                ? () => setState(
                                    () => _returnQtys[i]--)
                                : null,
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${_returnQtys[i]}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _returnQtys[i] > 0
                                    ? Colors.red.shade700
                                    : null,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            iconSize: 20,
                            onPressed: _returnQtys[i] < item.qty
                                ? () => setState(
                                    () => _returnQtys[i]++)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          // Reason
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(
              labelText: 'Reason for return (optional)',
              prefixIcon: Icon(Icons.note_outlined),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          // Refund summary
          if (_hasReturns) ...[
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Refund Amount',
                            style: TextStyle(color: Colors.red.shade700)),
                        Text(_money.format(_refundAmount),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.red.shade700)),
                      ],
                    ),
                    Text(
                      _isFullRefund ? 'Full Refund' : 'Partial Refund',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (!_hasReturns || _saving) ? null : _processRefund,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm Refund'),
            ),
          ),
        ],
      ),
    );
  }
}
