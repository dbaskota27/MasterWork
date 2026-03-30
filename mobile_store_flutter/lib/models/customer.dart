class Customer {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final double pointsBalance;
  final DateTime? createdAt;

  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.pointsBalance = 0,
    this.createdAt,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as int,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        pointsBalance: (j['points_balance'] as num?)?.toDouble() ?? 0,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'phone': phone,
        'email': email,
      };
}
