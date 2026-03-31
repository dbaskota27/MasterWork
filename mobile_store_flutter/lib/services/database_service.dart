import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/expense.dart';
import '../models/refund.dart';
import '../models/cash_register.dart';
import 'auth_service.dart';
import 'worker_service.dart';

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

  static Future<List<Product>> getLowStockProducts() async {
    final products = await getProducts();
    return products.where((p) => p.stock <= p.lowStockThreshold).toList();
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
    int? customerId,
    String? customerName,
    String? customerPhone,
    required List<InvoiceItem> items,
    required double markedPrice,
    required double discount,
    required double customerPays,
    required double amountReceived,
    required double change,
    required String paymentType,
    double pointsEarned = 0,
    double pointsRedeemed = 0,
    String status = 'completed',
  }) async {
    final res = await _db.from('invoices').insert({
      'store_id':        _storeId,
      'worker_name':     WorkerService.workerName,
      'customer_id':     customerId,
      'customer_name':   customerName,
      'customer_phone':  customerPhone,
      'items':           items.map((e) => e.toJson()).toList(),
      'marked_price':    markedPrice,
      'discount':        discount,
      'customer_pays':   customerPays,
      'amount_received': amountReceived,
      'change_given':    change,
      'payment_type':    paymentType,
      'points_earned':   pointsEarned,
      'points_redeemed': pointsRedeemed,
      'status':          status,
    }).select().single();
    return Invoice.fromJson(res);
  }

  /// Add points to a customer's balance.
  static Future<void> addPoints(int customerId, double points) async {
    final res = await _db.from('customers').select('points_balance').eq('id', customerId).single();
    final current = (res['points_balance'] as num).toDouble();
    await _db.from('customers').update({'points_balance': current + points}).eq('id', customerId);
  }

  /// Deduct points from a customer's balance.
  static Future<void> deductPoints(int customerId, double points) async {
    final res = await _db.from('customers').select('points_balance').eq('id', customerId).single();
    final current = (res['points_balance'] as num).toDouble();
    final newBal = (current - points).clamp(0, double.infinity);
    await _db.from('customers').update({'points_balance': newBal}).eq('id', customerId);
  }

  /// Get store's points configuration.
  static Future<Map<String, double>> getPointsConfig() async {
    final info = await getStoreInfo();
    return {
      'points_per_unit': (info['points_per_unit'] as num?)?.toDouble() ?? 1,
      'points_value': (info['points_value'] as num?)?.toDouble() ?? 0.01,
    };
  }

  static Future<void> deleteInvoice(int id) async {
    await _db.from('invoices').delete().eq('id', id);
  }

  static Future<void> updateInvoiceStatus(int id, String status) async {
    await _db.from('invoices').update({'status': status}).eq('id', id);
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
    double totalCost = 0;
    Map<String, int> productCounts = {};

    for (final inv in invoices) {
      totalRevenue += inv.customerPays;
      totalDiscount += inv.discount;
      for (final item in inv.items) {
        productCounts[item.productName] =
            (productCounts[item.productName] ?? 0) + item.qty;
        totalCost += item.costPrice * item.qty;
      }
    }

    final totalProfit = totalRevenue - totalCost;

    return {
      'total_revenue': totalRevenue,
      'total_discount': totalDiscount,
      'total_cost': totalCost,
      'total_profit': totalProfit,
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

  // ── Expenses ──────────────────────────────────────────────────────────────

  static Future<List<Expense>> getExpenses({DateTime? from, DateTime? to}) async {
    var query = _db.from('expenses').select().eq('store_id', _storeId);
    if (from != null) query = query.gte('date', from.toIso8601String().split('T').first);
    if (to != null) query = query.lte('date', to.toIso8601String().split('T').first);
    final res = await query.order('date', ascending: false);
    return (res as List).map((e) => Expense.fromJson(e)).toList();
  }

  static Future<void> addExpense(Expense e) async {
    await _db.from('expenses').insert({
      'store_id': _storeId,
      ...e.toInsert(),
    });
  }

  static Future<void> updateExpense(int id, Map<String, dynamic> data) async {
    await _db.from('expenses').update(data).eq('id', id);
  }

  static Future<void> deleteExpense(int id) async {
    await _db.from('expenses').delete().eq('id', id);
  }

  // ── Cash Register ─────────────────────────────────────────────────────────

  static Future<CashRegister?> getOpenRegister() async {
    final res = await _db
        .from('cash_register')
        .select()
        .eq('store_id', _storeId)
        .eq('status', 'open')
        .order('opened_at', ascending: false)
        .maybeSingle();
    if (res == null) return null;
    return CashRegister.fromJson(res);
  }

  static Future<CashRegister> openRegister(double openingBalance) async {
    final res = await _db.from('cash_register').insert({
      'store_id': _storeId,
      'worker_name': WorkerService.workerName,
      'opening_balance': openingBalance,
    }).select().single();
    return CashRegister.fromJson(res);
  }

  static Future<void> closeRegister(int id, double closingBalance, {String? notes}) async {
    await _db.from('cash_register').update({
      'closing_balance': closingBalance,
      'status': 'closed',
      'closed_at': DateTime.now().toIso8601String(),
      'notes': notes,
    }).eq('id', id);
  }

  static Future<void> addCashAdjustment({
    required int registerId,
    required String type,
    required double amount,
    String? reason,
  }) async {
    await _db.from('cash_adjustments').insert({
      'register_id': registerId,
      'store_id': _storeId,
      'type': type,
      'amount': amount,
      'reason': reason,
      'worker_name': WorkerService.workerName,
    });

    // Update the register totals
    final reg = await _db.from('cash_register').select().eq('id', registerId).single();
    if (type == 'in') {
      final current = (reg['cash_in'] as num).toDouble();
      await _db.from('cash_register').update({'cash_in': current + amount}).eq('id', registerId);
    } else {
      final current = (reg['cash_out'] as num).toDouble();
      await _db.from('cash_register').update({'cash_out': current + amount}).eq('id', registerId);
    }
  }

  static Future<List<CashAdjustment>> getCashAdjustments(int registerId) async {
    final res = await _db
        .from('cash_adjustments')
        .select()
        .eq('register_id', registerId)
        .order('created_at', ascending: false);
    return (res as List).map((e) => CashAdjustment.fromJson(e)).toList();
  }

  // ── Refunds ───────────────────────────────────────────────────────────────

  static Future<Refund> createRefund({
    required int invoiceId,
    required List<InvoiceItem> items,
    required double refundAmount,
    String? reason,
  }) async {
    final res = await _db.from('refunds').insert({
      'store_id': _storeId,
      'invoice_id': invoiceId,
      'worker_name': WorkerService.workerName,
      'items': items.map((e) => e.toJson()).toList(),
      'refund_amount': refundAmount,
      'reason': reason,
    }).select().single();
    return Refund.fromJson(res);
  }

  static Future<List<Refund>> getRefunds({int? invoiceId}) async {
    var query = _db.from('refunds').select().eq('store_id', _storeId);
    if (invoiceId != null) query = query.eq('invoice_id', invoiceId);
    final res = await query.order('created_at', ascending: false);
    return (res as List).map((e) => Refund.fromJson(e)).toList();
  }

  // ── Sales Targets ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSalesTargets() async {
    final res = await _db
        .from('sales_targets')
        .select()
        .eq('store_id', _storeId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<void> createSalesTarget({
    int? workerId,
    String? workerName,
    required String periodType,
    required double targetAmount,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    await _db.from('sales_targets').insert({
      'store_id': _storeId,
      'worker_id': workerId,
      'worker_name': workerName,
      'period_type': periodType,
      'target_amount': targetAmount,
      'period_start': periodStart.toIso8601String().split('T').first,
      'period_end': periodEnd.toIso8601String().split('T').first,
    });
  }

  static Future<void> deleteSalesTarget(int id) async {
    await _db.from('sales_targets').delete().eq('id', id);
  }

  static Future<double> getWorkerSales({
    required String workerName,
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await _db
        .from('invoices')
        .select('customer_pays')
        .eq('store_id', _storeId)
        .eq('worker_name', workerName)
        .gte('created_at', from.toIso8601String())
        .lte('created_at', to.toIso8601String());
    double total = 0;
    for (final row in (res as List)) {
      total += (row['customer_pays'] as num).toDouble();
    }
    return total;
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
        'cost_price': p.costPrice,
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
        'status': inv.status,
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
        'cost_price': row['cost_price'] ?? 0,
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
        'status': row['status'] ?? 'completed',
      });
      addedI++;
    }

    return {'products': addedP, 'customers': addedC, 'invoices': addedI};
  }
}
