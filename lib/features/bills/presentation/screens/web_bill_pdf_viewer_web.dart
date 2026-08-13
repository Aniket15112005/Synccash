// Web-only PDF viewer for custom bills.
//
// Pages are rendered by pdf.js through pdfx instead of the browser's native
// PDF plug-in. Safari on iOS can then render every page in a standalone PWA,
// just as desktop browsers do.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

void openPdfInApp(
    BuildContext context, String url, String billNumber, String clientName) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _WebBillPdfViewerPage(
        url: url,
        billNumber: billNumber,
        clientName: clientName,
      ),
    ),
  );
}

class _WebBillPdfViewerPage extends StatefulWidget {
  final String url;
  final String billNumber;
  final String clientName;

  const _WebBillPdfViewerPage({
    required this.url,
    required this.billNumber,
    required this.clientName,
  });

  @override
  State<_WebBillPdfViewerPage> createState() => _WebBillPdfViewerPageState();
}

class _WebBillPdfViewerPageState extends State<_WebBillPdfViewerPage> {
  bool _loading = true;
  bool _errored = false;
  bool _sharing = false;
  Uint8List? _pdfBytes;
  late final Future<Uint8List> _pdfBytesFuture;
  late final PdfControllerPinch _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfBytesFuture = _fetchPdfBytes();
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openData(_pdfBytesFuture),
    );
  }

  Future<Uint8List> _fetchPdfBytes() async {
    final response = await http
        .get(Uri.parse(widget.url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    _pdfBytes = response.bodyBytes;
    return response.bodyBytes;
  }

  Future<void> _sharePdf() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = _pdfBytes ?? await _pdfBytesFuture;
      final safeName = widget.billNumber.replaceAll(RegExp(r'[^\w\-]'), '_');
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: 'Bill_$safeName.pdf',
          mimeType: 'application/pdf',
        ),
      ]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
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
            Text(
              widget.clientName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Bill  #${widget.billNumber}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
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
                      color: Colors.white70,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.share_rounded, color: Colors.white70),
            tooltip: 'Share',
          ),
        ],
      ),
      body: Stack(
        children: [
          PdfViewPinch(
            controller: _pdfController,
            padding: 12,
            backgroundDecoration: const BoxDecoration(
              color: Color(0xFF080A0E),
            ),
            onDocumentLoaded: (_) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _errored = false;
                });
              }
            },
            onDocumentError: (_) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _errored = true;
                });
              }
            },
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF6C7FE4),
                strokeWidth: 2.5,
              ),
            ),
          if (_errored && !_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Colors.white38,
                    size: 52,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Could not load PDF',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
