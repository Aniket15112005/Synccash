import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Push-to-talk audio capture. Records only between start() and stop() —
/// no background/continuous listening. Uses `startStream` (raw PCM chunks)
/// instead of file-based recording so it works identically on web (needed
/// for iOS PWA users, where Safari blocks native speech APIs) and native
/// platforms — no platform-specific code branches needed.
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
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: _numChannels,
      ),
    );
    _sub = stream.listen((chunk) => _buffer.add(chunk));
    return true;
  }

  /// Stops recording and returns a valid WAV file (header + PCM data) as
  /// raw bytes, ready to send straight to Gemini.
  Future<Uint8List> stop() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;

    final pcmBytes = _buffer.takeBytes();
    if (pcmBytes.isEmpty) {
      throw Exception('No audio was recorded — please try again');
    }
    return _pcmToWav(pcmBytes);
  }

  /// `record`'s streaming mode gives raw PCM samples with no file header.
  /// Gemini expects a proper WAV file, so we prepend a standard 44-byte
  /// WAV header describing the format we recorded with.
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
