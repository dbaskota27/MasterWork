class Expense {
  final int id;
  final String category;
  final double amount;
  final String? description;
  final DateTime date;
  final String? workerName;
  final DateTime? createdAt;

  const Expense({
    required this.id,
    this.category = 'other',
    required this.amount,
    this.description,
    required this.date,
    this.workerName,
    this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as int,
        category: j['category'] as String? ?? 'other',
        amount: (j['amount'] as num).toDouble(),
        description: j['description'] as String?,
        date: DateTime.parse(j['date'] as String),
        workerName: j['worker_name'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toInsert() => {
        'category': category,
        'amount': amount,
        'description': description,
        'date': date.toIso8601String().split('T').first,
        'worker_name': workerName,
      };
}
