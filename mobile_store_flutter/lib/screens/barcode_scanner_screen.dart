import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../services/database_service.dart';
import '../widgets/checkout_form.dart';

// ═══════════════════════════════════════════════════
// Barcode classification — identifies what a scanned code is
// ═══════════════════════════════════════════════════

enum BarcodeType { imei, ean, serial }

class ScannedCode {
  final String value;
  BarcodeType type;

  ScannedCode({required this.value, required this.type});

  String get label {
    switch (type) {
      case BarcodeType.imei:
        return 'IMEI';
      case BarcodeType.ean:
        return 'Product Barcode';
      case BarcodeType.serial:
        return 'Serial / S/N';
    }
  }

  IconData get icon {
    switch (type) {
      case BarcodeType.imei:
        return Icons.phone_android;
      case BarcodeType.ean:
        return Icons.qr_code;
      case BarcodeType.serial:
        return Icons.tag;
    }
  }

  Color get color {
    switch (type) {
      case BarcodeType.imei:
        return Colors.blue;
      case BarcodeType.ean:
        return Colors.green;
      case BarcodeType.serial:
        return Colors.orange;
    }
  }
}

BarcodeType classifyBarcode(String code) {
  final digitsOnly = RegExp(r'^\d+$').hasMatch(code);

  // IMEI: exactly 15 digits
  if (digitsOnly && code.length == 15) return BarcodeType.imei;

  // EAN-13 (13 digits), UPC-A (12 digits), EAN-8 (8 digits)
  if (digitsOnly && (code.length == 13 || code.length == 12 || code.length == 8)) {
    return BarcodeType.ean;
  }

  // Everything else — serial number
  return BarcodeType.serial;
}

// ═══════════════════════════════════════════════════
// Main screen
// ═══════════════════════════════════════════════════

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

enum _Step { camera, cartReview, checkout, addProduct, multiScanReview }

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

  // Unknown barcode
  String? _unknownBarcode;

  // Multi-scan (Stock IN) — collect all barcodes from a phone box
  final List<ScannedCode> _scannedCodes = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resetAll() async {
    setState(() {
      _step = _Step.camera;
      _processing = false;
      _cart.clear();
      _lastScanned = null;
      _unknownBarcode = null;
      _scannedCodes.clear();
    });
    await _controller.start();
  }

  Future<void> _scanAnother() async {
    setState(() {
      _step = _Step.camera;
      _processing = false;
      _lastScanned = null;
      _unknownBarcode = null;
      _scannedCodes.clear();
    });
    await _controller.start();
  }

  // ── Stock OUT: detect & look up ─────────────────────────────────────────

  Future<void> _onDetectStockOut(BarcodeCapture capture) async {
    if (_step != _Step.camera || _processing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _processing = true);
    await _controller.stop();

    // Smart lookup: barcode → IMEI → serial number
    final product = await DatabaseService.findProductByAnyCode(code);

    if (!mounted) return;

    if (product == null) {
      setState(() {
        _unknownBarcode = code;
        _step = _Step.addProduct;
        _processing = false;
      });
      return;
    }

    final existingIdx = _cart.indexWhere((c) => c.product.id == product.id);
    if (existingIdx >= 0) {
      _cart[existingIdx].qty++;
    } else {
      _cart.add(CartItem(product: product, qty: 1));
    }
    setState(() {
      _lastScanned = product;
      _step = _Step.cartReview;
      _processing = false;
    });
  }

  // ── Stock IN: multi-scan — keep camera open, collect codes ──────────────

  Future<void> _onDetectStockIn(BarcodeCapture capture) async {
    if (_step != _Step.camera || _processing) return;

    // Grab ALL barcodes visible in this frame
    int added = 0;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.isEmpty) continue;

      // Skip duplicates
      if (_scannedCodes.any((s) => s.value == code)) continue;

      final type = classifyBarcode(code);
      _scannedCodes.add(ScannedCode(value: code, type: type));
      added++;
    }

    if (added == 0) return;

    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added == 1
            ? 'Scanned ${_scannedCodes.last.label}: ${_scannedCodes.last.value}'
            : 'Scanned $added barcodes at once'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
    }

  }

  void _finishMultiScan() async {
    await _controller.stop();
    if (_scannedCodes.isEmpty) {
      _scanAnother();
      return;
    }

    // Check if the product barcode (EAN) already exists
    final eanCode = _scannedCodes.where((s) => s.type == BarcodeType.ean).firstOrNull;
    if (eanCode != null) {
      final existing = await DatabaseService.getProductByBarcode(eanCode.value);
      if (existing != null && mounted) {
        // Product exists — go to stock-in view
        setState(() {
          _lastScanned = existing;
          _step = _Step.cartReview;
        });
        return;
      }
    }

    // No existing product — go to add-product form with scanned data pre-filled
    setState(() => _step = _Step.multiScanReview);
  }

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
          scannedCodes: const [],
          onSaved: _mode == 'in' ? _resetAll : _scanAnother,
          onCancel: _scanAnother,
        );
      case _Step.multiScanReview:
        return _AddProductView(
          barcode: '',
          scannedCodes: _scannedCodes,
          onSaved: _resetAll,
          onCancel: _scanAnother,
        );
    }
  }

  Widget _buildCamera() {
    final isStockIn = _mode == 'in';

    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: isStockIn ? _onDetectStockIn : _onDetectStockOut,
        ),

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
                        onTap: () => setState(() {
                          _mode = 'out';
                          _scannedCodes.clear();
                        }),
                      ),
                      const SizedBox(width: 6),
                      _ModeChip(
                        label: 'Stock IN',
                        selected: _mode == 'in',
                        onTap: () => setState(() {
                          _mode = 'in';
                          _scannedCodes.clear();
                        }),
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
        if (!isStockIn && _cart.isNotEmpty)
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

        // Stock IN: scanned codes list overlay
        if (isStockIn && _scannedCodes.isNotEmpty)
          Positioned(
            bottom: 130,
            left: 16,
            right: 16,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.checklist, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${_scannedCodes.length} code(s) scanned',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: _scannedCodes.length,
                      itemBuilder: (ctx, i) {
                        final sc = _scannedCodes[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(sc.icon, color: sc.color, size: 16),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: sc.color.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(sc.label,
                                    style: TextStyle(color: sc.color, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(sc.value,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _scannedCodes.removeAt(i)),
                                child: const Icon(Icons.close, color: Colors.white38, size: 16),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
                isStockIn
                    ? 'Scan all barcodes on the box (IMEI, S/N, product code)'
                    : 'Point at any barcode to find the product',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),

        // Stock IN: Done button
        if (isStockIn)
          Positioned(
            bottom: 20,
            left: 40,
            right: 40,
            child: FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(_scannedCodes.isEmpty
                  ? 'Done Scanning'
                  : 'Done — ${_scannedCodes.length} code(s)'),
              onPressed: _finishMultiScan,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
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

// ── Cart Review (Stock OUT) ──────────────────────────────────────────────────

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
                      Text(
                        [
                          money.format(lastScanned.price) + ' each',
                          if (lastScanned.brand != null) lastScanned.brand!,
                          if (lastScanned.model != null) lastScanned.model!,
                        ].join(' · '),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),

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
                              onPressed: () => onQtyChanged(item.product, item.qty - 1),
                            ),
                            Text('${item.qty}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add, size: 20),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onQtyChanged(item.product, item.qty + 1),
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

// ── Stock In ─────────────────────────────────────────────────────────────────

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
                          Text(
                            [
                              'Current stock: ${widget.product.stock}',
                              if (widget.product.brand != null) widget.product.brand!,
                              if (widget.product.model != null) widget.product.model!,
                            ].join(' · '),
                            style: const TextStyle(color: Colors.grey),
                          ),
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

// ── Add Product (with smart multi-scan support) ──────────────────────────────

class _AddProductView extends StatefulWidget {
  final String barcode;
  final List<ScannedCode> scannedCodes;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const _AddProductView({
    required this.barcode,
    required this.scannedCodes,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  State<_AddProductView> createState() => _AddProductViewState();
}

class _AddProductViewState extends State<_AddProductView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _imei;
  late final TextEditingController _serial;
  late final TextEditingController _barcode;
  late final TextEditingController _price;
  late final TextEditingController _costPrice;
  late final TextEditingController _stock;
  late final TextEditingController _category;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    // Extract values from scanned codes
    String imeiVal = '';
    String barcodeVal = '';
    String serialVal = '';

    if (widget.scannedCodes.isNotEmpty) {
      for (final sc in widget.scannedCodes) {
        switch (sc.type) {
          case BarcodeType.imei:
            if (imeiVal.isEmpty) imeiVal = sc.value;
            break;
          case BarcodeType.ean:
            if (barcodeVal.isEmpty) barcodeVal = sc.value;
            break;
          case BarcodeType.serial:
            if (serialVal.isEmpty) serialVal = sc.value;
            break;
        }
      }
    } else if (widget.barcode.isNotEmpty) {
      final type = classifyBarcode(widget.barcode);
      switch (type) {
        case BarcodeType.imei:
          imeiVal = widget.barcode;
          break;
        case BarcodeType.ean:
          barcodeVal = widget.barcode;
          break;
        case BarcodeType.serial:
          serialVal = widget.barcode;
          break;
      }
    }

    // Initialize controllers with pre-filled values
    _name      = TextEditingController();
    _brand     = TextEditingController();
    _model     = TextEditingController();
    _imei      = TextEditingController(text: imeiVal);
    _serial    = TextEditingController(text: serialVal);
    _barcode   = TextEditingController(text: barcodeVal);
    _price     = TextEditingController();
    _costPrice = TextEditingController();
    _stock     = TextEditingController(text: '1');
    _category  = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose(); _brand.dispose(); _model.dispose();
    _imei.dispose(); _serial.dispose(); _barcode.dispose();
    _price.dispose(); _costPrice.dispose(); _stock.dispose();
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
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
        imei: _imei.text.trim().isEmpty ? null : _imei.text.trim(),
        serialNumber: _serial.text.trim().isEmpty ? null : _serial.text.trim(),
        price: double.parse(_price.text),
        costPrice: double.tryParse(_costPrice.text) ?? 0,
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
    final hasMultiScan = widget.scannedCodes.isNotEmpty;

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
                  Icon(hasMultiScan ? Icons.phone_android : Icons.search_off,
                      size: 32, color: hasMultiScan ? Colors.blue : Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New Product', style: theme.textTheme.titleLarge),
                        if (hasMultiScan)
                          Text('${widget.scannedCodes.length} barcode(s) scanned from box',
                              style: const TextStyle(fontSize: 12, color: Colors.grey))
                        else if (widget.barcode.isNotEmpty)
                          Text('Barcode: ${widget.barcode}',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ]),

                // Show scanned codes summary
                if (hasMultiScan) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Scanned Codes (auto-classified)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          ...widget.scannedCodes.map((sc) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(sc.icon, size: 16, color: sc.color),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: sc.color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(sc.label,
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sc.color)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(sc.value,
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 6),
                const Text(
                    'Fill in the product details. Scanned codes are pre-filled below.',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const Divider(height: 24),

                // Product name
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                    hintText: 'e.g. Samsung Galaxy A15',
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Brand + Model
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _brand,
                      decoration: const InputDecoration(
                        labelText: 'Brand',
                        hintText: 'e.g. Samsung',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _model,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        hintText: 'e.g. Galaxy A15',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // IMEI
                TextFormField(
                  controller: _imei,
                  decoration: InputDecoration(
                    labelText: 'IMEI',
                    prefixIcon: const Icon(Icons.phone_android, size: 20),
                    hintText: '15-digit IMEI number',
                    suffixIcon: _imei.text.isNotEmpty
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),

                // Serial number
                TextFormField(
                  controller: _serial,
                  decoration: InputDecoration(
                    labelText: 'Serial Number (S/N)',
                    prefixIcon: const Icon(Icons.tag, size: 20),
                    suffixIcon: _serial.text.isNotEmpty
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Product barcode (EAN)
                TextFormField(
                  controller: _barcode,
                  decoration: InputDecoration(
                    labelText: 'Product Barcode (EAN/UPC)',
                    prefixIcon: const Icon(Icons.qr_code, size: 20),
                    suffixIcon: _barcode.text.isNotEmpty
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Price + Cost
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(labelText: 'Sell Price *'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      controller: _costPrice,
                      decoration: const InputDecoration(labelText: 'Cost Price'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // Stock + Category
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      decoration: const InputDecoration(labelText: 'Stock Qty'),
                      keyboardType: TextInputType.number,
                      validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _category,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        hintText: 'e.g. Smartphones',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ]),

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

// ── Scanner overlay ──────────────────────────────────────────────────────────

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
