// Web-only PDF/invoice viewer using iframe.
// Imported conditionally via `if (dart.library.html)` in purchase_client_detail_screen.dart
//
// Renders the PDF directly (no Google Docs Viewer round trip) so the
// browser's own PDF engine handles it: faster (one network hop instead of
// two).
//
// IMPORTANT: zoom is handled entirely inside Flutter via InteractiveViewer.
// A previous version of this screen temporarily rewrote the page's
// <meta name="viewport"> tag to allow native browser pinch-zoom. That was
// the root cause of two bugs:
//   1. The close (X) button becoming unresponsive — changing the page
//      viewport while an HtmlElementView (iframe) is mounted desyncs the
//      DOM coordinates Flutter uses to position/hit-test that platform
//      view, so taps could land in the wrong place.
//   2. Zooming all the way out closing the app — with the page viewport
//      unlocked, a large pinch-zoom-out on an iOS home-screen (standalone)
//      PWA can be interpreted by iOS as a dismiss/back gesture.
// Keeping the global viewport permanently locked and doing zoom with
// InteractiveViewer avoids both: the browser viewport is never touched.

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
  final TransformationController _transformCtrl = TransformationController();

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
        ..style.setProperty('touch-action', 'auto')
        ..style.setProperty('-webkit-overflow-scrolling', 'touch')
        ..allow = 'fullscreen';
    });
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformCtrl.value = Matrix4.identity();
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
        actions: [
          IconButton(
            onPressed: _resetZoom,
            icon: const Icon(Icons.zoom_out_map_rounded,
                color: Colors.white70, size: 20),
            tooltip: 'Reset zoom',
          ),
        ],
      ),
      // Pinch-to-zoom is handled entirely by Flutter (InteractiveViewer),
      // never by the browser page itself — see file header comment.
      // panEnabled is off so a single-finger drag still scrolls the PDF
      // inside the iframe normally; only a two-finger pinch is captured
      // here to scale it.
      body: InteractiveViewer(
        transformationController: _transformCtrl,
        panEnabled: false,
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: 4.0,
        child: HtmlElementView(viewType: _viewId),
      ),
    );
  }
}
