class Product {
  final int id;
  final String name;
  final String? barcode;
  final String? brand;
  final String? model;
  final String? imei;
  final String? serialNumber;
  final double price;
  final double costPrice;
  final int stock;
  final int lowStockThreshold;
  final String? category;
  final String? imageUrl;
  final DateTime? createdAt;

  const Product({
    required this.id,
    required this.name,
    this.barcode,
    this.brand,
    this.model,
    this.imei,
    this.serialNumber,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    this.lowStockThreshold = 5,
    this.category,
    this.imageUrl,
    this.createdAt,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as int,
        name: j['name'] as String,
        barcode: j['barcode'] as String?,
        brand: j['brand'] as String?,
        model: j['model'] as String?,
        imei: j['imei'] as String?,
        serialNumber: j['serial_number'] as String?,
        price: (j['price'] as num).toDouble(),
        costPrice: (j['cost_price'] as num?)?.toDouble() ?? 0,
        stock: (j['stock'] as num).toInt(),
        lowStockThreshold: (j['low_stock_threshold'] as num?)?.toInt() ?? 5,
        category: j['category'] as String?,
        imageUrl: j['image_url'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'barcode': barcode,
        'brand': brand,
        'model': model,
        'imei': imei,
        'serial_number': serialNumber,
        'price': price,
        'cost_price': costPrice,
        'stock': stock,
        'low_stock_threshold': lowStockThreshold,
        'category': category,
        'image_url': imageUrl,
      };

  Product copyWith({
    String? name,
    String? barcode,
    String? brand,
    String? model,
    String? imei,
    String? serialNumber,
    double? price,
    double? costPrice,
    int? stock,
    int? lowStockThreshold,
    String? category,
    String? imageUrl,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        brand: brand ?? this.brand,
        model: model ?? this.model,
        imei: imei ?? this.imei,
        serialNumber: serialNumber ?? this.serialNumber,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        stock: stock ?? this.stock,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        category: category ?? this.category,
        imageUrl: imageUrl ?? this.imageUrl,
        createdAt: createdAt,
      );
}
