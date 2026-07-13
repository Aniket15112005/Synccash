// Web-only PDF/invoice viewer.
// Imported conditionally via `if (dart.library.html)` in bill_pdf_viewer_screen.dart.
//
// FIX — Pinch-to-zoom on Web / iOS PWA / Android PWA:
//
//   Root cause of the previous breakage: the old version displayed the PDF
//   inside an <iframe src="rawPdfUrl">. A cross-origin iframe has its own
//   browsing context — touch events over its content are dispatched to
//   *that* document, never to ours, no matter what listeners (even
//   capture-phase) are attached to the parent document. So pinch gestures
//   were never actually seen by our code.
//
//   Fix: render the PDF ourselves, onto <canvas> elements that live in our
//   own document (via pdf.js), instead of embedding it via iframe. With no
//   cross-frame boundary, touch events over the rendered pages are normal
//   DOM events we can listen to directly on our own container and use to
//   drive a CSS `transform: scale()` pinch-zoom, exactly as intended.
//
//   Requirement: pdf.js fetches the PDF's bytes itself (unlike an iframe,
//   which can just display a cross-origin URL without needing permission).
//   That fetch is subject to CORS, so the file's host must return
//   `Access-Control-Allow-Origin` on GET. For Firebase Storage:
//     gsutil cors set cors.json gs://<your-bucket>
//   cors.json:
//     [{"origin": ["*"], "method": ["GET"], "maxAgeSeconds": 3600}]

// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

const String _pdfJsUrl =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
const String _pdfJsWorkerUrl =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';

// Loaded once and reused by every viewer instance (sales / purchases / bills).
Future<void>? _pdfJsLoading;

Future<void> _ensurePdfJsLoaded() {
  if (_pdfJsLoading != null) return _pdfJsLoading!;

  _pdfJsLoading = () async {
    if (js_util.hasProperty(html.window, 'pdfjsLib')) return;

    final completer = Completer<void>();
    final script = html.ScriptElement()
      ..src = _pdfJsUrl
      ..type = 'application/javascript';
    script.onLoad.first.then((_) => completer.complete());
    script.onError.first
        .then((_) => completer.completeError('Failed to load pdf.js'));
    html.document.head!.append(script);
    await completer.future;

    final lib = js_util.getProperty(html.window, 'pdfjsLib');
    final workerOptions = js_util.getProperty(lib, 'GlobalWorkerOptions');
    js_util.setProperty(workerOptions, 'workerSrc', _pdfJsWorkerUrl);
  }();

  return _pdfJsLoading!;
}

void openPdfInApp(
    BuildContext context, String url, String billNumber, String clientName) {
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

// ─────────────────────────────────────────────────────────────────────────────

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

  // DOM refs.
  late html.DivElement _containerEl; // scrollable viewport (overflow: auto)
  late html.DivElement _scaleEl; // transform: scale(S) wrapper, holds pages

  bool _loading = true;
  bool _errored = false;

  // Pinch-zoom state.
  bool _pinching = false;
  double _startDist = 0.0;
  double _baseScale = 1.0;
  double _scale = 1.0;

  late final html.EventListener _onTouchStart;
  late final html.EventListener _onTouchMove;
  late final html.EventListener _onTouchEnd;

  @override
  void initState() {
    super.initState();

    _viewId = 'purchase-invoice-pdf-${widget.billNumber}-${widget.url.hashCode}';

    // Build the DOM tree:
    //   containerEl (overflow-y: auto — native single-finger scroll)
    //     └─ scaleEl (transform: scale(S), pages stacked vertically)
    //          └─ <canvas> per page, rendered by pdf.js
    _scaleEl = html.DivElement()
      ..style.transformOrigin = '50% 0%'
      ..style.transform = 'scale(1)'
      ..style.display = 'flex'
      ..style.flexDirection = 'column'
      ..style.alignItems = 'center'
      ..style.width = '100%';

    _containerEl = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.overflowY = 'auto'
      ..style.overflowX = 'hidden'
      ..style.background = '#080A0E'
      ..style.setProperty('-webkit-overflow-scrolling', 'touch')
      ..style.setProperty('touch-action', 'pan-y')
      ..append(_scaleEl);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int id) => _containerEl,
    );

    // ── Touch listeners on OUR OWN container ───────────────────────────────
    // No iframe boundary anymore, so these reliably see every touch,
    // including ones over the rendered PDF pages.
    _onTouchStart = (html.Event raw) {
      final e = raw as html.TouchEvent;
      if ((e.touches?.length ?? 0) >= 2) {
        _pinching = true;
        _startDist = _touchDistance(e.touches!);
        _baseScale = _scale;
      }
    };

    _onTouchMove = (html.Event raw) {
      if (!_pinching) return;
      final e = raw as html.TouchEvent;
      if ((e.touches?.length ?? 0) < 2) return;
      final dist = _touchDistance(e.touches!);
      if (_startDist > 0) {
        _applyScale(_baseScale * (dist / _startDist));
      }
      e.preventDefault();
    };

    _onTouchEnd = (html.Event raw) {
      final e = raw as html.TouchEvent;
      if ((e.touches?.length ?? 0) < 2) _pinching = false;
    };

    _containerEl.addEventListener('touchstart', _onTouchStart);
    _containerEl.addEventListener('touchmove', _onTouchMove);
    _containerEl.addEventListener('touchend', _onTouchEnd);
    _containerEl.addEventListener('touchcancel', _onTouchEnd);

    _renderPdf();
  }

  Future<void> _renderPdf() async {
    try {
      await _ensurePdfJsLoaded();
      final lib = js_util.getProperty(html.window, 'pdfjsLib');

      final params = js_util.newObject();
      js_util.setProperty(params, 'url', widget.url);
      js_util.setProperty(params, 'withCredentials', false);

      final loadingTask = js_util.callMethod(lib, 'getDocument', [params]);
      final pdfDoc = await js_util.promiseToFuture(
        js_util.getProperty(loadingTask, 'promise'),
      );

      final numPages = js_util.getProperty(pdfDoc, 'numPages') as int;
      final dpr = html.window.devicePixelRatio;
      // Full-screen viewer, so window width is a reliable "fit" target even
      // before the platform view has been laid out.
      final cssWidth = html.window.innerWidth!.toDouble();

      for (var i = 1; i <= numPages; i++) {
        final page = await js_util.promiseToFuture(
          js_util.callMethod(pdfDoc, 'getPage', [i]),
        );

        final probeViewport = js_util.callMethod(
          page,
          'getViewport',
          [js_util.jsify({'scale': 1})],
        );
        final nativeWidth =
            (js_util.getProperty(probeViewport, 'width') as num).toDouble();
        final fitScale = cssWidth / nativeWidth;

        final viewport = js_util.callMethod(
          page,
          'getViewport',
          [js_util.jsify({'scale': fitScale * dpr})],
        );
        final vpWidth = (js_util.getProperty(viewport, 'width') as num);
        final vpHeight = (js_util.getProperty(viewport, 'height') as num);

        final canvas = html.CanvasElement(
          width: vpWidth.round(),
          height: vpHeight.round(),
        )
          ..style.width = '${vpWidth / dpr}px'
          ..style.height = '${vpHeight / dpr}px'
          ..style.display = 'block'
          ..style.margin = '0 0 8px 0'
          ..style.setProperty('user-select', 'none')
          ..style.setProperty('-webkit-user-select', 'none');

        final ctx = canvas.context2D;
        final renderContext = js_util.newObject();
        js_util.setProperty(renderContext, 'canvasContext', ctx);
        js_util.setProperty(renderContext, 'viewport', viewport);

        await js_util.promiseToFuture(
          js_util.callMethod(page, 'render', [renderContext]),
        );

        _scaleEl.append(canvas);
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errored = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _containerEl.removeEventListener('touchstart', _onTouchStart);
    _containerEl.removeEventListener('touchmove', _onTouchMove);
    _containerEl.removeEventListener('touchend', _onTouchEnd);
    _containerEl.removeEventListener('touchcancel', _onTouchEnd);
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  double _touchDistance(html.TouchList touches) {
    final t0 = touches.item(0)! as dynamic;
    final t1 = touches.item(1)! as dynamic;
    final dx = ((t0.clientX as num) - (t1.clientX as num)).toDouble();
    final dy = ((t0.clientY as num) - (t1.clientY as num)).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  void _applyScale(double newScale) {
    _scale = newScale.clamp(1.0, 4.0);
    _scaleEl.style.transform = 'scale($_scale)';
  }

  /// Reset zoom to 1× (called by the AppBar button).
  void _resetZoom() {
    _applyScale(1.0);
    _containerEl.scrollTop = 0;
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
            Text(widget.clientName,
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
            onPressed: _resetZoom,
            icon: const Icon(Icons.zoom_out_map_rounded,
                color: Colors.white70, size: 20),
            tooltip: 'Reset zoom',
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
                  const SizedBox(height: 4),
                  const Text(
                    'Check that CORS is enabled on the file host.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
