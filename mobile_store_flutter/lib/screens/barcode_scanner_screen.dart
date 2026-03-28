import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../widgets/checkout_form.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  bool _scanning = true;
  bool _processing = false;
  Product? _foundProduct;
  String? _scannedBarcode;

  // Stock In / Out mode
  String _mode = 'out'; // 'in' | 'out'

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _scanning = true;
      _processing = false;
      _foundProduct = null;
      _scannedBarcode = null;
    });
    _controller.start();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning || _processing) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() {
      _processing = true;
      _scanning = false;
    });
    await _controller.stop();

    final product = await DatabaseService.getProductByBarcode(code);
    setState(() {
      _scannedBarcode = code;
      _foundProduct = product;
      _processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _scanning ? _buildScanner() : _buildResult(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),
        // Mode toggle at top
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Card(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ModeButton(
                        label: 'Stock OUT (Sale)',
                        selected: _mode == 'out',
                        onTap: () => setState(() => _mode = 'out')),
                    const SizedBox(width: 8),
                    _ModeButton(
                        label: 'Stock IN',
                        selected: _mode == 'in',
                        onTap: () => setState(() => _mode = 'in')),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Overlay frame
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _FramePainter()),
          ),
        ),
        // Hint text at bottom
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              _mode == 'out'
                  ? 'Scan product barcode to sell'
                  : 'Scan product barcode to add stock',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
            ),
          ),
        ),
        if (_processing)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _buildResult() {
    if (_foundProduct == null) {
      return _UnknownBarcodeView(
        barcode: _scannedBarcode ?? '',
        onReset: _reset,
      );
    }

    if (_mode == 'in') {
      return _StockInView(
        product: _foundProduct!,
        onDone: _reset,
      );
    }

    return CheckoutForm(
      product: _foundProduct!,
      onDone: _reset,
    );
  }
}

// ── Unknown barcode ───────────────────────────────────────────────────────────

class _UnknownBarcodeView extends StatelessWidget {
  final String barcode;
  final VoidCallback onReset;
  const _UnknownBarcodeView({required this.barcode, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.orange),
            const SizedBox(height: 12),
            Text('Barcode not found',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(barcode,
                style: const TextStyle(
                    fontFamily: 'monospace', color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add to Inventory'),
              onPressed: () {
                // Navigate to inventory tab with pre-filled barcode
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Again'),
              onPressed: onReset,
            ),
          ],
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Stock updated!',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Added $_qty unit(s) to ${widget.product.name}'),
            const SizedBox(height: 24),
            FilledButton(onPressed: widget.onDone, child: const Text('Scan Another')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text('Stock In', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.product.name,
                            style: theme.textTheme.titleMedium),
                        Text(
                            'Current stock: ${widget.product.stock}',
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Quantity to add:', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filled(
                onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('$_qty',
                    style: theme.textTheme.headlineMedium),
              ),
              IconButton.filled(
                onPressed: () => setState(() => _qty++),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 32),
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
            ],
          ),
        ],
      ),
    );
  }
}

// ── Scanner overlay frame ─────────────────────────────────────────────────────

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const w = 240.0;
    const h = 160.0;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

    // Dim overlay
    final dimPaint = Paint()..color = Colors.black.withOpacity(0.4);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(RRect.fromRectXY(rect, 8, 8)),
      ),
      dimPaint,
    );

    // Corner lines
    const cl = 24.0;
    final lp = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final corners = [
      [rect.topLeft, const Offset(cl, 0), const Offset(0, cl)],
      [rect.topRight, const Offset(-cl, 0), const Offset(0, cl)],
      [rect.bottomLeft, const Offset(cl, 0), const Offset(0, -cl)],
      [rect.bottomRight, const Offset(-cl, 0), const Offset(0, -cl)],
    ];
    for (final c in corners) {
      final origin = c[0] as Offset;
      canvas.drawLine(origin, origin + (c[1] as Offset), lp);
      canvas.drawLine(origin, origin + (c[2] as Offset), lp);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Mode button ───────────────────────────────────────────────────────────────

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white54),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }
}
