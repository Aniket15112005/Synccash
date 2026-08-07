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
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

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
  bool _sharing = false;
  Timer? _loadingFallbackTimer;

  // Bytes are fetched in the background as soon as the viewer opens (see
  // _prefetchPdfBytes below) so the Share button already has the file ready
  // when tapped.
  Uint8List? _pdfBytes;
  Future<Uint8List>? _pdfBytesFuture;

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

    // Prefetch the PDF bytes in the background, well before the user taps
    // Share. This matters because the Web Share API's file-sharing path
    // (navigator.share({files: [...]})) only works inside a short-lived
    // "user activation" window right after a click. Previously we fetched
    // the PDF with `await http.get(...)` *inside* the Share button's
    // onPressed handler — by the time that network call finished, the
    // activation window had already expired, so the browser silently
    // rejected the file share and share_plus fell back to sharing a plain
    // link instead of the actual PDF. By fetching ahead of time here, the
    // bytes are normally already sitting in memory by the time the user
    // taps Share, so the call to Share.shareXFiles happens essentially
    // synchronously with the click and the native file-share path is used.
    _pdfBytesFuture = _fetchPdfBytes();

    // FIX (iOS PWA multi-page): Safari on iOS only renders the FIRST PAGE
    // when the iframe src is a remote HTTPS URL — the browser's built-in
    // PDF plugin does not scroll through pages in an inline iframe on iOS.
    // Once the bytes are already being fetched (above), create a Blob URL
    // from those bytes and swap the iframe src to it.  iOS Safari treats
    // Blob URLs as local resources and renders ALL pages with native
    // scrolling — identical to the desktop browser experience.
    _pdfBytesFuture!.then((bytes) {
      if (!mounted) return;
      try {
        final blob = html.Blob([bytes], 'application/pdf');
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        _iframeEl.src = blobUrl;
      } catch (_) {
        // Blob creation unsupported in this browser — keep the original URL
      }
    }).catchError((_) {
      // Fetch already failed; error state is handled via _errored flag
    });
  }

  Future<Uint8List> _fetchPdfBytes() async {
    final res = await http
        .get(Uri.parse(widget.url))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    _pdfBytes = res.bodyBytes;
    return res.bodyBytes;
  }

  void _stopLoading() {
    _loadingFallbackTimer?.cancel();
    if (mounted) setState(() => _loading = false);
  }

  // Shares the actual PDF file (not a link) — uses bytes prefetched in
  // initState so the call to Share.shareXFiles fires right on the click,
  // preserving the browser's user-activation window that the native
  // file-share path requires. No subject/description text is passed, so
  // recipients just get the file itself.
  Future<void> _sharePdf() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // If the prefetch already finished (the common case — the user has
      // usually been looking at the PDF for a moment before tapping Share),
      // this resolves with no additional await, keeping the share call
      // inside the click's activation window. If it hasn't finished yet,
      // we still wait for it rather than fail — a slightly delayed share
      // is better than a broken one — but this path should be rare.
      final bytes = _pdfBytes ?? await (_pdfBytesFuture ??= _fetchPdfBytes());
      final safeName = widget.billNumber.replaceAll(RegExp(r'[^\w\-]'), '_');
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: 'Invoice_$safeName.pdf',
          mimeType: 'application/pdf',
        ),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
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
        actions: [
          IconButton(
            onPressed: _sharing ? null : _sharePdf,
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white70, strokeWidth: 2),
                  )
                : const Icon(Icons.share_rounded, color: Colors.white70),
            tooltip: 'Share',
          ),
        ],
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
