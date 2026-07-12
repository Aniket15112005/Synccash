// lib/features/bills/presentation/screens/bill_pdf_generator.dart
//
// Generates a Tax Invoice PDF matching the reference format exactly.
// No rupee symbols anywhere. No lags (no heavy ops on main thread).

import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../data/models/custom_bill_model.dart';

// ── Amount-to-words (Indian numbering system) ─────────────────────────────────

String _numberToWords(int n) {
  if (n == 0) return 'Zero';
  const ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight',
    'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
    'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
  ];
  const tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty',
    'Sixty', 'Seventy', 'Eighty', 'Ninety',
  ];

  String convert(int x) {
    if (x == 0) return '';
    if (x < 20) return ones[x];
    if (x < 100) {
      return tens[x ~/ 10] + (x % 10 != 0 ? ' ${ones[x % 10]}' : '');
    }
    if (x < 1000) {
      return '${ones[x ~/ 100]} Hundred' +
          (x % 100 != 0 ? ' ${convert(x % 100)}' : '');
    }
    if (x < 100000) {
      return '${convert(x ~/ 1000)} Thousand' +
          (x % 1000 != 0 ? ' ${convert(x % 1000)}' : '');
    }
    if (x < 10000000) {
      return '${convert(x ~/ 100000)} Lakh' +
          (x % 100000 != 0 ? ' ${convert(x % 100000)}' : '');
    }
    return '${convert(x ~/ 10000000)} Crore' +
        (x % 10000000 != 0 ? ' ${convert(x % 10000000)}' : '');
  }

  return convert(n);
}

String _amountToWords(double amount) {
  final rupees = amount.floor();
  final paise  = ((amount - rupees) * 100).round();
  var result   = '${_numberToWords(rupees)} Rupees';
  if (paise > 0) result += ' and ${_numberToWords(paise)} Paise';
  result += ' only';
  return result;
}

// Formats a tax/GST rate without ever rounding to a whole number
// (e.g. 2.5 must stay "2.5", not become "3").
String _fmtRate(double r) {
  if (r == r.truncateToDouble()) return r.toStringAsFixed(0);
  var s = r.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

// ── Place-of-supply helper ────────────────────────────────────────────────────

String _placeOfSupply(String address) {
  final a = address.toLowerCase();
  if (a.contains('karnataka'))      return '29-Karnataka';
  if (a.contains('gujarat'))        return '24-Gujarat';
  if (a.contains('delhi'))          return '07-Delhi';
  if (a.contains('rajasthan'))      return '08-Rajasthan';
  if (a.contains('tamil'))          return '33-Tamil Nadu';
  if (a.contains('telangana'))      return '36-Telangana';
  if (a.contains('andhra'))         return '37-Andhra Pradesh';
  if (a.contains('kerala'))         return '32-Kerala';
  if (a.contains('punjab'))         return '03-Punjab';
  if (a.contains('haryana'))        return '06-Haryana';
  if (a.contains('uttar pradesh') || a.contains(' up '))
                                    return '09-Uttar Pradesh';
  if (a.contains('west bengal'))    return '19-West Bengal';
  return '27-Maharashtra';
}

// ── PDF Builder ───────────────────────────────────────────────────────────────

Future<Uint8List> buildBillPdfFromModel(CustomBillModel bill) async {
  final pdf     = pw.Document();
  final fmt     = NumberFormat('#,##,##0.00', 'en_IN');
  final dateFmt = DateFormat('dd/MM/yyyy');
  final date    = dateFmt.format(bill.billDate);

  // ── Colors ─────────────────────────────────────────────────────────
  const cBlack  = PdfColors.black;
  const cWhite  = PdfColors.white;
  final cBorder = PdfColor.fromHex('AAAAAA');
  final cBg     = PdfColor.fromHex('F2F2F2');   // header/total row bg

  // ── Text styles ────────────────────────────────────────────────────
  final titleStyle = pw.TextStyle(
      fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800);

  final sectionBold = pw.TextStyle(
      fontSize: 8, fontWeight: pw.FontWeight.bold, color: cBlack);

  final body = pw.TextStyle(fontSize: 8, color: cBlack);

  final bodyBold = pw.TextStyle(
      fontSize: 8, fontWeight: pw.FontWeight.bold, color: cBlack);

  final small = pw.TextStyle(fontSize: 7.5, color: cBlack);

  final smallBold = pw.TextStyle(
      fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: cBlack);

  final tinyMuted = pw.TextStyle(
      fontSize: 7, color: PdfColor.fromHex('555555'));

  // ── Table border used throughout ───────────────────────────────────
  final fullBorder = pw.TableBorder.all(color: cBorder, width: 0.5);

  // ── Cell helpers ───────────────────────────────────────────────────
  // Header cell (grey bg)
  pw.Widget hCell(String t, {pw.TextAlign align = pw.TextAlign.center}) =>
      pw.Container(
        color: cBg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
        child: pw.Text(t, style: smallBold, textAlign: align),
      );

  // Data cell
  pw.Widget dCell(String t,
      {pw.TextAlign align = pw.TextAlign.center, bool bold = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
        child: pw.Text(t, style: bold ? smallBold : small, textAlign: align),
      );

  // Padded text helper for manual table rows
  pw.Widget pad(pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
      child: child);

  // ── Compute totals ─────────────────────────────────────────────────
  final taxRate = bill.taxRate;
  double totalQty = 0;
  double totalTax = 0;

  for (final item in bill.items) {
    totalQty += item.qty;
    totalTax += item.qty * item.rate * taxRate / 100;
  }

  // HSN map for tax summary
  final hsnMap = <String, double>{};
  for (final item in bill.items) {
    final code = item.hsnSac.isEmpty ? '-' : item.hsnSac;
    hsnMap[code] = (hsnMap[code] ?? 0) + item.qty * item.rate;
  }

  final placeOfSupply = _placeOfSupply(bill.businessAddress);

  // ── Item rows ──────────────────────────────────────────────────────
  final itemRows = List.generate(bill.items.length, (i) {
    final item    = bill.items[i];
    final itemTax = item.qty * item.rate * taxRate / 100;
    final itemAmt = item.qty * item.rate + itemTax;
    final qtyStr  = item.qty == item.qty.truncateToDouble()
        ? item.qty.toStringAsFixed(0)
        : item.qty.toStringAsFixed(2);

    return pw.TableRow(
      children: [
        dCell('${i + 1}'),
        dCell(item.name, align: pw.TextAlign.left, bold: true),
        dCell(item.hsnSac.isEmpty ? '' : item.hsnSac),
        dCell(item.size),
        dCell(qtyStr, align: pw.TextAlign.right, bold: true),
        dCell('Pcs'),
        dCell(fmt.format(item.rate), align: pw.TextAlign.right),
        // GST column: amount on top, rate% in parentheses below
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: taxRate > 0
              ? pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(fmt.format(itemTax),
                        style: small, textAlign: pw.TextAlign.right),
                    pw.Text('(${_fmtRate(taxRate)}%)',
                        style: tinyMuted, textAlign: pw.TextAlign.right),
                  ],
                )
              : pw.Text('-', style: small, textAlign: pw.TextAlign.right),
        ),
        dCell(fmt.format(itemAmt), align: pw.TextAlign.right, bold: true),
      ],
    );
  });

  // ── Tax summary rows ───────────────────────────────────────────────
  final taxSummaryDataRows = hsnMap.entries.map((e) {
    final taxable = e.value;
    final igstAmt = taxable * taxRate / 100;
    return pw.TableRow(children: [
      dCell(e.key, align: pw.TextAlign.left),
      dCell(fmt.format(taxable), align: pw.TextAlign.right),
      dCell(taxRate > 0 ? _fmtRate(taxRate) : '0',
          align: pw.TextAlign.center),
      dCell(fmt.format(igstAmt), align: pw.TextAlign.right),
      dCell(fmt.format(igstAmt), align: pw.TextAlign.right),
    ]);
  }).toList();

  // TOTAL row for tax summary
  taxSummaryDataRows.add(pw.TableRow(
    decoration: pw.BoxDecoration(color: cBg),
    children: [
      pad(pw.Text('TOTAL', style: smallBold)),
      pad(pw.Text(fmt.format(bill.subtotal),
          style: smallBold, textAlign: pw.TextAlign.right)),
      pad(pw.Text('')),
      pad(pw.Text(fmt.format(bill.taxAmount),
          style: smallBold, textAlign: pw.TextAlign.right)),
      pad(pw.Text(fmt.format(bill.taxAmount),
          style: smallBold, textAlign: pw.TextAlign.right)),
    ],
  ));

  // ── Build page ─────────────────────────────────────────────────────
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
      build: (ctx) => [

        // ── 1. TITLE: "Tax Invoice" centered ──────────────────────
        pw.Center(child: pw.Text('ESTIMATE', style: titleStyle)),
        pw.SizedBox(height: 6),

        // ── 2. COMPANY HEADER BOX ─────────────────────────────────
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: cBorder, width: 0.5),
          ),
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(7),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left: company name + address block
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        bill.businessName,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      if (bill.businessAddress.isNotEmpty)
                        pw.Text(bill.businessAddress, style: small),
                      pw.SizedBox(height: 3),
                      pw.Row(children: [
                        pw.Text('Phone: ', style: tinyMuted),
                        pw.Text('', style: small),
                        pw.SizedBox(width: 16),
                        pw.Text('Email: ', style: tinyMuted),
                        pw.Text('', style: small),
                      ]),
                      pw.SizedBox(height: 2),
                      pw.Row(children: [
                        pw.Text('GSTIN: ', style: tinyMuted),
                        pw.Text('', style: small),
                        pw.SizedBox(width: 16),
                        pw.Text('State: ', style: tinyMuted),
                        pw.Text(
                          placeOfSupply.contains('-')
                              ? placeOfSupply.split('-').last
                              : placeOfSupply,
                          style: small,
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 3. BILL TO | INVOICE DETAILS ─────────────────────────
        pw.Table(
          border: fullBorder,
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            // Section labels row
            pw.TableRow(children: [
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(7, 4, 7, 2),
                child: pw.Text('Bill To:', style: bodyBold),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(7, 4, 7, 2),
                child: pw.Text('Invoice Details:', style: bodyBold),
              ),
            ]),
            // Content row
            pw.TableRow(children: [
              // Bill To content
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(7, 1, 7, 5),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      bill.clientName.isEmpty ? '-' : bill.clientName,
                      style: bodyBold,
                    ),
                    pw.SizedBox(height: 2),
                    if (bill.clientAddress.isNotEmpty)
                      pw.Text(bill.clientAddress, style: small),
                    pw.SizedBox(height: 2),
                    pw.Row(children: [
                      pw.Text('GSTIN: ', style: tinyMuted),
                      pw.Text('', style: small),
                    ]),
                    pw.SizedBox(height: 1),
                    pw.Row(children: [
                      pw.Text('State: ', style: tinyMuted),
                      pw.Text(
                        placeOfSupply.contains('-')
                            ? placeOfSupply.split('-').last
                            : placeOfSupply,
                        style: small,
                      ),
                    ]),
                  ],
                ),
              ),
              // Invoice Details content
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(7, 1, 7, 5),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      pw.Text('Invoice No.: ', style: small),
                      pw.Text(bill.billNumber, style: bodyBold),
                    ]),
                    pw.SizedBox(height: 3),
                    pw.Row(children: [
                      pw.Text('Date: ', style: small),
                      pw.Text(date, style: bodyBold),
                    ]),
                    pw.SizedBox(height: 3),
                    pw.Row(children: [
                      pw.Text('Place Of Supply: ', style: small),
                      pw.Text(placeOfSupply, style: bodyBold),
                    ]),
                  ],
                ),
              ),
            ]),
          ],
        ),

        // ── 4. ITEMS TABLE ────────────────────────────────────────
        pw.Table(
          border: fullBorder,
          columnWidths: const {
            0: pw.FixedColumnWidth(18),   // #
            1: pw.FlexColumnWidth(2.8),   // Item name
            2: pw.FixedColumnWidth(42),   // HSN/SAC
            3: pw.FixedColumnWidth(34),   // Size
            4: pw.FixedColumnWidth(40),   // Quantity
            5: pw.FixedColumnWidth(26),   // Unit
            6: pw.FixedColumnWidth(54),   // Price/Unit
            7: pw.FixedColumnWidth(58),   // GST
            8: pw.FixedColumnWidth(58),   // Amount
          },
          children: [
            // Header row
            pw.TableRow(
              decoration: pw.BoxDecoration(color: cBg),
              children: [
                hCell('#'),
                hCell('Item name', align: pw.TextAlign.left),
                hCell('HSN/ SAC'),
                hCell('Size'),
                hCell('Quantity', align: pw.TextAlign.right),
                hCell('Unit'),
                hCell('Price/\nUnit', align: pw.TextAlign.right),
                hCell('GST', align: pw.TextAlign.right),
                hCell('Amount', align: pw.TextAlign.right),
              ],
            ),
            // Item rows
            ...itemRows,
            // Total row
            pw.TableRow(
              decoration: pw.BoxDecoration(color: cBg),
              children: [
                pad(pw.Text('')),
                pad(pw.Text('Total', style: smallBold)),
                pad(pw.Text('')),
                pad(pw.Text('')),
                pad(pw.Text(
                  totalQty == totalQty.truncateToDouble()
                      ? totalQty.toStringAsFixed(0)
                      : totalQty.toStringAsFixed(2),
                  style: smallBold,
                  textAlign: pw.TextAlign.right,
                )),
                pad(pw.Text('')),
                pad(pw.Text('')),
                pad(pw.Text(
                  taxRate > 0 ? fmt.format(totalTax) : '',
                  style: smallBold,
                  textAlign: pw.TextAlign.right,
                )),
                pad(pw.Text(fmt.format(bill.grandTotal),
                    style: smallBold, textAlign: pw.TextAlign.right)),
              ],
            ),
          ],
        ),

        // ── 5. TAX SUMMARY (left) + TOTALS (right) ───────────────
        pw.Table(
          border: fullBorder,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.55),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: [
                // Left: Tax Summary
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.fromLTRB(6, 3.5, 6, 3.5),
                      child: pw.Text('Tax Summary:', style: bodyBold),
                    ),
                    pw.Table(
                      border: pw.TableBorder(
                        top: pw.BorderSide(color: cBorder, width: 0.5),
                        bottom: pw.BorderSide(color: cBorder, width: 0.5),
                        left: pw.BorderSide.none,
                        right: pw.BorderSide(color: cBorder, width: 0.5),
                        verticalInside:
                            pw.BorderSide(color: cBorder, width: 0.5),
                        horizontalInside:
                            pw.BorderSide(color: cBorder, width: 0.5),
                      ),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(1.1),   // HSN/SAC
                        1: pw.FlexColumnWidth(1.6),   // Taxable amount
                        2: pw.FlexColumnWidth(0.8),   // IGST Rate
                        3: pw.FlexColumnWidth(1.2),   // IGST Amt
                        4: pw.FlexColumnWidth(1.2),   // Total Tax
                      },
                      children: [
                        // Tax summary header
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: cBg),
                          children: [
                            hCell('HSN/ SAC', align: pw.TextAlign.left),
                            hCell('Taxable amount',
                                align: pw.TextAlign.right),
                            pw.Container(
                              color: cBg,
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 5),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  pw.Text('IGST',
                                      style: smallBold,
                                      textAlign: pw.TextAlign.center),
                                  pw.Table(
                                    border: pw.TableBorder(
                                      top: pw.BorderSide(
                                          color: cBorder, width: 0.5),
                                      verticalInside: pw.BorderSide(
                                          color: cBorder, width: 0.5),
                                    ),
                                    columnWidths: const {
                                      0: pw.FlexColumnWidth(1),
                                      1: pw.FlexColumnWidth(1),
                                    },
                                    children: [
                                      pw.TableRow(children: [
                                        pw.Container(
                                          padding: const pw.EdgeInsets.only(
                                              top: 2),
                                          child: pw.Text('Rate (%)',
                                              style: tinyMuted,
                                              textAlign:
                                                  pw.TextAlign.center),
                                        ),
                                        pw.Container(
                                          padding: const pw.EdgeInsets.only(
                                              top: 2),
                                          child: pw.Text('Amt',
                                              style: tinyMuted,
                                              textAlign:
                                                  pw.TextAlign.center),
                                        ),
                                      ]),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Blank for IGST Amt (merged into IGST column above)
                            pw.Container(color: cBg),
                            hCell('Total Tax\n(in Amt)',
                                align: pw.TextAlign.right),
                          ],
                        ),
                        // Data rows
                        ...hsnMap.entries.map((e) {
                          final taxable = e.value;
                          final igstAmt = taxable * taxRate / 100;
                          return pw.TableRow(children: [
                            dCell(e.key, align: pw.TextAlign.left),
                            dCell(fmt.format(taxable),
                                align: pw.TextAlign.right),
                            dCell(
                                taxRate > 0 ? _fmtRate(taxRate) : '0',
                                align: pw.TextAlign.center),
                            dCell(fmt.format(igstAmt),
                                align: pw.TextAlign.right),
                            dCell(fmt.format(igstAmt),
                                align: pw.TextAlign.right),
                          ]);
                        }),
                        // TOTAL row
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: cBg),
                          children: [
                            pad(pw.Text('TOTAL', style: smallBold,
                                textAlign: pw.TextAlign.left)),
                            pad(pw.Text(fmt.format(bill.subtotal),
                                style: smallBold,
                                textAlign: pw.TextAlign.right)),
                            pad(pw.Text('')),
                            pad(pw.Text(fmt.format(bill.taxAmount),
                                style: smallBold,
                                textAlign: pw.TextAlign.right)),
                            pad(pw.Text(fmt.format(bill.taxAmount),
                                style: smallBold,
                                textAlign: pw.TextAlign.right)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                // Right: Totals
                pw.Table(
                  border: pw.TableBorder(
                    top: pw.BorderSide.none,
                    bottom: pw.BorderSide.none,
                    left: pw.BorderSide.none,
                    right: pw.BorderSide.none,
                    horizontalInside:
                        pw.BorderSide(color: cBorder, width: 0.5),
                    verticalInside:
                        pw.BorderSide(color: cBorder, width: 0.5),
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.6),  // label
                    1: pw.FixedColumnWidth(10),  // colon
                    2: pw.FlexColumnWidth(2),    // value
                  },
                  children: [
                    // Sub Total
                    pw.TableRow(children: [
                      pad(pw.Text('Sub Total', style: small)),
                      pad(pw.Text(':', style: small)),
                      pad(pw.Text(fmt.format(bill.subtotal),
                          style: small, textAlign: pw.TextAlign.right)),
                    ]),
                    // Total (bold)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: cWhite),
                      children: [
                        pad(pw.Text('Total', style: bodyBold)),
                        pad(pw.Text(':', style: bodyBold)),
                        pad(pw.Text(fmt.format(bill.grandTotal),
                            style: bodyBold,
                            textAlign: pw.TextAlign.right)),
                      ],
                    ),
                    // Received
                    pw.TableRow(children: [
                      pad(pw.Text('Received', style: small)),
                      pad(pw.Text(':', style: small)),
                      pad(pw.Text(fmt.format(bill.receivedAmount),
                          style: small, textAlign: pw.TextAlign.right)),
                    ]),
                    // Balance
                    pw.TableRow(children: [
                      pad(pw.Text('Balance', style: small)),
                      pad(pw.Text(':', style: small)),
                      pad(pw.Text(
                          fmt.format(bill.grandTotal - bill.receivedAmount),
                          style: small, textAlign: pw.TextAlign.right)),
                    ]),
                  ],
                ),
              ],
            ),
          ],
        ),

        // ── 5b. INVOICE AMOUNT IN WORDS (full width, left aligned) ──
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: cBorder, width: 0.5),
          ),
          padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Invoice Amount in Words: ',
                  style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: cBlack)),
              pw.Expanded(
                child: pw.Text(
                  _amountToWords(bill.grandTotal),
                  style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: cBlack),
                  textAlign: pw.TextAlign.left,
                ),
              ),
            ],
          ),
        ),

        // ── 6. TERMS & CONDITIONS ─────────────────────────────────
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: cBorder, width: 0.5),
          ),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Terms & Conditions:', style: bodyBold),
              pw.SizedBox(height: 3),
              pw.Text(
                '1. Shirts must be returned in original condition with tags intact to be eligible for exchange.\n'
                '2. Discounts, if any, are applied at the time of sale and cannot be claimed later.\n'
                '3. The store is not responsible for damage due to mishandling or improper washing.\n'
                '4. Any disputes will be subject to Bangalore jurisdiction.',
                style: pw.TextStyle(fontSize: 7.5, color: cBlack),
              ),
            ],
          ),
        ),

        // ── 7. BANK DETAILS | AUTHORIZED SIGNATORY ───────────────
        pw.Table(
          border: fullBorder,
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(children: [
              // Bank Details
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Bank Details:', style: bodyBold),
                    pw.SizedBox(height: 4),
                    pw.Row(children: [
                      pw.Text('Name : ', style: tinyMuted),
                      pw.Text('', style: small),
                    ]),
                    pw.SizedBox(height: 3),
                    pw.Row(children: [
                      pw.Text('Account No. : ', style: tinyMuted),
                      pw.Text('', style: small),
                    ]),
                    pw.SizedBox(height: 3),
                    pw.Row(children: [
                      pw.Text('IFSC code : ', style: tinyMuted),
                      pw.Text('', style: small),
                    ]),
                    pw.SizedBox(height: 3),
                    pw.Row(children: [
                      pw.Text('Account holder\'s name : ', style: tinyMuted),
                      pw.Text('', style: small),
                    ]),
                    pw.SizedBox(height: 3),
                  ],
                ),
              ),
              // Authorized Signatory
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('For ${bill.businessName}', style: bodyBold),
                    pw.SizedBox(height: 36),
                    pw.Container(
                        width: 100, height: 0.6,
                        color: PdfColor.fromHex('888888')),
                    pw.SizedBox(height: 3),
                    pw.Text('Authorized Signatory', style: tinyMuted),
                  ],
                ),
              ),
            ]),
          ],
        ),
      ],
    ),
  );

  return pdf.save();
}
