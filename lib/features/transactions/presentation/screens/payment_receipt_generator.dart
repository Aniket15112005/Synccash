import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PaymentReceiptData {
  final String receiptNumber;
  final String paidBy;
  final String paidTo;
  final String billNumber;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod;
  final String notes;

  const PaymentReceiptData({
    required this.receiptNumber,
    required this.paidBy,
    required this.paidTo,
    required this.billNumber,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    required this.notes,
  });
}

Future<Uint8List> buildPaymentReceiptPdf(PaymentReceiptData data) async {
  final pdf = pw.Document();
  final date = DateFormat('dd MMM yyyy').format(data.paymentDate);
  final amount = data.amount.toStringAsFixed(2);
  const navy = PdfColor.fromInt(0xFF172033);
  const slate = PdfColor.fromInt(0xFF64748B);
  const light = PdfColor.fromInt(0xFFF1F5F9);

  pw.Widget detail(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 125,
            child: pw.Text(
              label,
              style: const pw.TextStyle(color: slate, fontSize: 10),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '—' : value,
              style: pw.TextStyle(
                color: navy,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: const pw.BoxDecoration(
              color: navy,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'PAYMENT RECEIPT',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Acknowledgement of payment',
                      style: const pw.TextStyle(
                        color: PdfColor.fromInt(0xFFCBD5E1),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'INR $amount',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Receipt no. ${data.receiptNumber}',
                style: const pw.TextStyle(color: slate, fontSize: 10),
              ),
              pw.Text(
                date,
                style: const pw.TextStyle(color: slate, fontSize: 10),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(18),
            decoration: const pw.BoxDecoration(
              color: light,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Column(
              children: [
                detail('Paid by', data.paidBy),
                pw.Divider(color: PdfColors.white),
                detail('Paid to', data.paidTo),
                pw.Divider(color: PdfColors.white),
                detail('Amount paid', 'INR $amount'),
                pw.Divider(color: PdfColors.white),
                detail('Payment method', data.paymentMethod),
                if (data.billNumber.isNotEmpty) ...[
                  pw.Divider(color: PdfColors.white),
                  detail('Purchase bill', data.billNumber),
                ],
              ],
            ),
          ),
          if (data.notes.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'Notes',
              style: pw.TextStyle(
                color: navy,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              data.notes,
              style: const pw.TextStyle(color: slate, fontSize: 11),
            ),
          ],
          pw.Spacer(),
          pw.Divider(color: light),
          pw.SizedBox(height: 8),
          pw.Text(
            'This receipt confirms that the payment above was recorded.',
            style: const pw.TextStyle(color: slate, fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    ),
  );

  return pdf.save();
}