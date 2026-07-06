import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

/// Result of a recording: raw bytes + the mime type they're actually in.
/// Native platforms give real PCM16 (wrapped as WAV here). Web gives
/// whatever container/codec the browser's MediaRecorder actually used —
/// which is NOT PCM, no matter what encoder you ask for.
class RecordedAudio {
  final Uint8List bytes;
  final String mimeType;
  RecordedAudio(this.bytes, this.mimeType);
}

/// Push-to-talk audio capture. Records only between start() and stop().
///
/// IMPORTANT: `record`'s web backend is built on the browser's
/// MediaRecorder API, which cannot produce raw PCM. Even when you request
/// AudioEncoder.pcm16bits on web, it silently records Opus (usually in a
/// WebM container, sometimes AAC/MP4 on Safari) instead — with no error,
/// no warning your app sees. Treating those bytes as PCM and wrapping
/// them in a fake WAV header (the old bug) produces a corrupt file that
/// no STT API can read. Fix: on web, record in whatever the browser
/// actually supports, and pass the REAL mime type through — don't fake WAV.
class VoiceRecorderService {
  // NOT final anymore: on web, a failed startStream() attempt on one
  // AudioRecorder instance can leave its underlying MediaStreamTrack
  // "ended" — reusing that same instance for the next fallback candidate
  // then fails with the exact same error regardless of codec. start()
  // swaps this to a fresh instance per successful attempt; see below.
  AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _buffer = BytesBuilder();

  static const int _sampleRate = 16000;
  static const int _numChannels = 1;
  static const int _bitsPerSample = 16;

  // Which web codec actually got used — decided at start() time, since it
  // depends on what the browser actually accepted (see start() below —
  // this is now set only once startStream() has genuinely succeeded with
  // that format, not from an upfront guess).
  String _webMimeType = 'audio/webm';

  /// Starts recording. Returns false if mic permission was denied.
  Future<bool> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    _buffer.clear();

    if (!kIsWeb) {
      // Native (Android/iOS): real PCM16 streaming actually works here,
      // so the original approach is correct on these platforms.
      // UNCHANGED — Android relies on this exact path working as-is. The
      // try/catch below changes nothing about the success path; it only
      // gives a clearer error message in the hypothetical case this ever
      // throws, instead of an unhandled exception with no context.
      final config = const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: _numChannels,
      );
      try {
        final stream = await _recorder.startStream(config);
        _sub = stream.listen((chunk) => _buffer.add(chunk));
        return true;
      } catch (e) {
        throw Exception('Could not start recording (audio/wav): $e');
      }
    }

    // ── Web (includes Android web/PWA and iOS Safari/PWA) ──────────────
    //
    // FIX: iOS Safari has been observed to report
    // isEncoderSupported(AudioEncoder.opus) == true and then throw
    // "Stream not supported" the instant startStream() actually tries to
    // use it — i.e. the feature-detection check itself lies on iOS. The
    // old code trusted that single upfront check and picked ONE config,
    // so when it lied, the whole start() call threw with nothing to fall
    // back to.
    //
    // Now: try each candidate format in order, and only move to the next
    // one if ACTUALLY starting the stream throws — never trust the
    // upfront check as the final word. AAC/MP4 is the one format that has
    // reliably worked on Safari in testing, so it's always in the chain
    // regardless of what isEncoderSupported claims. This changes nothing
    // for Chrome/Firefox: Opus is genuinely supported there, so the first
    // candidate always succeeds immediately, same as before.
    bool opusSupported = false;
    try {
      opusSupported = await _recorder.isEncoderSupported(AudioEncoder.opus);
    } catch (_) {
      opusSupported = false;
    }

    final candidates = <(RecordConfig config, String mimeType)>[
      if (opusSupported)
        (
          const RecordConfig(encoder: AudioEncoder.opus, numChannels: _numChannels),
          'audio/ogg',
        ),
      (
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: _numChannels),
        'audio/mp4',
      ),
      // Last resort — let the browser pick whatever default it can.
      (
        const RecordConfig(numChannels: _numChannels),
        'audio/webm',
      ),
    ];

    Object? lastError;
    for (final candidate in candidates) {
      // FIX: reusing the same AudioRecorder/stream across attempts meant
      // that once one attempt died, EVERY later candidate failed with the
      // identical error too (same dead MediaStreamTrack underneath),
      // making the fallback chain pointless in practice. Each attempt now
      // gets its own fresh instance — and therefore its own fresh
      // getUserMedia() stream — so a dead track from a failed try can't
      // carry over and poison the next candidate.
      final recorder = AudioRecorder();
      try {
        final hasPerm = await recorder.hasPermission();
        if (!hasPerm) {
          lastError = Exception('permission unavailable on retry');
          try { await recorder.dispose(); } catch (_) {}
          continue;
        }
        final stream = await recorder.startStream(candidate.$1);
        // Success — this instance becomes the "live" recorder; dispose
        // the old one (from a previous failed attempt, or the initial
        // permission-check instance) now that it's no longer needed.
        if (!identical(recorder, _recorder)) {
          try { await _recorder.dispose(); } catch (_) {}
        }
        _recorder = recorder;
        _sub = stream.listen((chunk) => _buffer.add(chunk));
        _webMimeType = candidate.$2;
        return true;
      } catch (e) {
        lastError = e;
        try { await recorder.dispose(); } catch (_) {}
      }
    }

    // Every candidate failed for real (not just the detection check) —
    // surface the actual browser error instead of the previous silent
    // failure/uncaught exception.
    throw Exception('Could not start recording on this browser: $lastError');
  }

  /// Stops recording and returns the audio bytes plus their real mime type.
  Future<RecordedAudio> stop() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;

    final rawBytes = _buffer.takeBytes();
    if (rawBytes.isEmpty) {
      throw Exception('No audio was recorded — please try again');
    }

    if (kIsWeb) {
      // Already a complete, valid audio file in whatever codec was chosen
      // above. Do NOT wrap it in a fake WAV header.
      assert(() {
        // ignore: avoid_print
        print('[VoiceRecorderService] web recording: '
            '$_webMimeType, ${rawBytes.length} bytes');
        return true;
      }());
      return RecordedAudio(rawBytes, _webMimeType);
    } else {
      return RecordedAudio(_pcmToWav(rawBytes), 'audio/wav');
    }
  }

  /// `record`'s native streaming mode gives raw PCM samples with no file
  /// header, so we prepend a standard 44-byte WAV header describing the
  /// format we recorded with. Only valid to call with genuine PCM16 bytes
  /// (i.e. native platforms) — never call this on web-recorded bytes.
  Uint8List _pcmToWav(Uint8List pcmData) {
    final byteRate = _sampleRate * _numChannels * _bitsPerSample ~/ 8;
    final blockAlign = _numChannels * _bitsPerSample ~/ 8;
    final dataLength = pcmData.length;

    final header = BytesBuilder();
    void writeString(String s) => header.add(s.codeUnits);
    void writeUint32(int v) => header.add([
          v & 0xff,
          (v >> 8) & 0xff,
          (v >> 16) & 0xff,
          (v >> 24) & 0xff,
        ]);
    void writeUint16(int v) => header.add([v & 0xff, (v >> 8) & 0xff]);

    writeString('RIFF');
    writeUint32(36 + dataLength);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16); // PCM fmt chunk size
    writeUint16(1); // audio format = PCM
    writeUint16(_numChannels);
    writeUint32(_sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(_bitsPerSample);
    writeString('data');
    writeUint32(dataLength);

    final wavFile = BytesBuilder();
    wavFile.add(header.toBytes());
    wavFile.add(pcmData);
    return wavFile.toBytes();
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _recorder.dispose();
  }
}
