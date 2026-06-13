// lib/features/settings/services/export_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

class ExportService {
  static final _dateFmt    = DateFormat('dd MMM yyyy, hh:mm a');
  static final _fileDateFmt = DateFormat('yyyyMMdd_HHmmss');

  // ── PDF Export ────────────────────────────────────────────────────────────

  static Future<void> exportToPdf({
    required BuildContext context,
    required List<TransactionEntity> transactions,
    required String cashbookName,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();

    final totalIncome = transactions
        .where((t) => t.type == 'income')
        .fold(0.0, (s, t) => s + t.amount);
    final totalExpense = transactions
        .where((t) => t.type == 'expense')
        .fold(0.0, (s, t) => s + t.amount);
    final balance = totalIncome - totalExpense;

    const rowsPerPage = 25;
    final chunks = <List<TransactionEntity>>[];
    for (var i = 0; i < transactions.length; i += rowsPerPage) {
      chunks.add(transactions.sublist(
        i,
        (i + rowsPerPage).clamp(0, transactions.length),
      ));
    }
    if (chunks.isEmpty) chunks.add([]);

    for (var pageIndex = 0; pageIndex < chunks.length; pageIndex++) {
      final isFirst = pageIndex == 0;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (isFirst) ...[
                  pw.Text(
                    cashbookName,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Exported on ${_dateFmt.format(now)}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Row(children: [
                    _pdfSummaryBox('Total Income',
                        '${_fmt(totalIncome)}', PdfColors.green700),
                    pw.SizedBox(width: 12),
                    _pdfSummaryBox('Total Expense',
                        '${_fmt(totalExpense)}', PdfColors.red700),
                    pw.SizedBox(width: 12),
                    _pdfSummaryBox(
                      'Balance',
                      '${_fmt(balance)}',
                      balance >= 0 ? PdfColors.blue700 : PdfColors.red700,
                    ),
                  ]),
                  pw.SizedBox(height: 20),
                ],
                if (!isFirst) ...[
                  pw.Text(
                    '$cashbookName — continued (page ${pageIndex + 1})',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ],
                pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2.2),
                    1: const pw.FlexColumnWidth(1.2),
                    2: const pw.FlexColumnWidth(1.4),
                    3: const pw.FlexColumnWidth(2.5),
                    4: const pw.FlexColumnWidth(1.5),
                    5: const pw.FlexColumnWidth(1.5),
                  },
                  border: pw.TableBorder.all(
                    color: PdfColors.grey300,
                    width: 0.5,
                  ),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                          color: PdfColors.grey100),
                      children: [
                        _pdfHeaderCell('Date'),
                        _pdfHeaderCell('Type'),
                        _pdfHeaderCell('Category'),
                        _pdfHeaderCell('Description'),
                        _pdfHeaderCell('Amount (₹)'),
                        _pdfHeaderCell('Created By'),
                      ],
                    ),
                    ...chunks[pageIndex].map((tx) {
                      final isIncome = tx.type == 'income';
                      return pw.TableRow(children: [
                        _pdfCell(_dateFmt.format(tx.createdAt)),
                        _pdfCell(
                          tx.type.toUpperCase(),
                          color: isIncome
                              ? PdfColors.green700
                              : PdfColors.red700,
                          bold: true,
                        ),
                        _pdfCell(tx.category),
                        _pdfCell(tx.description.isEmpty
                            ? '—'
                            : tx.description),
                        _pdfCell(
                          '${isIncome ? '+' : '-'}${_fmt(tx.amount)}',
                          color: isIncome
                              ? PdfColors.green700
                              : PdfColors.red700,
                          bold: true,
                          align: pw.TextAlign.right,
                        ),
                        _pdfCell(tx.creatorName),
                      ]);
                    }),
                  ],
                ),
                pw.Spacer(),
                pw.Divider(color: PdfColors.grey300),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'SyncCash — Cashbook Export',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey500),
                    ),
                    pw.Text(
                      'Page ${pageIndex + 1} of ${chunks.length}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey500),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    final bytes = await pdf.save();
    final fileName = 'SyncCash_Export_${_fileDateFmt.format(now)}.pdf';

    if (!context.mounted) return;
    await _saveAndShare(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/pdf',
    );
  }

  // ── Excel Export ──────────────────────────────────────────────────────────

  static Future<void> exportToExcel({
    required BuildContext context,
    required List<TransactionEntity> transactions,
    required String cashbookName,
  }) async {
    final excel = Excel.createExcel();
    final now = DateTime.now();

    final sheet = excel['Transactions'];
    excel.delete('Sheet1');

    CellStyle headerStyle() => CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#1E293B'),
          fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
          horizontalAlign: HorizontalAlign.Center,
        );

    CellStyle incomeStyle() => CellStyle(
          fontColorHex: ExcelColor.fromHexString('#16A34A'),
          bold: true,
        );

    CellStyle expenseStyle() => CellStyle(
          fontColorHex: ExcelColor.fromHexString('#DC2626'),
          bold: true,
        );

    final headers = [
      'Date', 'Time', 'Type', 'Category',
      'Description', 'Amount (INR)', 'Created By',
    ];
    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = headerStyle();
    }

    for (var i = 0; i < transactions.length; i++) {
      final tx = transactions[i];
      final rowIndex = i + 1;
      final isIncome = tx.type == 'income';
      final amtStyle = isIncome ? incomeStyle() : expenseStyle();

      void setCell(int col, CellValue val, {CellStyle? style}) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
              columnIndex: col, rowIndex: rowIndex),
        );
        cell.value = val;
        if (style != null) cell.cellStyle = style;
      }

      setCell(0,
          TextCellValue(DateFormat('dd MMM yyyy').format(tx.createdAt)));
      setCell(1,
          TextCellValue(DateFormat('hh:mm a').format(tx.createdAt)));
      setCell(2, TextCellValue(tx.type.toUpperCase()), style: amtStyle);
      setCell(3, TextCellValue(tx.category));
      setCell(4,
          TextCellValue(
              tx.description.isEmpty ? '—' : tx.description));
      setCell(
        5,
        DoubleCellValue(tx.amount * (isIncome ? 1 : -1)),
        style: amtStyle,
      );
      setCell(6, TextCellValue(tx.creatorName));
    }

    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 14);
    sheet.setColumnWidth(2, 12);
    sheet.setColumnWidth(3, 16);
    sheet.setColumnWidth(4, 30);
    sheet.setColumnWidth(5, 16);
    sheet.setColumnWidth(6, 18);

    final summary = excel['Summary'];
    final totalIncome = transactions
        .where((t) => t.type == 'income')
        .fold(0.0, (s, t) => s + t.amount);
    final totalExpense = transactions
        .where((t) => t.type == 'expense')
        .fold(0.0, (s, t) => s + t.amount);

    void sumRow(int row, String label, double val, String hexColor) {
      final lCell = summary.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      );
      lCell.value = TextCellValue(label);
      lCell.cellStyle = CellStyle(bold: true);
      final vCell = summary.cell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
      );
      vCell.value = DoubleCellValue(val);
      vCell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString(hexColor),
      );
    }

    summary
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue('Cashbook Summary');
    sumRow(1, 'Total Income',  totalIncome,  '#16A34A');
    sumRow(2, 'Total Expense', totalExpense, '#DC2626');
    sumRow(3, 'Net Balance',   totalIncome - totalExpense,
        totalIncome >= totalExpense ? '#16A34A' : '#DC2626');

    summary.setColumnWidth(0, 24);
    summary.setColumnWidth(1, 18);

    final bytes = excel.save();
    if (bytes == null) throw Exception('Failed to generate Excel file');

    final fileName = 'SyncCash_Export_${_fileDateFmt.format(now)}.xlsx';

    if (!context.mounted) return;
    await _saveAndShare(
      bytes: bytes,
      fileName: fileName,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  // ── Internal: platform-safe save & share ─────────────────────────────────

  static Future<void> _saveAndShare({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final uint8 = Uint8List.fromList(bytes);

    if (kIsWeb) {
      // Web / iOS PWA: use in-memory XFile — no path_provider needed
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(uint8, name: fileName, mimeType: mimeType)],
          subject: fileName,
        ),
      );
    } else {
      // Android / iOS native: write to temp file then share
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(uint8, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeType)],
          subject: fileName,
        ),
      );
    }
  }

  // ── PDF widget helpers ────────────────────────────────────────────────────

  static pw.Widget _pdfSummaryBox(
      String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1),
          borderRadius:
              const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: color)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfHeaderCell(String text) {
    return pw.Padding(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style:
            pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _pdfCell(
    String text, {
    PdfColor? color,
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8.5,
          color: color,
          fontWeight:
              bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static String _fmt(double v) => NumberFormat('#,##,##0', 'en_IN').format(v);
}