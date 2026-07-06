import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'voice_recorder_service.dart';

/// Wraps Groq's Whisper transcription endpoint. Both the transaction-entry
/// parser and the party-name navigator need "raw audio -> text" first, so
/// this is shared instead of duplicated in both files.
///
/// Groq's Whisper models don't do combined transcribe+extract in a single
/// multimodal call the way Gemini's do — transcription and understanding
/// are two separate calls now. See ai_command_fallback.dart /
/// party_voice_navigator.dart for the second (extraction) step.
class GroqTranscriber {
  final String apiKey;
  GroqTranscriber(this.apiKey);

  static const _endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  /// Maps our known mime types to a file extension + subtype for the
  /// multipart upload. Groq accepts flac, mp3, mp4, mpeg, mpga, m4a, ogg,
  /// wav, webm.
  static ({String ext, String subtype}) _fileInfoFor(String mimeType) {
    switch (mimeType) {
      case 'audio/wav':
        return (ext: 'wav', subtype: 'wav');
      case 'audio/aac':
        return (ext: 'm4a', subtype: 'aac');
      case 'audio/ogg':
        return (ext: 'ogg', subtype: 'ogg');
      case 'audio/webm':
        return (ext: 'webm', subtype: 'webm');
      default:
        return (ext: 'wav', subtype: 'wav');
    }
  }

  /// Returns the raw transcript text, or null if nothing usable came back.
  Future<String?> transcribe(RecordedAudio audio) async {
    final info = _fileInfoFor(audio.mimeType);

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'whisper-large-v3'
      ..fields['response_format'] = 'json'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        audio.bytes,
        filename: 'audio.${info.ext}',
        contentType: MediaType('audio', info.subtype),
      ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
          'Groq transcription error (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text = decoded['text'] as String?;
    if (text == null || text.trim().isEmpty) return null;
    return text.trim();
  }
}
