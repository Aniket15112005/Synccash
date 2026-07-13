// Web-only PDF/invoice viewer using iframe.
// Imported conditionally via `if (dart.library.html)` in bill_pdf_viewer_screen.dart.
//
// FIX — Pinch-to-zoom on Web / iOS PWA / Android PWA:
//
//   Root cause: Flutter Web renders to a <canvas>/<flt-glass-pane> element.
//   HtmlElementView embeds the iframe as a separate DOM platform-view layer.
//   Touch events that land inside the iframe go directly to the browser DOM
//   and never reach Flutter's gesture system, so InteractiveViewer (the
//   previous approach) never receives pinch events and zoom was broken on
//   all web/PWA targets.
//
//   Fix: Attach touchstart / touchmove / touchend listeners in capture phase
//   on document. When 2+ fingers are detected we:
//     1. Prevent the event from reaching the iframe (stopPropagation).
//     2. Apply a CSS transform: scale() to a wrapper <div> around the iframe.
//     3. Re-enable normal iframe pointer events as soon as the pinch ends.
//   Single-finger touches are never intercepted, so PDF scrolling continues
//   to work exactly as before.
//
//   We do NOT touch the page's <meta name="viewport"> tag. A previous version
//   of this screen unlocked the viewport to allow native browser pinch-zoom;
//   that caused two regressions:
//     1. The close (X) button becoming unresponsive — modifying the viewport
//        while an HtmlElementView is mounted desyncs DOM coordinates Flutter
//        uses for hit-testing.
//     2. On iOS standalone PWA a large zoom-out was interpreted as a dismiss
//        gesture, closing the app.
//   The viewport stays locked at maximum-scale=1. All zoom is CSS-only.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:math' as math;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

void openPdfInApp(BuildContext context, String url, String billNumber,
    String partyName) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _WebInvoiceViewerPage(
        url:        url,
        billNumber: billNumber,
        partyName:  partyName,
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

  // DOM refs — set once inside the view factory, used in touch listeners.
  late html.DivElement  _containerEl;
  late html.DivElement  _scaleEl;
  late html.IFrameElement _iframeEl;

  // Pinch-zoom state.
  bool   _pinching   = false;
  double _startDist  = 0.0;
  double _baseScale  = 1.0;
  double _scale      = 1.0;   // current applied scale

  // Capture-phase document listeners (stored so we can remove them).
  late final html.EventListener _onTouchStart;
  late final html.EventListener _onTouchMove;
  late final html.EventListener _onTouchEnd;

  @override
  void initState() {
    super.initState();

    // Unique view-type id — must be registered before the widget is built.
    _viewId = 'web-invoice-pdf-${widget.billNumber}-${widget.url.hashCode}';

    // Build the DOM tree:
    //   containerEl  (overflow: hidden, full size, holds the platform view)
    //     └─ scaleEl (transform: scale(S), scaled from top-centre)
    //          └─ iframeEl (width/height 100%, no border)
    _iframeEl = html.IFrameElement()
      ..src = widget.url
      ..style.border = 'none'
      ..style.width  = '100%'
      ..style.height = '100%'
      ..style.setProperty('touch-action', 'auto')
      ..style.setProperty('-webkit-overflow-scrolling', 'touch')
      ..allow = 'fullscreen';

    _scaleEl = html.DivElement()
      ..style.width           = '100%'
      ..style.height          = '100%'
      ..style.transformOrigin = '50% 0%'   // zoom anchored to top-centre
      ..style.transform       = 'scale(1)'
      ..append(_iframeEl);

    _containerEl = html.DivElement()
      ..style.width    = '100%'
      ..style.height   = '100%'
      ..style.overflow = 'hidden'
      ..append(_scaleEl);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int id) => _containerEl,
    );

    // ── Capture-phase touch listeners ────────────────────────────────────────
    // These fire BEFORE any element (including the iframe) receives the event,
    // giving us first-refusal on multi-touch gestures.

    _onTouchStart = (html.Event raw) {
      final e = raw as html.TouchEvent;
      if ((e.touches?.length ?? 0) >= 2) {
        // Two-finger gesture starting — begin pinch tracking.
        _pinching  = true;
        _startDist = _touchDistance(e.touches!);
        _baseScale = _scale;

        // Block the iframe from receiving this event so it doesn't
        // try to scroll while we are zooming.
        _iframeEl.style.pointerEvents = 'none';
        e.stopPropagation();
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
      // Prevent browser scroll / default zoom behaviour.
      e.preventDefault();
      e.stopPropagation();
    };

    _onTouchEnd = (html.Event raw) {
      final e = raw as html.TouchEvent;
      if ((e.touches?.length ?? 0) < 2) {
        // Fewer than two fingers remain — pinch is over.
        _pinching = false;
        _iframeEl.style.pointerEvents = 'auto';
      }
    };

    // Register in capture phase (useCapture = true) so we intercept before
    // the browser dispatches to the iframe's DOM subtree.
    html.document.addEventListener('touchstart', _onTouchStart, true);
    html.document.addEventListener('touchmove',  _onTouchMove,  true);
    html.document.addEventListener('touchend',   _onTouchEnd,   true);
    html.document.addEventListener('touchcancel',_onTouchEnd,   true);
  }

  @override
  void dispose() {
    html.document.removeEventListener('touchstart', _onTouchStart, true);
    html.document.removeEventListener('touchmove',  _onTouchMove,  true);
    html.document.removeEventListener('touchend',   _onTouchEnd,   true);
    html.document.removeEventListener('touchcancel',_onTouchEnd,   true);
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Euclidean distance between the first two touches.
  double _touchDistance(html.TouchList touches) {
    final t0 = touches.item(0)! as dynamic;
    final t1 = touches.item(1)! as dynamic;
    final dx = ((t0.clientX as num) - (t1.clientX as num)).toDouble();
    final dy = ((t0.clientY as num) - (t1.clientY as num)).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Clamp and apply [newScale] as a CSS transform on the scale wrapper.
  void _applyScale(double newScale) {
    _scale = newScale.clamp(0.5, 4.0);
    _scaleEl.style.transform = 'scale($_scale)';
  }

  /// Reset zoom to 1× (called by the AppBar button).
  void _resetZoom() {
    _applyScale(1.0);
    // Scroll container back to top after reset so the PDF header is visible.
    _containerEl.scrollTop = 0;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

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
      // The iframe fills the body. Pinch events are handled by the
      // document-level capture listeners above — no InteractiveViewer needed.
      body: HtmlElementView(viewType: _viewId),
    );
  }
}
