import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Push-to-talk audio capture. Records only between start() and stop().
///
/// Strategy per platform:
///   Web  — startStream + pcm16bits (browser MediaRecorder requires PCM),
///           raw samples are wrapped in a WAV header before sending to Gemini.
///   Native (Android / iOS)
///        — file-based recording with aacLc into a temp .m4a file.
///           startStream + aacLc is NOT supported by the record package on
///           native and throws AudioRecorderNotInitialisedException.
///           File-based recording is reliable on both platforms.
class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  // Web streaming state
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _buffer = BytesBuilder();

  // Native file-based state
  String? _nativeTempPath;

  static const int _sampleRate   = 16000;
  static const int _numChannels  = 1;
  static const int _bitsPerSample = 16;

  /// Starts recording. Returns false if mic permission was denied.
  Future<bool> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    if (kIsWeb) {
      _buffer.clear();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: _numChannels,
        ),
      );
      _sub = stream.listen((chunk) => _buffer.add(chunk));
    } else {
      // Native: file-based recording into a temp path.
      final dir = await getTemporaryDirectory();
      _nativeTempPath =
          '${dir.path}/synccash_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: _sampleRate,
          numChannels: _numChannels,
        ),
        path: _nativeTempPath!,
      );
    }
    return true;
  }

  /// Stops recording and returns bytes ready to send to Gemini.
  ///   Web    → WAV (PCM + 44-byte header)
  ///   Native → raw AAC/M4A bytes from the temp file
  Future<Uint8List> stop() async {
    if (kIsWeb) {
      try {
        await _recorder.stop();
      } catch (_) {
        // ignore stop errors — data is already in the buffer
      }
      await _sub?.cancel();
      _sub = null;

      final rawBytes = _buffer.takeBytes();
      if (rawBytes.isEmpty) {
        throw Exception('No audio was recorded — please try again');
      }
      return _pcmToWav(rawBytes);
    } else {
      // Native: stop() returns the path to the finished file.
      final returnedPath = await _recorder.stop();
      final filePath = returnedPath ?? _nativeTempPath;
      _nativeTempPath = null;

      if (filePath == null) {
        throw Exception('No audio file was created — please try again');
      }
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Audio file not found — please try again');
      }
      final bytes = await file.readAsBytes();
      file.delete().catchError((_) {}); // best-effort cleanup
      if (bytes.isEmpty) {
        throw Exception('No audio was recorded — please try again');
      }
      return bytes;
    }
  }

  /// Wraps raw PCM samples in a standard 44-byte WAV header so Gemini
  /// can parse the format. Only used on web (streaming PCM path).
  Uint8List _pcmToWav(Uint8List pcmData) {
    final byteRate    = _sampleRate * _numChannels * _bitsPerSample ~/ 8;
    final blockAlign  = _numChannels * _bitsPerSample ~/ 8;
    final dataLength  = pcmData.length;

    final header = BytesBuilder();
    void writeString(String s) => header.add(s.codeUnits);
    void writeUint32(int v) => header.add([
          v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff,
        ]);
    void writeUint16(int v) => header.add([v & 0xff, (v >> 8) & 0xff]);

    writeString('RIFF');
    writeUint32(36 + dataLength);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16);
    writeUint16(1);           // PCM
    writeUint16(_numChannels);
    writeUint32(_sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(_bitsPerSample);
    writeString('data');
    writeUint32(dataLength);

    final wav = BytesBuilder();
    wav.add(header.toBytes());
    wav.add(pcmData);
    return wav.toBytes();
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _recorder.dispose();
  }
}
