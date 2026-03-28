class Product {
  final int id;
  final String name;
  final String? barcode;
  final double price;
  final int stock;
  final String? category;
  final String? imageUrl;
  final DateTime? createdAt;

  const Product({
    required this.id,
    required this.name,
    this.barcode,
    required this.price,
    required this.stock,
    this.category,
    this.imageUrl,
    this.createdAt,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as int,
        name: j['name'] as String,
        barcode: j['barcode'] as String?,
        price: (j['price'] as num).toDouble(),
        stock: (j['stock'] as num).toInt(),
        category: j['category'] as String?,
        imageUrl: j['image_url'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'barcode': barcode,
        'price': price,
        'stock': stock,
        'category': category,
        'image_url': imageUrl,
      };

  Product copyWith({
    String? name,
    String? barcode,
    double? price,
    int? stock,
    String? category,
    String? imageUrl,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        price: price ?? this.price,
        stock: stock ?? this.stock,
        category: category ?? this.category,
        imageUrl: imageUrl ?? this.imageUrl,
        createdAt: createdAt,
      );
}
