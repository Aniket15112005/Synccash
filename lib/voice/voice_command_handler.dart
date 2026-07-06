// lib/voice/voice_command_handler.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'voice_recorder_service.dart';
import 'ai_command_fallback.dart';
import 'parsed_entry.dart';

enum VoiceStatus { idle, listening, processing, done, error }

typedef VoiceStatusCallback = void Function(VoiceStatus status, String? hint);

class VoiceCommandHandler {
  VoiceCommandHandler({required this.apiKey});

  final String apiKey; // your GROQ_API_KEY
  final _recorder = VoiceRecorderService();

  VoiceStatusCallback?               _onStatus;
  void Function(ParsedEntry entry)?  _onResult;
  void Function(String error)?       _onError;

  bool _listening = false;

  Future<void> startListening({
    String localeId = 'hi-IN',
    required VoiceStatusCallback           onStatus,
    required void Function(ParsedEntry)    onResult,
    required void Function(String error)   onError,
  }) async {
    if (_listening) return;

    _onStatus  = onStatus;
    _onResult  = onResult;
    _onError   = onError;
    _listening = true;

    // Give instant visual feedback BEFORE waiting for recorder permission
    onStatus(VoiceStatus.listening, null);

    final started = await _recorder.start();
    if (!started) {
      _listening = false;
      onStatus(VoiceStatus.error, null);
      onError('Microphone permission denied');
    }
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    _listening = false;

    _onStatus?.call(VoiceStatus.processing, null);

    try {
      final bytes    = await _recorder.stop();
      // VoiceRecorderService returns WAV on web (PCM + WAV header),
      // and AAC/M4A on native — match the actual output format.
      final mimeType = kIsWeb ? 'audio/wav' : 'audio/aac';

      final fallback = AiCommandFallback(apiKey);

      // Step 1 — transcribe audio first so we can give feedback on what was heard
      final transcript = await fallback
          .transcribeOnly(bytes, mimeType: mimeType)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw Exception(
                'Transcription timed out — please check your internet connection'),
          );

      if (transcript == null || transcript.trim().isEmpty) {
        _onStatus?.call(VoiceStatus.error, null);
        _onError?.call("Nothing was heard — please speak clearly and try again");
        return;
      }

      // Step 2 — extract structured fields from the transcript
      final json = await fallback
          .parseText(transcript)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
                'Request timed out — please check your internet connection'),
          );

      if (json == null) {
        _onStatus?.call(VoiceStatus.error, null);
        _onError?.call("Heard: \"$transcript\" — couldn't parse, please try again");
        return;
      }

      // Inject the transcript so the snackbar in the UI shows what was heard
      final jsonWithTranscript = Map<String, dynamic>.from(json);
      jsonWithTranscript.putIfAbsent('transcript', () => transcript);

      _onStatus?.call(VoiceStatus.done, null);
      _onResult?.call(ParsedEntry.fromJson(jsonWithTranscript));
    } catch (e) {
      _onStatus?.call(VoiceStatus.error, null);
      _onError?.call(e.toString());
    }
  }

  void dispose() => _recorder.dispose();
}
