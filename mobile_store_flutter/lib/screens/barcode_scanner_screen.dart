import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../widgets/checkout_form.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

// Steps: camera → result (stock-in, checkout, or add-product)
enum _Step { camera, stockIn, checkout, addProduct }

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  _Step _step = _Step.camera;
  bool _processing = false; // DB lookup in progress
  bool _torchOn = false;
  String _mode = 'out'; // 'in' | 'out'

  Product? _foundProduct;
  String? _scannedBarcode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Reset to camera ───────────────────────────────────────────────────────

  Future<void> _reset() async {
    setState(() {
      _step = _Step.camera;
      _processing = false;
      _foundProduct = null;
      _scannedBarcode = null;
    });
    await _controller.start();
  }

  // ── Barcode detected ──────────────────────────────────────────────────────

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_step != _Step.camera || _processing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    // Show loading overlay ON TOP of camera — don't switch view yet
    setState(() => _processing = true);
    await _controller.stop();

    final product = await DatabaseService.getProductByBarcode(code);

    if (!mounted) return;

    setState(() {
      _scannedBarcode = code;
      _foundProduct = product;
      _processing = false;

      if (product == null) {
        _step = _Step.addProduct;
      } else if (_mode == 'in') {
        _step = _Step.stockIn;
      } else {
        _step = _Step.checkout;
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.camera:
        return _buildCamera();
      case _Step.stockIn:
        return _StockInView(product: _foundProduct!, onDone: _reset);
      case _Step.checkout:
        return CheckoutForm(product: _foundProduct!, onDone: _reset);
      case _Step.addProduct:
        return _AddProductView(
          barcode: _scannedBarcode ?? '',
          onSaved: _reset,
          onCancel: _reset,
        );
    }
  }

  Widget _buildCamera() {
    return Stack(
      children: [
        // Camera feed fills screen
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),

        // Top controls: mode toggle + torch
        Positioned(
          top: 40,
          left: 12,
          right: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mode toggle
              Card(
                color: Colors.black54,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
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
              // Torch
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

        // Scanner frame overlay
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _FramePainter()),
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
                    ? 'Point at barcode to sell'
                    : 'Point at barcode to add stock',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),

        // Loading overlay — shown WHILE looking up barcode in DB
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _category;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _price = TextEditingController();
    _stock = TextEditingController(text: '1');
    _category = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _category.dispose();
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
          const SnackBar(content: Text('Product added to inventory!')),
        );
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
                // Header
                Row(
                  children: [
                    const Icon(Icons.search_off, size: 32, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New Product',
                              style: theme.textTheme.titleLarge),
                          Text('Barcode: ${widget.barcode}',
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                    'This barcode is not in your inventory yet. '
                    'Fill in the details to add it.',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const Divider(height: 24),

                // Form fields
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
                      decoration:
                          const InputDecoration(labelText: 'Stock Qty'),
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
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
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
      setState(() {
        _saving = false;
        _done = true;
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
                      backgroundColor:
                          theme.colorScheme.primaryContainer,
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
                  child:
                      Text('$_qty', style: theme.textTheme.headlineLarge),
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
                          height: 20,
                          width: 20,
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

// ── Scanner frame overlay ─────────────────────────────────────────────────────

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

// ── Mode chip ─────────────────────────────────────────────────────────────────

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
          border: Border.all(
              color: selected ? Colors.blue : Colors.white54),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }
}
