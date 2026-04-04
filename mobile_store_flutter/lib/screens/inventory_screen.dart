import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/worker_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<Product>> _future;
  String _search = '';

  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _future = DatabaseService.getProducts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search inventory...',
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
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final products = (snap.data ?? [])
                    .where((p) =>
                        p.name.toLowerCase().contains(_search) ||
                        (p.barcode?.toLowerCase().contains(_search) ?? false) ||
                        (p.brand?.toLowerCase().contains(_search) ?? false) ||
                        (p.model?.toLowerCase().contains(_search) ?? false) ||
                        (p.imei?.contains(_search) ?? false) ||
                        (p.serialNumber?.toLowerCase().contains(_search) ?? false) ||
                        (p.category?.toLowerCase().contains(_search) ?? false))
                    .toList();

                if (products.isEmpty) {
                  return const Center(child: Text('No products found.'));
                }

                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (ctx, i) =>
                        _ProductTile(
                      product: products[i],
                      moneyFmt: _money,
                      onUpdated: _reload,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: WorkerService.hasPermission('inventory_edit')
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
              onPressed: () => _showAddDialog(context),
            )
          : null,
    );
  }

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductForm(
        onSaved: (p) async {
          await DatabaseService.addProduct(p);
          _reload();
        },
      ),
    );
  }
}

// ── Product tile ──────────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  final Product product;
  final NumberFormat moneyFmt;
  final VoidCallback onUpdated;

  const _ProductTile(
      {required this.product,
      required this.moneyFmt,
      required this.onUpdated});

  @override
  Widget build(BuildContext context) {
    final lowStock = product.stock <= product.lowStockThreshold;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: lowStock
              ? Colors.orange.shade100
              : Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            '${product.stock}',
            style: TextStyle(
                color: lowStock ? Colors.orange.shade800 : null,
                fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(product.name),
        subtitle: Text([
          product.brand ?? product.category ?? 'Uncategorized',
          if (product.model != null) product.model!,
          if (product.imei != null) 'IMEI: ${product.imei!}',
          if (product.imei == null) product.barcode ?? 'No barcode',
        ].join(' · ')),
        trailing: Text(
          moneyFmt.format(product.price),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onTap: WorkerService.hasPermission('inventory_edit')
            ? () => _showEditDialog(context)
            : null,
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductForm(
        existing: product,
        onSaved: (p) async {
          await DatabaseService.updateProduct(product.id, {
            'name': p.name,
            'price': p.price,
            'cost_price': p.costPrice,
            'stock': p.stock,
            'low_stock_threshold': p.lowStockThreshold,
            'barcode': p.barcode,
            'brand': p.brand,
            'model': p.model,
            'imei': p.imei,
            'serial_number': p.serialNumber,
            'category': p.category,
          });
          onUpdated();
        },
        onDelete: () async {
          await DatabaseService.deleteProduct(product.id);
          onUpdated();
        },
      ),
    );
  }
}

// ── Add / Edit form ───────────────────────────────────────────────────────────

class _ProductForm extends StatefulWidget {
  final Product? existing;
  final Future<void> Function(Product) onSaved;
  final Future<void> Function()? onDelete;

  const _ProductForm({this.existing, required this.onSaved, this.onDelete});

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _brand;
  late TextEditingController _model;
  late TextEditingController _imei;
  late TextEditingController _serial;
  late TextEditingController _price;
  late TextEditingController _costPrice;
  late TextEditingController _stock;
  late TextEditingController _lowStockThreshold;
  late TextEditingController _barcode;
  late TextEditingController _category;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _model = TextEditingController(text: p?.model ?? '');
    _imei = TextEditingController(text: p?.imei ?? '');
    _serial = TextEditingController(text: p?.serialNumber ?? '');
    _price =
        TextEditingController(text: p != null ? p.price.toStringAsFixed(2) : '');
    _costPrice =
        TextEditingController(text: p != null ? p.costPrice.toStringAsFixed(2) : '0.00');
    _stock = TextEditingController(text: p != null ? '${p.stock}' : '0');
    _lowStockThreshold = TextEditingController(
        text: p != null ? '${p.lowStockThreshold}' : '5');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _category = TextEditingController(text: p?.category ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _model.dispose();
    _imei.dispose();
    _serial.dispose();
    _price.dispose();
    _costPrice.dispose();
    _stock.dispose();
    _lowStockThreshold.dispose();
    _barcode.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final p = Product(
      id: widget.existing?.id ?? 0,
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      model: _model.text.trim().isEmpty ? null : _model.text.trim(),
      imei: _imei.text.trim().isEmpty ? null : _imei.text.trim(),
      serialNumber: _serial.text.trim().isEmpty ? null : _serial.text.trim(),
      price: double.parse(_price.text),
      costPrice: double.tryParse(_costPrice.text) ?? 0,
      stock: int.parse(_stock.text),
      lowStockThreshold: int.tryParse(_lowStockThreshold.text) ?? 5,
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      category:
          _category.text.trim().isEmpty ? null : _category.text.trim(),
    );
    try {
      await widget.onSaved(p);
      if (mounted) Navigator.pop(context);
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.existing == null ? 'Add Product' : 'Edit Product',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Product Name *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    decoration:
                        const InputDecoration(labelText: 'Sell Price *'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (double.tryParse(v) == null) return 'Invalid';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _costPrice,
                    decoration:
                        const InputDecoration(labelText: 'Cost Price'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _stock,
                    decoration:
                        const InputDecoration(labelText: 'Stock'),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        int.tryParse(v ?? '') == null ? 'Invalid' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _lowStockThreshold,
                    decoration:
                        const InputDecoration(labelText: 'Low Stock Alert'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _brand,
                    decoration: const InputDecoration(labelText: 'Brand'),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: 'Model'),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextFormField(
                controller: _imei,
                decoration: const InputDecoration(labelText: 'IMEI'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _serial,
                decoration: const InputDecoration(labelText: 'Serial Number (S/N)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _barcode,
                decoration:
                    const InputDecoration(labelText: 'Product Barcode (EAN/UPC)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _category,
                decoration:
                    const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 20),
              Row(children: [
                if (widget.onDelete != null)
                  IconButton.filled(
                    icon: const Icon(Icons.delete_outline),
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade50),
                    color: Colors.red,
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete Product?'),
                          content:
                              const Text('This action cannot be undone.'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await widget.onDelete!();
                        if (mounted) Navigator.pop(context);
                      }
                    },
                  ),
                const Spacer(),
                OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(widget.existing == null ? 'Add' : 'Save'),
                ),
              ]),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
