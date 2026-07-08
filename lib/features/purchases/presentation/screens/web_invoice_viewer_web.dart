// Web-only PDF/invoice viewer using iframe.
// Imported conditionally via `if (dart.library.html)` in purchase_client_detail_screen.dart

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

void openPdfInApp(BuildContext context, String url, String billNumber,
    String clientName) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _WebInvoiceViewerPage(
        url: url,
        billNumber: billNumber,
        clientName: clientName,
      ),
    ),
  );
}

class _WebInvoiceViewerPage extends StatefulWidget {
  final String url;
  final String billNumber;
  final String clientName;

  const _WebInvoiceViewerPage({
    required this.url,
    required this.billNumber,
    required this.clientName,
  });

  @override
  State<_WebInvoiceViewerPage> createState() => _WebInvoiceViewerPageState();
}

class _WebInvoiceViewerPageState extends State<_WebInvoiceViewerPage> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'invoice-pdf-${widget.billNumber}-${widget.url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      return html.IFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'fullscreen';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1018),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.clientName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            Text('Invoice  #${widget.billNumber}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
      body: HtmlElementView(viewType: _viewId),
    );
  }
}
