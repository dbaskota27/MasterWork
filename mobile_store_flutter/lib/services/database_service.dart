import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import 'auth_service.dart';

class DatabaseService {
  static SupabaseClient get _db => Supabase.instance.client;
  static String get _storeId {
    final id = AuthService.storeId;
    if (id == null) throw Exception('No store linked. Please set up your store first.');
    return id;
  }

  // ── Products ──────────────────────────────────────────────────────────────

  static Future<List<Product>> getProducts() async {
    final res = await _db
        .from('products')
        .select()
        .eq('store_id', _storeId)
        .order('name', ascending: true);
    return (res as List).map((e) => Product.fromJson(e)).toList();
  }

  static Future<Product?> getProductByBarcode(String barcode) async {
    final res = await _db
        .from('products')
        .select()
        .eq('store_id', _storeId)
        .eq('barcode', barcode)
        .maybeSingle();
    if (res == null) return null;
    return Product.fromJson(res);
  }

  static Future<void> addProduct(Product p) async {
    await _db.from('products').insert({
      'store_id': _storeId,
      ...p.toInsert(),
    });
  }

  static Future<void> updateProduct(int id, Map<String, dynamic> data) async {
    await _db.from('products').update(data).eq('id', id);
  }

  static Future<void> deleteProduct(int id) async {
    await _db.from('products').delete().eq('id', id);
  }

  static Future<void> adjustStock(int productId, int delta) async {
    final res = await _db
        .from('products')
        .select('stock')
        .eq('id', productId)
        .single();
    final current = (res['stock'] as num).toInt();
    await _db
        .from('products')
        .update({'stock': current + delta}).eq('id', productId);
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  static Future<List<Customer>> getCustomers() async {
    final res = await _db
        .from('customers')
        .select()
        .eq('store_id', _storeId)
        .order('name', ascending: true);
    return (res as List).map((e) => Customer.fromJson(e)).toList();
  }

  static Future<Customer> addCustomer(Customer c) async {
    final res = await _db.from('customers').insert({
      'store_id': _storeId,
      ...c.toInsert(),
    }).select().single();
    return Customer.fromJson(res);
  }

  static Future<void> updateCustomer(int id, Map<String, dynamic> data) async {
    await _db.from('customers').update(data).eq('id', id);
  }

  static Future<void> deleteCustomer(int id) async {
    await _db.from('customers').delete().eq('id', id);
  }

  // ── Invoices ──────────────────────────────────────────────────────────────

  static Future<List<Invoice>> getInvoices() async {
    final res = await _db
        .from('invoices')
        .select()
        .eq('store_id', _storeId)
        .order('created_at', ascending: false);
    return (res as List).map((e) => Invoice.fromJson(e)).toList();
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
    final res = await _db.from('invoices').insert({
      'store_id':        _storeId,
      'customer_name':   customerName,
      'customer_phone':  customerPhone,
      'items':           items.map((e) => e.toJson()).toList(),
      'marked_price':    markedPrice,
      'discount':        discount,
      'customer_pays':   customerPays,
      'amount_received': amountReceived,
      'change_given':    change,
      'payment_type':    paymentType,
    }).select().single();
    return Invoice.fromJson(res);
  }

  static Future<void> deleteInvoice(int id) async {
    await _db.from('invoices').delete().eq('id', id);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSummary({
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _db.from('invoices').select().eq('store_id', _storeId);
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());

    final rows = await query;
    final invoices = (rows as List).map((e) => Invoice.fromJson(e)).toList();

    double totalRevenue = 0;
    double totalDiscount = 0;
    Map<String, int> productCounts = {};

    for (final inv in invoices) {
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
      'total_transactions': invoices.length,
      'invoices': invoices,
      'product_counts': productCounts,
    };
  }

  // ── Store Info ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getStoreInfo() async {
    final res = await _db
        .from('stores')
        .select()
        .eq('id', _storeId)
        .single();
    return res;
  }

  static Future<void> updateStoreInfo(Map<String, dynamic> data) async {
    await _db.from('stores').update(data).eq('id', _storeId);
  }

  // ── Export / Import ────────────────────────────────────────────────────────

  static Future<String> exportJson() async {
    final products = await getProducts();
    final customers = await getCustomers();
    final invoices = await getInvoices();

    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'version': 2,
      'products': products.map((p) => {
        'name': p.name, 'barcode': p.barcode, 'price': p.price,
        'stock': p.stock, 'category': p.category,
        'created_at': p.createdAt?.toIso8601String(),
      }).toList(),
      'customers': customers.map((c) => {
        'name': c.name, 'phone': c.phone, 'email': c.email,
        'created_at': c.createdAt?.toIso8601String(),
      }).toList(),
      'invoices': invoices.map((inv) => {
        'customer_name': inv.customerName, 'customer_phone': inv.customerPhone,
        'items': inv.items.map((i) => i.toJson()).toList(),
        'marked_price': inv.markedPrice, 'discount': inv.discount,
        'customer_pays': inv.customerPays, 'amount_received': inv.amountReceived,
        'change_given': inv.change, 'payment_type': inv.paymentType,
        'created_at': inv.createdAt.toIso8601String(),
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static Future<Map<String, int>> importJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    int addedP = 0, addedC = 0, addedI = 0;

    for (final row in (data['products'] as List? ?? [])) {
      await _db.from('products').insert({
        'store_id': _storeId,
        'name': row['name'], 'barcode': row['barcode'],
        'price': row['price'], 'stock': row['stock'],
        'category': row['category'],
      });
      addedP++;
    }

    for (final row in (data['customers'] as List? ?? [])) {
      await _db.from('customers').insert({
        'store_id': _storeId,
        'name': row['name'], 'phone': row['phone'], 'email': row['email'],
      });
      addedC++;
    }

    for (final row in (data['invoices'] as List? ?? [])) {
      await _db.from('invoices').insert({
        'store_id': _storeId,
        'customer_name': row['customer_name'],
        'customer_phone': row['customer_phone'],
        'items': row['items'],
        'marked_price': row['marked_price'],
        'discount': row['discount'],
        'customer_pays': row['customer_pays'],
        'amount_received': row['amount_received'],
        'change_given': row['change_given'],
        'payment_type': row['payment_type'] ?? 'cash',
      });
      addedI++;
    }

    return {'products': addedP, 'customers': addedC, 'invoices': addedI};
  }
}
