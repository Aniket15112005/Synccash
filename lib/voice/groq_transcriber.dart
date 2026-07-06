import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'voice_recorder_service.dart';

/// Shared, reused HTTP client for every Groq call in this app. Reusing one
/// client keeps the TLS/keep-alive connection to api.groq.com open across
/// requests instead of paying a fresh handshake on every mic tap — this is
/// the single biggest "make it feel faster" win that costs zero accuracy.
final http.Client groqHttpClient = http.Client();

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

  static const _transcribeEndpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static const _translateEndpoint =
      'https://api.groq.com/openai/v1/audio/translations';

  // whisper-large-v3-turbo is noticeably faster than whisper-large-v3 with
  // only a small accuracy trade-off — fine for short, clear single-sentence
  // commands. If you notice Hinglish/mixed-script accuracy drop in testing,
  // switch this back to 'whisper-large-v3'.
  static const _model = 'whisper-large-v3-turbo';

  // Translation endpoint output quality is more sensitive to model choice
  // than transcription is — using the full model here, not turbo.
  static const _translateModel = 'whisper-large-v3';

  /// Maps our known mime types to a file extension + subtype for the
  /// multipart upload. Groq accepts flac, mp3, mp4, mpeg, mpga, m4a, ogg,
  /// wav, webm.
  static ({String ext, String subtype}) _fileInfoFor(String mimeType) {
    switch (mimeType) {
      case 'audio/wav':
        return (ext: 'wav', subtype: 'wav');
      case 'audio/mp4':
        // Safari/iOS's real MediaRecorder output container.
        return (ext: 'm4a', subtype: 'mp4');
      case 'audio/aac':
        // Kept defensively in case a bare AAC stream ever shows up, but
        // Safari specifically produces audio/mp4, not this.
        return (ext: 'm4a', subtype: 'aac');
      case 'audio/ogg':
        return (ext: 'ogg', subtype: 'ogg');
      case 'audio/webm':
        return (ext: 'webm', subtype: 'webm');
      default:
        return (ext: 'wav', subtype: 'wav');
    }
  }

  /// Returns the raw transcript text, IN WHATEVER SCRIPT WAS SPOKEN
  /// (Hindi audio may come back in Devanagari or Romanized Hindi,
  /// inconsistently). Kept for cases where you genuinely want the original
  /// language preserved. For anything that gets shown/stored as English
  /// (like your description field), use translate() below instead.
  Future<String?> transcribe(RecordedAudio audio) async {
    final info = _fileInfoFor(audio.mimeType);

    final request = http.MultipartRequest('POST', Uri.parse(_transcribeEndpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = _model
      ..fields['response_format'] = 'json'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        audio.bytes,
        filename: 'audio.${info.ext}',
        contentType: MediaType('audio', info.subtype),
      ));

    final streamed = await groqHttpClient.send(request);
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

  /// Returns the audio's content translated into English, ALWAYS in Latin
  /// script — regardless of whether the speech was English, Hindi, or
  /// mixed Hinglish. This is what fixes inconsistent
  /// Devanagari-vs-Romanized output: the translation endpoint normalizes
  /// everything to English, so downstream extraction (partyName,
  /// description, etc.) is always in English too.
  ///
  /// The `prompt` param nudges Whisper to keep proper nouns (people/shop
  /// names) as-is in English letters rather than translating or dropping
  /// them — translation models can otherwise mangle names.
  Future<String?> translate(RecordedAudio audio) async {
    final info = _fileInfoFor(audio.mimeType);

    final request = http.MultipartRequest('POST', Uri.parse(_translateEndpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = _translateModel
      ..fields['response_format'] = 'json'
      ..fields['prompt'] =
          'This is a business cashbook voice command. Keep any person or shop names unchanged, spelled out in English letters.'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        audio.bytes,
        filename: 'audio.${info.ext}',
        contentType: MediaType('audio', info.subtype),
      ));

    final streamed = await groqHttpClient.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
          'Groq translation error (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text = decoded['text'] as String?;
    if (text == null || text.trim().isEmpty) return null;
    return text.trim();
  }
}
