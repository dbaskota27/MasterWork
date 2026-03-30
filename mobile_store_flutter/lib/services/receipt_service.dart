import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import 'database_service.dart';

class ReceiptService {
  static final _dateFormat = DateFormat('MMM d, y  h:mm a');

  static Future<pw.Document> buildPdf(Invoice inv) async {
    // Load live store info from Supabase
    final info = await DatabaseService.getStoreInfo();
    final storeName  = info['name'] as String? ?? 'Store';
    final storeAddr  = info['address'] as String? ?? '';
    final storePhone = info['phone'] as String? ?? '';
    final currency   = info['currency'] as String? ?? '\$';
    final paymentQr  = info['payment_qr'] as String? ?? '';

    final money = NumberFormat.currency(symbol: currency, decimalDigits: 2);

    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Center(
            child: pw.Column(children: [
              pw.Text(storeName,
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              if (storeAddr.isNotEmpty)
                pw.Text(storeAddr, style: const pw.TextStyle(fontSize: 9)),
              if (storePhone.isNotEmpty)
                pw.Text(storePhone, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 4),
              pw.Text('Invoice #${inv.id}', style: const pw.TextStyle(fontSize: 10)),
              pw.Text(_dateFormat.format(inv.createdAt),
                  style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
          pw.Divider(),

          // Served by
          if (inv.workerName != null)
            pw.Text('Served by: ${inv.workerName}',
                style: const pw.TextStyle(fontSize: 9)),

          // Customer
          if (inv.customerName != null) ...[
            pw.Text('Customer: ${inv.customerName}',
                style: const pw.TextStyle(fontSize: 10)),
            if (inv.customerPhone != null)
              pw.Text('Phone: ${inv.customerPhone}',
                  style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 4),
          ],

          // Items
          ...inv.items.map((item) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text('${item.productName} x${item.qty}',
                        style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Text(money.format(item.total),
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              )),

          pw.Divider(),

          // Totals
          _totalRow(money, 'Marked Price', inv.markedPrice),
          if (inv.discount > 0)
            _totalRow(money, 'Discount', -inv.discount, color: PdfColors.orange),
          _totalRow(money, 'Customer Pays', inv.customerPays,
              bold: true, color: PdfColors.green700),
          _totalRow(money,
              'Amount ${inv.paymentType == "cash" ? "Received" : "Transferred"}',
              inv.amountReceived),
          if (inv.change > 0)
            _totalRow(money, 'Change Given', inv.change, bold: true),

          if (inv.pointsRedeemed > 0)
            _totalRow(money, 'Points Redeemed', -inv.pointsRedeemed,
                color: PdfColors.amber),
          if (inv.pointsEarned > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Points Earned: +${inv.pointsEarned.toStringAsFixed(0)}',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.blue700),
              ),
            ),

          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              inv.paymentType == 'cash' ? 'Payment: Cash' : 'Payment: QuickPay',
              style: pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700),
            ),
          ),

          // QR code
          if (paymentQr.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Column(children: [
                pw.Text('Scan to Pay', style: const pw.TextStyle(fontSize: 9)),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: paymentQr,
                  width: 80,
                  height: 80,
                ),
              ]),
            ),
          ],

          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('Thank you for your business!',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    ));

    return pdf;
  }

  static pw.Widget _totalRow(
      NumberFormat money, String label, double amount,
      {bool bold = false, PdfColor? color}) {
    final style = pw.TextStyle(
      fontSize: 10,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(money.format(amount), style: style),
      ],
    );
  }

  static Future<void> shareReceipt(Invoice inv) async {
    final pdf = await buildPdf(inv);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'receipt_${inv.id}.pdf',
    );
  }

  static Future<void> printReceipt(Invoice inv) async {
    final pdf = await buildPdf(inv);
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }
}
