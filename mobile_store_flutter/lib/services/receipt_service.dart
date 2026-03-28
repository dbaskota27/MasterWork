import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models/invoice.dart';

class ReceiptService {
  static final _money = NumberFormat.currency(
    symbol: AppConfig.currency,
    decimalDigits: 2,
  );
  static final _dateFormat = DateFormat('MMM d, y  h:mm a');

  static Future<pw.Document> buildPdf(Invoice inv) async {
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Center(
            child: pw.Column(children: [
              pw.Text(AppConfig.storeName,
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              if (AppConfig.storeAddress.isNotEmpty)
                pw.Text(AppConfig.storeAddress,
                    style: const pw.TextStyle(fontSize: 9)),
              if (AppConfig.storePhone.isNotEmpty)
                pw.Text(AppConfig.storePhone,
                    style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 4),
              pw.Text('Invoice #${inv.id}',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text(_dateFormat.format(inv.createdAt),
                  style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
          pw.Divider(),

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
                  pw.Text(_money.format(item.total),
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              )),

          pw.Divider(),

          // Totals
          _totalRow('Marked Price', inv.markedPrice),
          if (inv.discount > 0)
            _totalRow('Discount', -inv.discount, color: PdfColors.orange),
          _totalRow('Customer Pays', inv.customerPays,
              bold: true, color: PdfColors.green700),
          _totalRow('Amount ${inv.paymentType == "cash" ? "Received" : "Transferred"}',
              inv.amountReceived),
          if (inv.change > 0)
            _totalRow('Change Given', inv.change, bold: true),

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

          // QR code placeholder (qr_flutter is for Flutter widgets, not PDF)
          if (AppConfig.paymentQrLink.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Column(children: [
                pw.Text('Scan to Pay', style: const pw.TextStyle(fontSize: 9)),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: AppConfig.paymentQrLink,
                  width: 80,
                  height: 80,
                ),
              ]),
            ),
          ],

          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('Thank you for your business!',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    ));

    return pdf;
  }

  static pw.Widget _totalRow(String label, double amount,
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
        pw.Text(_money.format(amount), style: style),
      ],
    );
  }

  /// Share/print via the OS share sheet.
  static Future<void> shareReceipt(Invoice inv) async {
    final pdf = await buildPdf(inv);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'receipt_${inv.id}.pdf',
    );
  }

  /// Open the system print dialog.
  static Future<void> printReceipt(Invoice inv) async {
    final pdf = await buildPdf(inv);
    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
    );
  }
}
