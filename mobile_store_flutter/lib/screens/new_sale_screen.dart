import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../services/database_service.dart';
import '../widgets/checkout_form.dart';

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final List<CartItem> _cart = [];
  bool _checkout = false;

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);

  double get _subtotal =>
      _cart.fold(0, (s, c) => s + c.total);

  void _addProduct(Product p) {
    setState(() {
      final existing = _cart.indexWhere((c) => c.product.id == p.id);
      if (existing >= 0) {
        _cart[existing].qty++;
      } else {
        _cart.add(CartItem(product: p, qty: 1));
      }
    });
  }

  void _removeItem(int index) {
    setState(() => _cart.removeAt(index));
  }

  void _reset() {
    setState(() {
      _cart.clear();
      _checkout = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkout) {
      return CheckoutForm(
        cart: List.from(_cart),
        onDone: _reset,
      );
    }

    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Add Product'),
            onPressed: () => _showProductPicker(context),
          ),
          const SizedBox(height: 12),

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
                          '${_money.format(c.product.price)} × ${c.qty} = ${_money.format(c.total)}'),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(_money.format(_subtotal),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _cart.isEmpty ? null : () => setState(() => _checkout = true),
                child: const Text('Proceed to Checkout'),
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
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
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
