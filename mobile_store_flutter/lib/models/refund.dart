import 'invoice.dart';

class Refund {
  final int id;
  final int invoiceId;
  final String? workerName;
  final List<InvoiceItem> items;
  final double refundAmount;
  final String? reason;
  final DateTime? createdAt;

  const Refund({
    required this.id,
    required this.invoiceId,
    this.workerName,
    required this.items,
    this.refundAmount = 0,
    this.reason,
    this.createdAt,
  });

  factory Refund.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    List<InvoiceItem> items = [];
    if (rawItems is List) {
      items = rawItems
          .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return Refund(
      id: j['id'] as int,
      invoiceId: (j['invoice_id'] as num).toInt(),
      workerName: j['worker_name'] as String?,
      items: items,
      refundAmount: (j['refund_amount'] as num?)?.toDouble() ?? 0,
      reason: j['reason'] as String?,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'] as String)
          : null,
    );
  }
}
