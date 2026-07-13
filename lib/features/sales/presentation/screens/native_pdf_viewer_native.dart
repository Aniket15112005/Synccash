// In-app PDF viewer for native Android & iOS.
//
// Renders the PDF locally with flutter_pdfview instead of round-tripping
// through Google Docs Viewer. This gives real native pinch-to-zoom and is
// much faster: the file is downloaded once (and cached) and rendered
// on-device, with no dependency on an external conversion service.
//
// FIX: Added gestureRecognizers to forward ScaleGestureRecognizer to the
// platform view. Without this, Flutter's gesture arena wins on pinch events
// and the native PDF renderer never receives them — so zoom didn't work.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void openNativePdfInApp(
  BuildContext context,
  String url,
  String billNumber,
  String partyName,
) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _NativePdfViewerPage(
        url:        url,
        billNumber: billNumber,
        partyName:  partyName,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _NativePdfViewerPage extends StatefulWidget {
  final String url;
  final String billNumber;
  final String partyName;

  const _NativePdfViewerPage({
    required this.url,
    required this.billNumber,
    required this.partyName,
  });

  @override
  State<_NativePdfViewerPage> createState() => _NativePdfViewerPageState();
}

class _NativePdfViewerPageState extends State<_NativePdfViewerPage> {
  static const _accent = Color(0xFF6C63FF);

  bool _loading = true;
  bool _errored = false;
  String? _filePath;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    if (mounted) setState(() { _loading = true; _errored = false; });
    try {
      // Cache by URL hash so re-opening the same invoice is instant.
      final dir  = await getTemporaryDirectory();
      final hash = widget.url.hashCode.toUnsigned(32).toRadixString(16);
      final file = File('${dir.path}/pdf_cache_$hash.pdf');

      if (!await file.exists()) {
        final res = await http
            .get(Uri.parse(widget.url))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }
        await file.writeAsBytes(res.bodyBytes, flush: true);
      }

      if (!mounted) return;
      setState(() {
        _filePath = file.path;
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _errored = true; });
    }
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
            Text(
              widget.partyName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Invoice  #${widget.billNumber}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadPdf,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_filePath != null)
            PDFView(
              filePath: _filePath!,
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: true,
              pageFling: false,
              pageSnap: false,
              fitPolicy: FitPolicy.WIDTH,
              // FIX: Forward pinch/scale gestures to the native platform view.
              // Without this set, Flutter's own gesture arena consumes scale
              // events before the underlying Android PdfViewer / iOS WKWebView
              // renderer ever sees them, making pinch-to-zoom impossible.
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<ScaleGestureRecognizer>(
                  () => ScaleGestureRecognizer(),
                ),
              },
              onRender: (pages) {
                if (mounted) setState(() => _pages = pages ?? 0);
              },
              onError: (_) {
                if (mounted) setState(() => _errored = true);
              },
              onPageError: (_, __) {},
            ),

          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                color: _accent, strokeWidth: 2.5,
              ),
            ),

          if (_errored && !_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.picture_as_pdf_outlined,
                      color: Colors.white38, size: 52),
                  const SizedBox(height: 12),
                  const Text(
                    'Could not load PDF',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _loadPdf,
                    icon: const Icon(Icons.refresh_rounded, color: _accent),
                    label: const Text('Try again',
                        style: TextStyle(color: _accent)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
