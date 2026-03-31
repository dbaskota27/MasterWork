import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/invoice.dart';
import '../models/refund.dart';
import '../services/database_service.dart';
import '../services/worker_service.dart';
import '../services/receipt_service.dart';
import 'refund_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  late Future<List<Invoice>> _future;
  final _money =
      NumberFormat.currency(symbol: AppConfig.currency, decimalDigits: 2);
  final _dateFmt = DateFormat('MMM d, y  h:mm a');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      setState(() => _future = DatabaseService.getInvoices());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Invoice>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final invoices = snap.data ?? [];
        if (invoices.isEmpty) {
          return const Center(child: Text('No invoices yet.'));
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: invoices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (ctx, i) => _InvoiceTile(
              invoice: invoices[i],
              moneyFmt: _money,
              dateFmt: _dateFmt,
              onChanged: _reload,
            ),
          ),
        );
      },
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final VoidCallback? onChanged;

  const _InvoiceTile({
    required this.invoice,
    required this.moneyFmt,
    required this.dateFmt,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('#${invoice.id}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (invoice.status != 'completed') ...[
                        const SizedBox(width: 6),
                        _statusBadge(invoice.status),
                      ],
                    ],
                  ),
                  Text(dateFmt.format(invoice.createdAt),
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (invoice.workerName != null)
                    Text(invoice.workerName!,
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (invoice.customerName != null)
                      Text(invoice.customerName!),
                    Text(
                        invoice.items
                            .map((e) => '${e.productName} x${e.qty}')
                            .join(', '),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(moneyFmt.format(invoice.customerPays),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: invoice.paymentType == 'cash'
                          ? Colors.blue.shade50
                          : Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      invoice.paymentType == 'cash' ? 'Cash' : 'QuickPay',
                      style: TextStyle(
                          fontSize: 10,
                          color: invoice.paymentType == 'cash'
                              ? Colors.blue.shade700
                              : Colors.purple.shade700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'partially_refunded':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        label = 'Partial Refund';
        break;
      case 'fully_refunded':
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        label = 'Refunded';
        break;
      default:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InvoiceDetail(
        invoice: invoice,
        moneyFmt: moneyFmt,
        dateFmt: dateFmt,
        onChanged: onChanged,
      ),
    );
  }
}

class _InvoiceDetail extends StatefulWidget {
  final Invoice invoice;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final VoidCallback? onChanged;

  const _InvoiceDetail({
    required this.invoice,
    required this.moneyFmt,
    required this.dateFmt,
    this.onChanged,
  });

  @override
  State<_InvoiceDetail> createState() => _InvoiceDetailState();
}

class _InvoiceDetailState extends State<_InvoiceDetail> {
  List<Refund> _refunds = [];

  @override
  void initState() {
    super.initState();
    _loadRefunds();
  }

  Future<void> _loadRefunds() async {
    try {
      final refunds =
          await DatabaseService.getRefunds(invoiceId: widget.invoice.id);
      if (mounted) setState(() => _refunds = refunds);
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final moneyFmt = widget.moneyFmt;
    final dateFmt = widget.dateFmt;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text('Invoice #${invoice.id}',
                          style: Theme.of(context).textTheme.titleLarge),
                      if (invoice.status != 'completed') ...[
                        const SizedBox(width: 8),
                        _InvoiceTile._statusBadge(invoice.status),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Share Receipt',
                  onPressed: () => ReceiptService.shareReceipt(invoice),
                ),
                IconButton(
                  icon: const Icon(Icons.print),
                  tooltip: 'Print',
                  onPressed: () => ReceiptService.printReceipt(invoice),
                ),
              ],
            ),
            Text(dateFmt.format(invoice.createdAt),
                style: const TextStyle(color: Colors.grey)),

            // WhatsApp/SMS buttons
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: Icon(Icons.chat, color: Colors.green.shade700, size: 18),
                  label: Text('WhatsApp',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
                  onPressed: () => ReceiptService.sendViaWhatsApp(
                    invoice,
                    phone: invoice.customerPhone,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: Icon(Icons.sms, color: Colors.blue.shade700, size: 18),
                  label: Text('SMS',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
                  onPressed: () => ReceiptService.sendViaSMS(
                    invoice,
                    phone: invoice.customerPhone,
                  ),
                ),
              ],
            ),

            const Divider(),

            if (invoice.customerName != null) ...[
              _row('Customer', invoice.customerName!),
              if (invoice.customerPhone != null)
                _row('Phone', invoice.customerPhone!),
              const SizedBox(height: 8),
            ],

            Text('Items',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            ...invoice.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${item.productName} x${item.qty}'),
                      Text(moneyFmt.format(item.total)),
                    ],
                  ),
                )),
            const Divider(),

            _row('Marked Price', moneyFmt.format(invoice.markedPrice)),
            if (invoice.discount > 0)
              _row('Discount', '- ${moneyFmt.format(invoice.discount)}',
                  valueColor: Colors.orange),
            _row('Customer Pays', moneyFmt.format(invoice.customerPays),
                bold: true, valueColor: Colors.green.shade700),
            _row(
                invoice.paymentType == 'cash'
                    ? 'Amount Received'
                    : 'Amount Transferred',
                moneyFmt.format(invoice.amountReceived)),
            if (invoice.change > 0)
              _row('Change Given', moneyFmt.format(invoice.change),
                  bold: true),

            if (invoice.pointsRedeemed > 0)
              _row('Points Redeemed', '${invoice.pointsRedeemed.toStringAsFixed(0)} pts',
                  valueColor: Colors.amber.shade700),
            if (invoice.pointsEarned > 0)
              _row('Points Earned', '+${invoice.pointsEarned.toStringAsFixed(0)} pts',
                  valueColor: Colors.blue.shade700),

            const SizedBox(height: 8),
            _row('Payment',
                invoice.paymentType == 'cash' ? 'Cash' : 'QuickPay'),

            // Refund info
            if (_refunds.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Refunds', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ...(_refunds.map((r) => Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Refund: ${moneyFmt.format(r.refundAmount)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700)),
                              if (r.createdAt != null)
                                Text(
                                    DateFormat('MMM d, h:mm a')
                                        .format(r.createdAt!),
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                          if (r.reason != null && r.reason!.isNotEmpty)
                            Text('Reason: ${r.reason}',
                                style: const TextStyle(fontSize: 12)),
                          ...r.items.map((item) => Text(
                              '  ${item.productName} x${item.qty}',
                              style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
                  ))),
            ],

            // Process Return button
            if (WorkerService.isManager &&
                invoice.status != 'fully_refunded') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.assignment_return, color: Colors.orange.shade700),
                  label: Text('Process Return',
                      style: TextStyle(color: Colors.orange.shade700)),
                  onPressed: () async {
                    Navigator.pop(context);
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => RefundScreen(invoice: invoice),
                      ),
                    );
                    if (result == true && widget.onChanged != null) {
                      widget.onChanged!();
                    }
                  },
                ),
              ),
            ],

            // Delete button
            if (WorkerService.isManager) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Delete Invoice',
                      style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete Invoice?'),
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
                      await DatabaseService.deleteInvoice(invoice.id);
                      if (context.mounted) Navigator.pop(context);
                      widget.onChanged?.call();
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: valueColor)),
        ],
      ),
    );
  }
}
