class InvoiceItem {
  final String productName;
  final int qty;
  final double unitPrice;
  final double costPrice;

  const InvoiceItem({
    required this.productName,
    required this.qty,
    required this.unitPrice,
    this.costPrice = 0,
  });

  double get total => qty * unitPrice;

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        productName: j['product_name'] as String,
        qty: (j['qty'] as num).toInt(),
        unitPrice: (j['unit_price'] as num).toDouble(),
        costPrice: (j['cost_price'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'product_name': productName,
        'qty': qty,
        'unit_price': unitPrice,
        'cost_price': costPrice,
      };
}

class Invoice {
  final int id;
  final String? workerName;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final List<InvoiceItem> items;
  final double markedPrice;
  final double discount;
  final double customerPays;
  final double amountReceived;
  final double change;
  final String paymentType;
  final double pointsEarned;
  final double pointsRedeemed;
  final String status;
  final DateTime createdAt;

  const Invoice({
    required this.id,
    this.workerName,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.items,
    required this.markedPrice,
    required this.discount,
    required this.customerPays,
    required this.amountReceived,
    required this.change,
    required this.paymentType,
    this.pointsEarned = 0,
    this.pointsRedeemed = 0,
    this.status = 'completed',
    required this.createdAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    List<InvoiceItem> items = [];
    if (rawItems is List) {
      items = rawItems
          .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return Invoice(
      id: j['id'] as int,
      workerName: j['worker_name'] as String?,
      customerId: j['customer_id'] as int?,
      customerName: j['customer_name'] as String?,
      customerPhone: j['customer_phone'] as String?,
      items: items,
      markedPrice: (j['marked_price'] as num?)?.toDouble() ?? 0,
      discount: (j['discount'] as num?)?.toDouble() ?? 0,
      customerPays: (j['customer_pays'] as num?)?.toDouble() ?? 0,
      amountReceived: (j['amount_received'] as num?)?.toDouble() ?? 0,
      change: (j['change_given'] as num?)?.toDouble() ?? 0,
      paymentType: j['payment_type'] as String? ?? 'cash',
      pointsEarned: (j['points_earned'] as num?)?.toDouble() ?? 0,
      pointsRedeemed: (j['points_redeemed'] as num?)?.toDouble() ?? 0,
      status: j['status'] as String? ?? 'completed',
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }
}
