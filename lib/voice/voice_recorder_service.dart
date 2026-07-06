import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Result of a recording: raw bytes + the mime type they're actually in.
/// Both native and web now stream raw PCM16 samples (see start() below),
/// wrapped in a WAV header — so both branches always report 'audio/wav'.
class RecordedAudio {
  final Uint8List bytes;
  final String mimeType;
  RecordedAudio(this.bytes, this.mimeType);
}

/// Push-to-talk audio capture. Records only between start() and stop().
///
/// HISTORY / WHY THIS LOOKS THE WAY IT DOES:
/// Earlier versions of this file tried to pick a browser-native encoded
/// format for web (Opus/OGG, then AAC/MP4, then "whatever the browser
/// defaults to") because of an old assumption that `record`'s web backend
/// couldn't produce real PCM and would silently substitute Opus instead.
/// That assumption no longer holds for the version of the `record` package
/// this app uses — and more importantly, none of those encoded-format
/// attempts were ever going to work in the first place: `record`'s own
/// published platform-support matrix states plainly that `startStream()`
/// in STREAM mode only supports `AudioEncoder.pcm16bits` on web — encoded
/// formats like Opus/AAC are not implemented for web streaming at all,
/// on ANY browser. That's why every encoded-format attempt failed with
/// "Stream not supported" on iOS: it was never an iOS-only quirk, it was
/// this app asking the web platform to do something the package's web
/// backend doesn't implement, full stop.
///
/// THE FIX: use the exact same pcm16bits config on web as on native, and
/// wrap the resulting raw samples in a WAV header exactly like native
/// already does. No more browser/codec detection needed anywhere.
class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _buffer = BytesBuilder();

  static const int _sampleRate = 16000;
  static const int _numChannels = 1;
  static const int _bitsPerSample = 16;

  /// Starts recording. Returns false if mic permission was denied.
  Future<bool> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    _buffer.clear();

    // Same config on every platform — pcm16bits is the one stream encoder
    // guaranteed to work on native Android/iOS AND on web (Chrome, Firefox,
    // Safari, and Safari-based iOS PWAs alike).
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
      throw Exception('Could not start recording: $e');
    }
  }

  /// Stops recording and returns the audio bytes plus their mime type.
  Future<RecordedAudio> stop() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;

    final rawBytes = _buffer.takeBytes();
    if (rawBytes.isEmpty) {
      throw Exception('No audio was recorded — please try again');
    }

    // Both native and web now stream raw PCM16 samples with no file header
    // (see start() above), so both need the same WAV header wrapping.
    return RecordedAudio(_pcmToWav(rawBytes), 'audio/wav');
  }

  /// `record`'s streaming mode gives raw PCM samples with no file header,
  /// so we prepend a standard 44-byte WAV header describing the format we
  /// recorded with. Only valid to call with genuine PCM16 bytes — which is
  /// now what start() always produces, on every platform.
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
