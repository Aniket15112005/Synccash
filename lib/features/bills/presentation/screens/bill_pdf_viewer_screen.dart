// lib/features/bills/presentation/screens/bill_pdf_viewer_screen.dart
//
// Universal in-app PDF viewer for custom bills.
// – Web  : iframe via Google Docs embedded viewer
// – Native: WebView via Google Docs viewer

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:synccash/features/sales/presentation/screens/web_invoice_viewer_stub.dart'
    if (dart.library.html) 'package:synccash/features/sales/presentation/screens/web_invoice_viewer_web.dart';
import 'package:synccash/features/sales/presentation/screens/native_pdf_viewer_stub.dart'
    if (dart.library.io) 'package:synccash/features/sales/presentation/screens/native_pdf_viewer_native.dart';

class BillPdfViewerScreen extends StatefulWidget {
  final String url;
  final String billNumber;
  final String clientName;

  const BillPdfViewerScreen({
    super.key,
    required this.url,
    required this.billNumber,
    required this.clientName,
  });

  @override
  State<BillPdfViewerScreen> createState() => _BillPdfViewerScreenState();
}

class _BillPdfViewerScreenState extends State<BillPdfViewerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kIsWeb) {
        // Replaces this route with the web iframe viewer
        openPdfInApp(
          context,
          widget.url,
          widget.billNumber,
          widget.clientName,
        );
      } else {
        openNativePdfInApp(
          context,
          widget.url,
          widget.billNumber,
          widget.clientName,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Shown briefly while the real viewer pushes
    return const Scaffold(
      backgroundColor: Color(0xFF080A0E),
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF6C7FE4),
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}
