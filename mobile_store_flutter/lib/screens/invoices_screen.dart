import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import '../services/worker_service.dart';
import '../services/receipt_service.dart';

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
              onDeleted: WorkerService.isManager ? _reload : null,
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
  final VoidCallback? onDeleted;

  const _InvoiceTile({
    required this.invoice,
    required this.moneyFmt,
    required this.dateFmt,
    this.onDeleted,
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
                  Text('#${invoice.id}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
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
                            .map((e) => '${e.productName} ×${e.qty}')
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

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InvoiceDetail(
        invoice: invoice,
        moneyFmt: moneyFmt,
        dateFmt: dateFmt,
        onDeleted: onDeleted,
      ),
    );
  }
}

class _InvoiceDetail extends StatelessWidget {
  final Invoice invoice;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final VoidCallback? onDeleted;

  const _InvoiceDetail({
    required this.invoice,
    required this.moneyFmt,
    required this.dateFmt,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
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
                Text('Invoice #${invoice.id}',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
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
                      Text('${item.productName} ×${item.qty}'),
                      Text(moneyFmt.format(item.total)),
                    ],
                  ),
                )),
            const Divider(),

            _row('Marked Price', moneyFmt.format(invoice.markedPrice)),
            if (invoice.discount > 0)
              _row('Discount', '− ${moneyFmt.format(invoice.discount)}',
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

            const SizedBox(height: 8),
            _row('Payment',
                invoice.paymentType == 'cash' ? 'Cash' : 'QuickPay'),

            if (onDeleted != null) ...[
              const SizedBox(height: 20),
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
                      onDeleted!();
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
