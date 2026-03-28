import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import '../services/receipt_service.dart';
import 'receipt_bottom_sheet.dart';

class CheckoutForm extends StatefulWidget {
  final Product product;
  final VoidCallback onDone;

  const CheckoutForm({super.key, required this.product, required this.onDone});

  @override
  State<CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends State<CheckoutForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0.00');
  final _customerPaysCtrl = TextEditingController();
  final _receivedCtrl = TextEditingController();

  int _qty = 1;
  String _paymentType = 'cash';
  bool _saving = false;
  Invoice? _createdInvoice;

  double get _markedPrice => widget.product.price * _qty;

  double get _discount {
    return double.tryParse(_discountCtrl.text) ?? 0;
  }

  double get _customerPays {
    return double.tryParse(_customerPaysCtrl.text) ?? _markedPrice;
  }

  double get _amountReceived {
    return double.tryParse(_receivedCtrl.text) ?? 0;
  }

  double get _change =>
      (_amountReceived - _customerPays).clamp(0, double.infinity);

  final _money = NumberFormat.currency(
      symbol: AppConfig.currency, decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _customerPaysCtrl.text = _markedPrice.toStringAsFixed(2);
    _receivedCtrl.text = _markedPrice.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _discountCtrl.dispose();
    _customerPaysCtrl.dispose();
    _receivedCtrl.dispose();
    super.dispose();
  }

  void _onDiscountChanged(String val) {
    final d = double.tryParse(val) ?? 0;
    final cp = (_markedPrice - d).clamp(0, _markedPrice);
    _customerPaysCtrl.text = cp.toStringAsFixed(2);
    _receivedCtrl.text = cp.toStringAsFixed(2);
    setState(() {});
  }

  void _onCustomerPaysChanged(String val) {
    final cp = double.tryParse(val) ?? _markedPrice;
    final d = (_markedPrice - cp).clamp(0.0, _markedPrice);
    _discountCtrl.text = d.toStringAsFixed(2);
    _receivedCtrl.text = cp.toStringAsFixed(2);
    setState(() {});
  }

  void _onQtyChanged(int delta) {
    setState(() {
      _qty = (_qty + delta).clamp(1, 9999);
      final mp = widget.product.price * _qty;
      final d = _discount;
      final cp = (mp - d).clamp(0.0, mp);
      _discountCtrl.text = d.toStringAsFixed(2);
      _customerPaysCtrl.text = cp.toStringAsFixed(2);
      _receivedCtrl.text = cp.toStringAsFixed(2);
    });
  }

  Future<void> _checkout() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final item = InvoiceItem(
        productName: widget.product.name,
        qty: _qty,
        unitPrice: widget.product.price,
      );

      final inv = await DatabaseService.createInvoice(
        customerName:
            _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        customerPhone:
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        items: [item],
        markedPrice: _markedPrice,
        discount: _discount,
        customerPays: _customerPays,
        amountReceived: _amountReceived,
        change: _change,
        paymentType: _paymentType,
      );

      // Deduct stock
      await DatabaseService.adjustStock(widget.product.id, -_qty);

      setState(() {
        _saving = false;
        _createdInvoice = inv;
      });
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
    if (_createdInvoice != null) {
      return _ReceiptView(
        invoice: _createdInvoice!,
        onDone: widget.onDone,
      );
    }

    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text('Checkout', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),

            // Product card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.product.name,
                              style: theme.textTheme.titleMedium),
                          Text(_money.format(widget.product.price) + ' each',
                              style:
                                  const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                    // Qty stepper
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _qty > 1 ? () => _onQtyChanged(-1) : null),
                        Text('$_qty',
                            style: theme.textTheme.titleMedium),
                        IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _onQtyChanged(1)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Marked price
            _ReadonlyField(
              label: 'Marked Price',
              value: _money.format(_markedPrice),
            ),
            const SizedBox(height: 10),

            // Discount
            TextFormField(
              controller: _discountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Discount'),
              onChanged: _onDiscountChanged,
            ),
            const SizedBox(height: 10),

            // Customer pays
            TextFormField(
              controller: _customerPaysCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Customer Pays'),
              onChanged: _onCustomerPaysChanged,
            ),
            const SizedBox(height: 16),

            // Payment type
            Text('Payment Type', style: theme.textTheme.labelLarge),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Cash'),
                    value: 'cash',
                    groupValue: _paymentType,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _paymentType = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('QuickPay'),
                    value: 'quickpay',
                    groupValue: _paymentType,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _paymentType = v!),
                  ),
                ),
              ],
            ),

            // Amount received / transferred
            TextFormField(
              controller: _receivedCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _paymentType == 'cash'
                    ? 'Amount Received'
                    : 'Amount Transferred',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),

            if (_change > 0)
              Card(
                color: Colors.green.shade50,
                child: ListTile(
                  leading: const Icon(Icons.check_circle,
                      color: Colors.green),
                  title: Text('Change: ${_money.format(_change)}',
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold)),
                ),
              ),

            const SizedBox(height: 16),
            const Divider(),
            Text('Customer Info (optional)',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),

            TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Customer Name'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              decoration:
                  const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: widget.onDone,
                      child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _checkout,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Complete Sale'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Receipt view after sale ───────────────────────────────────────────────────

class _ReceiptView extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onDone;

  const _ReceiptView({required this.invoice, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 64, color: Colors.green),
            const SizedBox(height: 12),
            Text('Sale Complete!',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Share / Print Receipt'),
              onPressed: () => ReceiptService.shareReceipt(invoice),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Another'),
              onPressed: onDone,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Readonly display field ────────────────────────────────────────────────────

class _ReadonlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadonlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(value,
          style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
