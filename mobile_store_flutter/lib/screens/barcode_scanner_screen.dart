import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../services/database_service.dart';
import '../widgets/checkout_form.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

enum _Step { camera, cartReview, checkout, addProduct }

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  _Step _step = _Step.camera;
  bool _processing = false;
  bool _torchOn = false;
  String _mode = 'out'; // 'in' | 'out'

  // Cart (Stock OUT)
  final List<CartItem> _cart = [];

  // Last scanned (used in cartReview step)
  Product? _lastScanned;
  int _lastQty = 1;

  // Unknown barcode
  String? _unknownBarcode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Reset to camera (clear cart too) ─────────────────────────────────────

  Future<void> _resetAll() async {
    setState(() {
      _step = _Step.camera;
      _processing = false;
      _cart.clear();
      _lastScanned = null;
      _unknownBarcode = null;
    });
    await _controller.start();
  }

  // ── Resume scanning (keep cart) ───────────────────────────────────────────

  Future<void> _scanAnother() async {
    setState(() {
      _step = _Step.camera;
      _processing = false;
      _lastScanned = null;
      _unknownBarcode = null;
    });
    await _controller.start();
  }

  // ── Barcode detected ──────────────────────────────────────────────────────

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_step != _Step.camera || _processing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _processing = true);
    await _controller.stop();

    final product = await DatabaseService.getProductByBarcode(code);

    if (!mounted) return;

    if (product == null) {
      setState(() {
        _unknownBarcode = code;
        _step = _Step.addProduct;
        _processing = false;
      });
      return;
    }

    if (_mode == 'in') {
      // Stock In: go directly to stock-in view
      setState(() {
        _lastScanned = product;
        _lastQty = 1;
        _step = _Step.cartReview; // reuse cartReview for stock-in confirmation
        _processing = false;
      });
    } else {
      // Stock Out: check if already in cart
      final existingIdx = _cart.indexWhere((c) => c.product.id == product.id);
      if (existingIdx >= 0) {
        _cart[existingIdx].qty++;
        setState(() {
          _lastScanned = product;
          _lastQty = _cart[existingIdx].qty;
          _step = _Step.cartReview;
          _processing = false;
        });
      } else {
        _cart.add(CartItem(product: product, qty: 1));
        setState(() {
          _lastScanned = product;
          _lastQty = 1;
          _step = _Step.cartReview;
          _processing = false;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.camera:
        return _buildCamera();
      case _Step.cartReview:
        return _mode == 'in'
            ? _StockInView(product: _lastScanned!, onDone: _resetAll)
            : _CartReviewView(
                lastScanned: _lastScanned!,
                cart: _cart,
                onScanAnother: _scanAnother,
                onCheckout: () => setState(() => _step = _Step.checkout),
                onQtyChanged: (product, qty) {
                  setState(() {
                    final idx = _cart.indexWhere((c) => c.product.id == product.id);
                    if (idx >= 0) {
                      if (qty <= 0) {
                        _cart.removeAt(idx);
                        if (_cart.isEmpty) _scanAnother();
                      } else {
                        _cart[idx].qty = qty;
                      }
                    }
                  });
                },
              );
      case _Step.checkout:
        return CheckoutForm(
          cart: List.from(_cart),
          onDone: _resetAll,
        );
      case _Step.addProduct:
        return _AddProductView(
          barcode: _unknownBarcode ?? '',
          onSaved: _mode == 'in' ? _resetAll : _scanAnother,
          onCancel: _scanAnother,
        );
    }
  }

  Widget _buildCamera() {
    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),

        // Mode toggle + torch
        Positioned(
          top: 40,
          left: 12,
          right: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                color: Colors.black54,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ModeChip(
                        label: 'Stock OUT',
                        selected: _mode == 'out',
                        onTap: () => setState(() => _mode = 'out'),
                      ),
                      const SizedBox(width: 6),
                      _ModeChip(
                        label: 'Stock IN',
                        selected: _mode == 'in',
                        onTap: () => setState(() => _mode = 'in'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  _controller.toggleTorch();
                  setState(() => _torchOn = !_torchOn);
                },
                child: Card(
                  color: Colors.black54,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _torchOn ? Icons.flash_on : Icons.flash_off,
                      color: _torchOn ? Colors.yellow : Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Scanner frame
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _FramePainter())),
        ),

        // Cart badge (Stock OUT)
        if (_mode == 'out' && _cart.isNotEmpty)
          Positioned(
            top: 40,
            right: 72,
            child: GestureDetector(
              onTap: () => setState(() => _step = _Step.cartReview),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shopping_cart, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${_cart.fold(0, (s, c) => s + c.qty)} item(s)',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Hint text
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _mode == 'out'
                    ? 'Point at barcode to add to cart'
                    : 'Point at barcode to add stock',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),

        // Loading overlay
        if (_processing)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Looking up barcode…',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Cart Review ───────────────────────────────────────────────────────────────

class _CartReviewView extends StatelessWidget {
  final Product lastScanned;
  final List<CartItem> cart;
  final VoidCallback onScanAnother;
  final VoidCallback onCheckout;
  final void Function(Product, int) onQtyChanged;

  const _CartReviewView({
    required this.lastScanned,
    required this.cart,
    required this.onScanAnother,
    required this.onCheckout,
    required this.onQtyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);
    final total = cart.fold(0.0, (s, c) => s + c.total);

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Added: ${lastScanned.name}',
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text('${money.format(lastScanned.price)} each',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),

          // Cart list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: cart.length,
              itemBuilder: (ctx, i) {
                final item = cart[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.name,
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text(money.format(item.product.price) + ' each',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        // Qty stepper
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                item.qty <= 1 ? Icons.delete_outline : Icons.remove,
                                color: item.qty <= 1 ? Colors.red : null,
                                size: 20,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  onQtyChanged(item.product, item.qty - 1),
                            ),
                            Text('${item.qty}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add, size: 20),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  onQtyChanged(item.product, item.qty + 1),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 70,
                          child: Text(
                            money.format(item.total),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Total + action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                )
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total (${cart.fold(0, (s, c) => s + c.qty)} items)',
                        style: theme.textTheme.titleMedium),
                    Text(money.format(total),
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan Another'),
                        onPressed: onScanAnother,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Checkout'),
                        onPressed: onCheckout,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stock In ──────────────────────────────────────────────────────────────────

class _StockInView extends StatefulWidget {
  final Product product;
  final VoidCallback onDone;
  const _StockInView({required this.product, required this.onDone});

  @override
  State<_StockInView> createState() => _StockInViewState();
}

class _StockInViewState extends State<_StockInView> {
  int _qty = 1;
  bool _saving = false;
  bool _done = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await DatabaseService.adjustStock(widget.product.id, _qty);
      setState(() { _saving = false; _done = true; });
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

    if (_done) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('Stock Updated!', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('Added $_qty unit(s) to ${widget.product.name}',
                  textAlign: TextAlign.center),
              const SizedBox(height: 28),
              FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Another'),
                onPressed: widget.onDone,
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock In', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: const Icon(Icons.inventory_2_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.product.name,
                              style: theme.textTheme.titleMedium),
                          Text('Current stock: ${widget.product.stock}',
                              style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Quantity to add:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filled(
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('$_qty', style: theme.textTheme.headlineLarge),
                ),
                IconButton.filled(
                  onPressed: () => setState(() => _qty++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const Spacer(),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: widget.onDone, child: const Text('Cancel')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _confirm,
                  child: _saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Add Product (unknown barcode) ─────────────────────────────────────────────

class _AddProductView extends StatefulWidget {
  final String barcode;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const _AddProductView({
    required this.barcode,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  State<_AddProductView> createState() => _AddProductViewState();
}

class _AddProductViewState extends State<_AddProductView> {
  final _formKey  = GlobalKey<FormState>();
  final _name     = TextEditingController();
  final _price    = TextEditingController();
  final _stock    = TextEditingController(text: '1');
  final _category = TextEditingController();
  bool _saving    = false;

  @override
  void dispose() {
    _name.dispose(); _price.dispose(); _stock.dispose(); _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await DatabaseService.addProduct(Product(
        id: 0,
        name: _name.text.trim(),
        barcode: widget.barcode,
        price: double.parse(_price.text),
        stock: int.parse(_stock.text),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product added to inventory!')));
        widget.onSaved();
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
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.search_off, size: 32, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New Product', style: theme.textTheme.titleLarge),
                        Text('Barcode: ${widget.barcode}',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.grey)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text(
                    'This barcode is not in your inventory yet. '
                    'Fill in the details to add it.',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const Divider(height: 24),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Product Name *'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(labelText: 'Price *'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      decoration: const InputDecoration(labelText: 'Stock Qty'),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          int.tryParse(v ?? '') == null ? 'Invalid' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _category,
                  decoration:
                      const InputDecoration(labelText: 'Category (optional)'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                        onPressed: widget.onCancel,
                        child: const Text('Cancel')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Add to Inventory'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Scanner overlay ───────────────────────────────────────────────────────────

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const w = 260.0;
    const h = 160.0;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

    final dimPaint = Paint()..color = Colors.black.withOpacity(0.45);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(RRect.fromRectXY(rect, 10, 10)),
      ),
      dimPaint,
    );

    const cl = 26.0;
    final lp = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final corner in [
      [rect.topLeft,     const Offset(cl, 0),   const Offset(0, cl)],
      [rect.topRight,    const Offset(-cl, 0),  const Offset(0, cl)],
      [rect.bottomLeft,  const Offset(cl, 0),   const Offset(0, -cl)],
      [rect.bottomRight, const Offset(-cl, 0),  const Offset(0, -cl)],
    ]) {
      final o = corner[0] as Offset;
      canvas.drawLine(o, o + (corner[1] as Offset), lp);
      canvas.drawLine(o, o + (corner[2] as Offset), lp);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.blue : Colors.white54),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }
}
