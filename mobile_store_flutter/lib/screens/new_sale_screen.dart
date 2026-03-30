import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import '../services/receipt_service.dart';

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  // Cart
  final List<_CartItem> _cart = [];

  // Payment
  String _paymentType = 'cash';
  final _discountCtrl = TextEditingController(text: '0.00');
  final _customerPaysCtrl = TextEditingController();
  final _receivedCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _saving = false;
  Invoice? _createdInvoice;

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _resetTotals();
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _customerPaysCtrl.dispose();
    _receivedCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  double get _subtotal =>
      _cart.fold(0, (s, c) => s + c.product.price * c.qty);
  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get _customerPays =>
      double.tryParse(_customerPaysCtrl.text) ?? _subtotal;
  double get _amountReceived =>
      double.tryParse(_receivedCtrl.text) ?? 0;
  double get _change =>
      (_amountReceived - _customerPays).clamp(0, double.infinity);

  void _resetTotals() {
    _discountCtrl.text = '0.00';
    _customerPaysCtrl.text = _subtotal.toStringAsFixed(2);
    _receivedCtrl.text = _subtotal.toStringAsFixed(2);
  }

  void _onDiscountChanged(String val) {
    final d = double.tryParse(val) ?? 0;
    final cp = (_subtotal - d).clamp(0.0, _subtotal);
    _customerPaysCtrl.text = cp.toStringAsFixed(2);
    _receivedCtrl.text = cp.toStringAsFixed(2);
    setState(() {});
  }

  void _onCustomerPaysChanged(String val) {
    final cp = double.tryParse(val) ?? _subtotal;
    final d = (_subtotal - cp).clamp(0.0, _subtotal);
    _discountCtrl.text = d.toStringAsFixed(2);
    _receivedCtrl.text = cp.toStringAsFixed(2);
    setState(() {});
  }

  void _addProduct(Product p) {
    setState(() {
      final existing =
          _cart.indexWhere((c) => c.product.id == p.id);
      if (existing >= 0) {
        _cart[existing] =
            _CartItem(_cart[existing].product, _cart[existing].qty + 1);
      } else {
        _cart.add(_CartItem(p, 1));
      }
      _resetTotals();
    });
  }

  void _removeItem(int index) {
    setState(() {
      _cart.removeAt(index);
      _resetTotals();
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty.')),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final items = _cart
          .map((c) => InvoiceItem(
                productName: c.product.name,
                qty: c.qty,
                unitPrice: c.product.price,
              ))
          .toList();

      final inv = await DatabaseService.createInvoice(
        customerName: _nameCtrl.text.trim().isEmpty
            ? null
            : _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        items: items,
        markedPrice: _subtotal,
        discount: _discount,
        customerPays: _customerPays,
        amountReceived: _amountReceived,
        change: _change,
        paymentType: _paymentType,
      );

      // Deduct stock for each item
      for (final c in _cart) {
        await DatabaseService.adjustStock(c.product.id, -c.qty);
      }

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

  void _reset() {
    setState(() {
      _cart.clear();
      _paymentType = 'cash';
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _createdInvoice = null;
      _resetTotals();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_createdInvoice != null) {
      return _DoneView(invoice: _createdInvoice!, onNew: _reset);
    }

    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Add product button
          FilledButton.icon(
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Add Product'),
            onPressed: () => _showProductPicker(context),
          ),
          const SizedBox(height: 12),

          // Cart
          if (_cart.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Cart is empty')),
            )
          else ...[
            Card(
              child: Column(
                children: [
                  ..._cart.asMap().entries.map((e) {
                    final i = e.key;
                    final c = e.value;
                    return ListTile(
                      title: Text(c.product.name),
                      subtitle: Text(
                          '${_money.format(c.product.price)} × ${c.qty} = ${_money.format(c.product.price * c.qty)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: () => _removeItem(i),
                      ),
                    );
                  }),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(_money.format(_subtotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Discount & Customer Pays
            TextField(
              controller: _discountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Discount'),
              onChanged: _onDiscountChanged,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customerPaysCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Customer Pays'),
              onChanged: _onCustomerPaysChanged,
            ),
            const SizedBox(height: 16),

            // Payment type
            Text('Payment Type', style: theme.textTheme.labelLarge),
            Row(children: [
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
            ]),

            TextField(
              controller: _receivedCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: _paymentType == 'cash'
                      ? 'Amount Received'
                      : 'Amount Transferred'),
              onChanged: (_) => setState(() {}),
            ),

            if (_change > 0) ...[
              const SizedBox(height: 8),
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
            ],

            const SizedBox(height: 16),
            const Divider(),
            Text('Customer Info (optional)',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Customer Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
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
        ],
      ),
    );
  }

  void _showProductPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPickerSheet(onPick: _addProduct),
    );
  }
}

// ── Product picker ────────────────────────────────────────────────────────────

class _ProductPickerSheet extends StatefulWidget {
  final void Function(Product) onPick;
  const _ProductPickerSheet({required this.onPick});

  @override
  State<_ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  late Future<List<Product>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = DatabaseService.getProducts();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          const SizedBox(height: 12),
          const Text('Select Product',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final products = (snap.data ?? [])
                    .where((p) =>
                        p.stock > 0 &&
                        (_search.isEmpty ||
                         p.name.toLowerCase().contains(_search) ||
                         (p.barcode?.toLowerCase().contains(_search) ?? false)))
                    .toList();
                if (products.isEmpty) {
                  return const Center(child: Text('No products in stock.'));
                }
                return ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (ctx, i) {
                    final p = products[i];
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text('Stock: ${p.stock}'),
                      trailing: Text(
                        NumberFormat.currency(
                                symbol: AppConfig.currency,
                                decimalDigits: 2)
                            .format(p.price),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        widget.onPick(p);
                        Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Done view ─────────────────────────────────────────────────────────────────

class _DoneView extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onNew;
  const _DoneView({required this.invoice, required this.onNew});

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
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('New Sale'),
              onPressed: onNew,
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItem {
  final Product product;
  final int qty;
  const _CartItem(this.product, this.qty);
}
