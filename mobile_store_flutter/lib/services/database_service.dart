import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/product.dart';
import '../models/customer.dart';
import '../models/invoice.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'mobile_store.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT,
            price REAL NOT NULL DEFAULT 0,
            stock INTEGER NOT NULL DEFAULT 0,
            category TEXT,
            image_url TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE invoices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_name TEXT,
            customer_phone TEXT,
            items TEXT NOT NULL,
            marked_price REAL NOT NULL DEFAULT 0,
            discount REAL NOT NULL DEFAULT 0,
            customer_pays REAL NOT NULL DEFAULT 0,
            amount_received REAL NOT NULL DEFAULT 0,
            change_given REAL NOT NULL DEFAULT 0,
            payment_type TEXT NOT NULL DEFAULT 'cash',
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // ── Products ──────────────────────────────────────────────────────────────

  static Future<List<Product>> getProducts() async {
    final database = await db;
    final rows = await database.query('products', orderBy: 'name ASC');
    return rows.map(_productFromRow).toList();
  }

  static Future<Product?> getProductByBarcode(String barcode) async {
    final database = await db;
    final rows = await database.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.first);
  }

  static Future<void> addProduct(Product p) async {
    final database = await db;
    await database.insert('products', {
      'name': p.name,
      'barcode': p.barcode,
      'price': p.price,
      'stock': p.stock,
      'category': p.category,
      'image_url': p.imageUrl,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> updateProduct(int id, Map<String, dynamic> data) async {
    final database = await db;
    await database.update('products', data, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteProduct(int id) async {
    final database = await db;
    await database.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> adjustStock(int productId, int delta) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE products SET stock = stock + ? WHERE id = ?',
      [delta, productId],
    );
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  static Future<List<Customer>> getCustomers() async {
    final database = await db;
    final rows = await database.query('customers', orderBy: 'name ASC');
    return rows.map(_customerFromRow).toList();
  }

  static Future<Customer> addCustomer(Customer c) async {
    final database = await db;
    final id = await database.insert('customers', {
      'name': c.name,
      'phone': c.phone,
      'email': c.email,
      'created_at': DateTime.now().toIso8601String(),
    });
    return Customer(id: id, name: c.name, phone: c.phone, email: c.email);
  }

  static Future<void> updateCustomer(int id, Map<String, dynamic> data) async {
    final database = await db;
    await database.update('customers', data, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteCustomer(int id) async {
    final database = await db;
    await database.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  // ── Invoices ──────────────────────────────────────────────────────────────

  static Future<List<Invoice>> getInvoices() async {
    final database = await db;
    final rows = await database.query('invoices', orderBy: 'created_at DESC');
    return rows.map(_invoiceFromRow).toList();
  }

  static Future<Invoice> createInvoice({
    String? customerName,
    String? customerPhone,
    required List<InvoiceItem> items,
    required double markedPrice,
    required double discount,
    required double customerPays,
    required double amountReceived,
    required double change,
    required String paymentType,
  }) async {
    final database = await db;
    final now = DateTime.now().toIso8601String();
    final itemsJson = jsonEncode(items.map((e) => e.toJson()).toList());

    final id = await database.insert('invoices', {
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'items': itemsJson,
      'marked_price': markedPrice,
      'discount': discount,
      'customer_pays': customerPays,
      'amount_received': amountReceived,
      'change_given': change,
      'payment_type': paymentType,
      'created_at': now,
    });

    return Invoice(
      id: id,
      customerName: customerName,
      customerPhone: customerPhone,
      items: items,
      markedPrice: markedPrice,
      discount: discount,
      customerPays: customerPays,
      amountReceived: amountReceived,
      change: change,
      paymentType: paymentType,
      createdAt: DateTime.parse(now),
    );
  }

  static Future<void> deleteInvoice(int id) async {
    final database = await db;
    await database.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSummary({
    DateTime? from,
    DateTime? to,
  }) async {
    final invoices = await getInvoices();
    final filtered = invoices.where((inv) {
      if (from != null && inv.createdAt.isBefore(from)) return false;
      if (to != null && inv.createdAt.isAfter(to.add(const Duration(days: 1)))) return false;
      return true;
    }).toList();

    double totalRevenue = 0;
    double totalDiscount = 0;
    Map<String, int> productCounts = {};

    for (final inv in filtered) {
      totalRevenue += inv.customerPays;
      totalDiscount += inv.discount;
      for (final item in inv.items) {
        productCounts[item.productName] =
            (productCounts[item.productName] ?? 0) + item.qty;
      }
    }

    return {
      'total_revenue': totalRevenue,
      'total_discount': totalDiscount,
      'total_transactions': filtered.length,
      'invoices': filtered,
      'product_counts': productCounts,
    };
  }

  // ── Backup & Restore ──────────────────────────────────────────────────────

  /// Export entire database as a JSON string.
  static Future<String> exportJson() async {
    final products = await getProducts();
    final customers = await getCustomers();
    final invoices = await getInvoices();

    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'version': 1,
      'products': products.map((p) => {
        'id': p.id,
        'name': p.name,
        'barcode': p.barcode,
        'price': p.price,
        'stock': p.stock,
        'category': p.category,
        'image_url': p.imageUrl,
        'created_at': p.createdAt?.toIso8601String(),
      }).toList(),
      'customers': customers.map((c) => {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'email': c.email,
        'created_at': c.createdAt?.toIso8601String(),
      }).toList(),
      'invoices': invoices.map((inv) => {
        'id': inv.id,
        'customer_name': inv.customerName,
        'customer_phone': inv.customerPhone,
        'items': inv.items.map((i) => i.toJson()).toList(),
        'marked_price': inv.markedPrice,
        'discount': inv.discount,
        'customer_pays': inv.customerPays,
        'amount_received': inv.amountReceived,
        'change_given': inv.change,
        'payment_type': inv.paymentType,
        'created_at': inv.createdAt.toIso8601String(),
      }).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Import from a JSON string (merges — does not wipe existing data).
  static Future<Map<String, int>> importJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final database = await db;

    int addedProducts = 0, addedCustomers = 0, addedInvoices = 0;

    // Products — insert only if barcode not already present
    for (final row in (data['products'] as List? ?? [])) {
      final barcode = row['barcode'] as String?;
      if (barcode != null) {
        final existing = await database.query('products',
            where: 'barcode = ?', whereArgs: [barcode], limit: 1);
        if (existing.isNotEmpty) continue;
      }
      await database.insert('products', {
        'name': row['name'],
        'barcode': row['barcode'],
        'price': row['price'],
        'stock': row['stock'],
        'category': row['category'],
        'image_url': row['image_url'],
        'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
      });
      addedProducts++;
    }

    // Customers — insert only if phone not already present
    for (final row in (data['customers'] as List? ?? [])) {
      final phone = row['phone'] as String?;
      if (phone != null) {
        final existing = await database.query('customers',
            where: 'phone = ?', whereArgs: [phone], limit: 1);
        if (existing.isNotEmpty) continue;
      }
      await database.insert('customers', {
        'name': row['name'],
        'phone': row['phone'],
        'email': row['email'],
        'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
      });
      addedCustomers++;
    }

    // Invoices — always import (different timestamps = different sales)
    for (final row in (data['invoices'] as List? ?? [])) {
      await database.insert('invoices', {
        'customer_name': row['customer_name'],
        'customer_phone': row['customer_phone'],
        'items': jsonEncode(row['items']),
        'marked_price': row['marked_price'],
        'discount': row['discount'],
        'customer_pays': row['customer_pays'],
        'amount_received': row['amount_received'],
        'change_given': row['change_given'],
        'payment_type': row['payment_type'] ?? 'cash',
        'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
      });
      addedInvoices++;
    }

    return {
      'products': addedProducts,
      'customers': addedCustomers,
      'invoices': addedInvoices,
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Product _productFromRow(Map<String, dynamic> row) => Product(
        id: row['id'] as int,
        name: row['name'] as String,
        barcode: row['barcode'] as String?,
        price: (row['price'] as num).toDouble(),
        stock: (row['stock'] as num).toInt(),
        category: row['category'] as String?,
        imageUrl: row['image_url'] as String?,
        createdAt: row['created_at'] != null
            ? DateTime.tryParse(row['created_at'] as String)
            : null,
      );

  static Customer _customerFromRow(Map<String, dynamic> row) => Customer(
        id: row['id'] as int,
        name: row['name'] as String,
        phone: row['phone'] as String?,
        email: row['email'] as String?,
        createdAt: row['created_at'] != null
            ? DateTime.tryParse(row['created_at'] as String)
            : null,
      );

  static Invoice _invoiceFromRow(Map<String, dynamic> row) {
    final itemsRaw = jsonDecode(row['items'] as String) as List;
    final items =
        itemsRaw.map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>)).toList();
    return Invoice(
      id: row['id'] as int,
      customerName: row['customer_name'] as String?,
      customerPhone: row['customer_phone'] as String?,
      items: items,
      markedPrice: (row['marked_price'] as num).toDouble(),
      discount: (row['discount'] as num).toDouble(),
      customerPays: (row['customer_pays'] as num).toDouble(),
      amountReceived: (row['amount_received'] as num).toDouble(),
      change: (row['change_given'] as num).toDouble(),
      paymentType: row['payment_type'] as String? ?? 'cash',
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
