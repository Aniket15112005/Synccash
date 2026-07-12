// Web-only PDF/invoice viewer using iframe.
// Imported conditionally via `if (dart.library.html)` in purchase_client_detail_screen.dart
//
// Renders the PDF directly (no Google Docs Viewer round trip) so the
// browser's own PDF engine handles it: faster (one network hop instead of
// two) and supports native pinch-to-zoom. The app's global viewport lock
// (user-scalable=no) is temporarily relaxed while this page is open so the
// pinch gesture actually works, then restored on close.

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
        url:        url,
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
  String? _originalViewportContent;

  @override
  void initState() {
    super.initState();
    _relaxViewportZoomLock();

    _viewId = 'invoice-pdf-${widget.billNumber}-${widget.url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      return html.IFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.setProperty('touch-action', 'auto')
        ..style.setProperty('-webkit-overflow-scrolling', 'touch')
        ..allow = 'fullscreen';
    });
  }

  // The app locks the page viewport to prevent accidental zoom of the main
  // UI. That lock also blocks pinch-zoom on embedded PDF content on some
  // mobile browsers, so we relax it only while this viewer is on screen.
  void _relaxViewportZoomLock() {
    final meta = html.document.querySelector('meta[name="viewport"]');
    if (meta == null) return;
    _originalViewportContent = meta.getAttribute('content');
    meta.setAttribute('content',
        'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes, viewport-fit=cover');
  }

  void _restoreViewportZoomLock() {
    final meta = html.document.querySelector('meta[name="viewport"]');
    if (meta == null || _originalViewportContent == null) return;
    meta.setAttribute('content', _originalViewportContent!);
  }

  @override
  void dispose() {
    _restoreViewportZoomLock();
    super.dispose();
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
          tooltip: 'Close',
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
