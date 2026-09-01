import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PaymentReceiptData {
  final String businessName;
  final String receiptNumber;
  final String paidBy;
  final String paidTo;
  final String billNumber;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod;
  final String notes;

  const PaymentReceiptData({
    this.businessName = 'NEELKANTH GARMENTS',
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
  final dateTime = DateFormat('dd MMM yyyy  ·  hh:mm a')
      .format(data.paymentDate);
  final amount = data.amount.toStringAsFixed(2);
  const ink = PdfColor.fromInt(0xFF102A43);
  const navy = PdfColor.fromInt(0xFF16324F);
  const blue = PdfColor.fromInt(0xFF2F80ED);
  const slate = PdfColor.fromInt(0xFF62748A);
  const muted = PdfColor.fromInt(0xFF8A9AAF);
  const lightBlue = PdfColor.fromInt(0xFFEAF3FF);
  const line = PdfColor.fromInt(0xFFDCE6F0);
  const white = PdfColors.white;

  pw.Widget detail(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 9),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 118,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                color: slate,
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '—' : value,
              style: pw.TextStyle(
                color: ink,
                fontSize: 10.5,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget partyCard(String label, String value, PdfColor accent) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: white,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
          border: pw.Border.all(color: line),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 24,
              height: 3,
              decoration: pw.BoxDecoration(
                color: accent,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
            ),
            pw.SizedBox(height: 9),
            pw.Text(
              label.toUpperCase(),
              style: const pw.TextStyle(
                color: muted,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              value.isEmpty ? '—' : value,
              maxLines: 2,
              style: pw.TextStyle(
                color: ink,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 38, 42, 34),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(22, 18, 22, 20),
            decoration: pw.BoxDecoration(
              color: navy,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
              border: pw.Border.all(color: blue, width: 1.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 38,
                      height: 38,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: blue,
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(9)),
                      ),
                      child: pw.Text(
                        'NG',
                        style: pw.TextStyle(
                          color: white,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          data.businessName,
                          style: pw.TextStyle(
                            color: white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Payment acknowledgement',
                          style: const pw.TextStyle(
                            color: PdfColor.fromInt(0xFFC7D9EF),
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'PAYMENT RECEIPT',
                      style: pw.TextStyle(
                        color: white,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      data.receiptNumber,
                      style: const pw.TextStyle(
                        color: PdfColor.fromInt(0xFFC7D9EF),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 22),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'AMOUNT RECEIVED',
                    style: const pw.TextStyle(
                      color: muted,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'INR $amount',
                    style: pw.TextStyle(
                      color: ink,
                      fontSize: 27,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: pw.BoxDecoration(
                  color: lightBlue,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(7)),
                ),
                child: pw.Text(
                  'PAID  ·  $date',
                  style: const pw.TextStyle(
                    color: blue,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              partyCard('Paid by', data.paidBy, blue),
              pw.SizedBox(width: 12),
              partyCard('Paid to', data.paidTo, navy),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(17, 7, 17, 7),
            decoration: pw.BoxDecoration(
              color: lightBlue,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Column(
              children: [
                detail('Payment date & time', dateTime),
                pw.Divider(color: white, height: 1),
                detail('Payment method', data.paymentMethod),
                pw.Divider(color: white, height: 1),
                detail(
                  'Reference bill',
                  data.billNumber.isEmpty ? 'Not linked' : data.billNumber,
                ),
              ],
            ),
          ),
          if (data.notes.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text(
              'Payment notes',
              style: pw.TextStyle(
                color: ink,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 7),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF7FAFD),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: line),
              ),
              child: pw.Text(
                data.notes,
                style: const pw.TextStyle(color: slate, fontSize: 10),
              ),
            ),
          ],
          pw.Spacer(),
          pw.Container(height: 1, color: line),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                data.businessName,
                style: const pw.TextStyle(
                  color: navy,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Generated on $dateTime',
                style: const pw.TextStyle(color: slate, fontSize: 8.5),
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          pw.Text(
            'This is a computer-generated receipt and does not require a signature.',
            style: const pw.TextStyle(color: slate, fontSize: 8.5),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    ),
  );

  return pdf.save();
}