import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/invoice.dart';

class DatabaseService {
  static SupabaseClient get _db => Supabase.instance.client;

  // ── Products ──────────────────────────────────────────────────────────────

  static Future<List<Product>> getProducts() async {
    final res = await _db
        .from('products')
        .select()
        .order('name', ascending: true);
    return (res as List).map((e) => Product.fromJson(e)).toList();
  }

  static Future<Product?> getProductByBarcode(String barcode) async {
    final res = await _db
        .from('products')
        .select()
        .eq('barcode', barcode)
        .maybeSingle();
    if (res == null) return null;
    return Product.fromJson(res);
  }

  static Future<void> addProduct(Product p) async {
    await _db.from('products').insert(p.toInsert());
  }

  static Future<void> updateProduct(int id, Map<String, dynamic> data) async {
    await _db.from('products').update(data).eq('id', id);
  }

  static Future<void> deleteProduct(int id) async {
    await _db.from('products').delete().eq('id', id);
  }

  static Future<void> adjustStock(int productId, int delta) async {
    // Fetch current stock then update
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
        .order('name', ascending: true);
    return (res as List).map((e) => Customer.fromJson(e)).toList();
  }

  static Future<Customer> addCustomer(Customer c) async {
    final res =
        await _db.from('customers').insert(c.toInsert()).select().single();
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
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'items': items.map((e) => e.toJson()).toList(),
      'marked_price': markedPrice,
      'discount': discount,
      'customer_pays': customerPays,
      'amount_received': amountReceived,
      'change_given': change,
      'payment_type': paymentType,
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
    var query = _db.from('invoices').select();
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());

    final rows = await query;
    final invoices = (rows as List).map((e) => Invoice.fromJson(e)).toList();

    double totalRevenue = 0;
    double totalDiscount = 0;
    int totalTransactions = invoices.length;
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
      'total_transactions': totalTransactions,
      'invoices': invoices,
      'product_counts': productCounts,
    };
  }
}
