// In-app PDF viewer for native Android & iOS.
// Uses WebView + Google Docs viewer so PDFs render inside the app with
// pinch-to-zoom and no OS hand-off.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  late final WebViewController _controller;
  bool _loading = true;
  bool _errored = false;

  static const _accent = Color(0xFF6C63FF);

  @override
  void initState() {
    super.initState();

    // Google Docs Viewer renders the PDF as HTML — works on every platform
    // that has a WebView and supports pinch-to-zoom natively.
    final viewerUrl =
        'https://docs.google.com/viewer?embedded=true&url='
        '${Uri.encodeComponent(widget.url)}';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (_) {
          if (mounted) setState(() { _loading = false; _errored = true; });
        },
      ))
      ..loadRequest(Uri.parse(viewerUrl));
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
          // Reload in case Google Docs Viewer shows a "preview not available" page
          IconButton(
            onPressed: () {
              setState(() { _loading = true; _errored = false; });
              _controller.reload();
            },
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),

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
                    onPressed: () {
                      setState(() { _loading = true; _errored = false; });
                      _controller.reload();
                    },
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
