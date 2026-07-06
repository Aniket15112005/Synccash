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
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _buffer = BytesBuilder();

  static const int _sampleRate = 16000;
  static const int _numChannels = 1;
  static const int _bitsPerSample = 16;

  // Which web codec actually got used — decided at start() time, since it
  // depends on what the browser supports (Chrome/Firefox: Opus, Safari:
  // typically AAC — Safari has historically not supported Opus in
  // MediaRecorder, including in iOS PWA contexts).
  String _webMimeType = 'audio/webm';

  /// Starts recording. Returns false if mic permission was denied.
  Future<bool> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    _buffer.clear();

    late final RecordConfig config;

    if (kIsWeb) {
      if (await _recorder.isEncoderSupported(AudioEncoder.opus)) {
        config = const RecordConfig(
          encoder: AudioEncoder.opus,
          numChannels: _numChannels,
        );
        _webMimeType = 'audio/ogg';
      } else if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
        config = const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: _numChannels,
        );
        _webMimeType = 'audio/aac';
      } else {
        // Last resort — let the browser pick whatever it can.
        config = const RecordConfig(numChannels: _numChannels);
        _webMimeType = 'audio/webm';
      }
    } else {
      // Native (Android/iOS): real PCM16 streaming actually works here,
      // so the original approach is correct on these platforms.
      config = const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: _numChannels,
      );
    }

    final stream = await _recorder.startStream(config);
    _sub = stream.listen((chunk) => _buffer.add(chunk));
    return true;
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
