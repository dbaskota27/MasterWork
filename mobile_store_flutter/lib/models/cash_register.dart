class CashRegister {
  final int id;
  final String? workerName;
  final DateTime date;
  final double openingBalance;
  final double? closingBalance;
  final double cashIn;
  final double cashOut;
  final String? notes;
  final String status;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final DateTime? createdAt;

  const CashRegister({
    required this.id,
    this.workerName,
    required this.date,
    this.openingBalance = 0,
    this.closingBalance,
    this.cashIn = 0,
    this.cashOut = 0,
    this.notes,
    this.status = 'open',
    this.openedAt,
    this.closedAt,
    this.createdAt,
  });

  double get expectedBalance => openingBalance + cashIn - cashOut;

  factory CashRegister.fromJson(Map<String, dynamic> j) => CashRegister(
        id: j['id'] as int,
        workerName: j['worker_name'] as String?,
        date: DateTime.parse(j['date'] as String),
        openingBalance: (j['opening_balance'] as num?)?.toDouble() ?? 0,
        closingBalance: (j['closing_balance'] as num?)?.toDouble(),
        cashIn: (j['cash_in'] as num?)?.toDouble() ?? 0,
        cashOut: (j['cash_out'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] as String?,
        status: j['status'] as String? ?? 'open',
        openedAt: j['opened_at'] != null
            ? DateTime.tryParse(j['opened_at'] as String)
            : null,
        closedAt: j['closed_at'] != null
            ? DateTime.tryParse(j['closed_at'] as String)
            : null,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );
}

class CashAdjustment {
  final int id;
  final int registerId;
  final String type;
  final double amount;
  final String? reason;
  final String? workerName;
  final DateTime? createdAt;

  const CashAdjustment({
    required this.id,
    required this.registerId,
    required this.type,
    required this.amount,
    this.reason,
    this.workerName,
    this.createdAt,
  });

  factory CashAdjustment.fromJson(Map<String, dynamic> j) => CashAdjustment(
        id: j['id'] as int,
        registerId: (j['register_id'] as num).toInt(),
        type: j['type'] as String,
        amount: (j['amount'] as num).toDouble(),
        reason: j['reason'] as String?,
        workerName: j['worker_name'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );
}
