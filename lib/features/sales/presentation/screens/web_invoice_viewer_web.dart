// Web-only PDF/invoice viewer.
// Imported conditionally via `if (dart.library.html)` in bill_pdf_viewer_screen.dart.
//
// Renders the PDF via a same-document <iframe src="rawPdfUrl">. The browser's
// own native PDF plugin handles paging, native pinch-zoom (on touch devices)
// and scrolling — no bytes are fetched by our code, so this never depends on
// the file host sending CORS headers. Nothing is opened in a new tab or via
// a third-party viewer; the PDF renders inside this in-app screen.

// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

void openPdfInApp(
    BuildContext context, String url, String billNumber, String partyName) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _WebInvoiceViewerPage(
        url: url,
        billNumber: billNumber,
        partyName: partyName,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _WebInvoiceViewerPage extends StatefulWidget {
  final String url;
  final String billNumber;
  final String partyName;

  const _WebInvoiceViewerPage({
    required this.url,
    required this.billNumber,
    required this.partyName,
  });

  @override
  State<_WebInvoiceViewerPage> createState() => _WebInvoiceViewerPageState();
}

class _WebInvoiceViewerPageState extends State<_WebInvoiceViewerPage> {
  late final String _viewId;
  late final html.IFrameElement _iframeEl;

  bool _loading = true;
  bool _errored = false;
  Timer? _loadingFallbackTimer;

  @override
  void initState() {
    super.initState();

    // FIX: viewId must be unique per screen instance, not just per
    // bill/URL. Reopening the same invoice previously reused the same
    // viewId, which made registerViewFactory throw/no-op on the second
    // open (Flutter Web disallows re-registering a viewType) — no new
    // iframe was created, onLoad never fired, and the spinner spun
    // forever even though nothing was actually broken underneath.
    _viewId =
        'web-invoice-pdf-${widget.billNumber}-${widget.url.hashCode}-'
        '${DateTime.now().microsecondsSinceEpoch}';

    _iframeEl = html.IFrameElement()
      ..src = widget.url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.background = '#080A0E';

    _iframeEl.onLoad.first.then((_) {
      if (mounted) _stopLoading();
    });
    _iframeEl.onError.first.then((_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errored = true;
        });
      }
    });

    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int id) => _iframeEl,
    );

    // FIX: the iframe's native `load` event is unreliable for PDFs across
    // browsers — Safari/Chrome frequently never fire it (or fire it for an
    // intermediate blank navigation) once the built-in PDF plugin takes
    // over rendering. That left `_loading` stuck at true indefinitely even
    // though the PDF was already visibly rendered behind the spinner. This
    // fallback guarantees the spinner clears shortly after the PDF has had
    // time to render, regardless of whether the browser ever fires `load`.
    _loadingFallbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _stopLoading();
    });
  }

  void _stopLoading() {
    _loadingFallbackTimer?.cancel();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _loadingFallbackTimer?.cancel();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────

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
            Text(widget.partyName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            Text('Invoice  #${widget.billNumber}',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
      body: Stack(
        children: [
          HtmlElementView(viewType: _viewId),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF6C7FE4), strokeWidth: 2.5),
            ),
          if (_errored && !_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.picture_as_pdf_outlined,
                      color: Colors.white38, size: 52),
                  const SizedBox(height: 12),
                  const Text('Could not load PDF',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
