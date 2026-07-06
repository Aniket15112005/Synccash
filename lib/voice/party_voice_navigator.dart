import 'dart:convert';
import 'package:http/http.dart' as http;
import 'voice_recorder_service.dart';
import 'groq_transcriber.dart';

/// Sends a short voice command (e.g. "open New Fashion party statement") to
/// Groq and extracts JUST the party/client name being referred to, ignoring
/// filler words like "open", "show", "party", "statement", "details".
/// Bilingual (English + Hindi + Hinglish), mirrors ai_command_fallback.dart's
/// approach but is scoped to navigation-only intent (never transaction data).
///
/// NOTE: like ai_command_fallback.dart, this is now two Groq calls
/// (transcribe, then extract) instead of one combined Gemini call.
class PartyVoiceNavigator {
  final String apiKey;
  PartyVoiceNavigator(this.apiKey);

  static const _chatEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  /// Returns the extracted party name (raw, as transcribed) or null if
  /// nothing usable was said.
  Future<String?> extractPartyName(RecordedAudio audio) async {
    final transcript = await GroqTranscriber(apiKey).transcribe(audio);
    if (transcript == null) return null;

    const systemPrompt = '''
You are a bilingual (English + Hindi, including mixed "Hinglish") voice
command parser for a business app. You will be given an already
-transcribed short command. The user is trying to NAVIGATE to a specific
client/party's statement screen.

Examples of commands and what to extract:
- "Open New Fashion party statement" -> "New Fashion"
- "Show Ramesh details" -> "Ramesh"
- "Ramesh ka statement kholo" -> "Ramesh"
- "Naya Fashion party dikhao" -> "Naya Fashion"
- "Go to Sita" -> "Sita"
- "New Fashion" (just the name alone) -> "New Fashion"

Strip filler/command words like: "open", "show", "go to", "display",
"kholo", "dikhao", "party", "statement", "details", "screen", "page".
Keep only the actual client/party name being referred to, exactly as
given (do not translate it, do not guess a name that wasn't said).

Respond with ONLY raw JSON (no markdown, no code fences, no extra text) in
exactly this shape:
{"partyName": "<extracted name or null if none was said>"}
''';

    final body = jsonEncode({
      'model': 'llama-3.1-8b-instant',
      'temperature': 0.1,
      'max_tokens': 60,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': transcript},
      ],
    });

    final response = await groqHttpClient.post(
      Uri.parse(_chatEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Groq chat error (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;

    final message = choices.first['message'] as Map<String, dynamic>?;
    final rawText = message?['content'] as String?;
    if (rawText == null || rawText.trim().isEmpty) return null;

    try {
      final cleaned = rawText
          .trim()
          .replaceAll(RegExp(r'^```json'), '')
          .replaceAll(RegExp(r'^```'), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final name = json['partyName'] as String?;
      if (name == null ||
          name.trim().isEmpty ||
          name.trim().toLowerCase() == 'null') {
        return null;
      }
      return name.trim();
    } catch (_) {
      return null;
    }
  }

  /// Fuzzy-matches a spoken (possibly imperfectly transcribed) party name
  /// against the real list of party names, returning the best match or null
  /// if nothing is close enough. Case-insensitive, tolerant of partial/
  /// reordered word matches (e.g. "fashion new" ~ "New Fashion").
  ///
  /// Unchanged from before — this logic never depended on Gemini vs Groq.
  static String? findBestMatch(String spoken, List<String> realNames) {
    final spokenLow = spoken.trim().toLowerCase();
    if (spokenLow.isEmpty || realNames.isEmpty) return null;

    // 1. Exact match
    for (final name in realNames) {
      if (name.trim().toLowerCase() == spokenLow) return name;
    }

    // 2. One fully contains the other
    for (final name in realNames) {
      final nameLow = name.trim().toLowerCase();
      if (nameLow.contains(spokenLow) || spokenLow.contains(nameLow)) {
        return name;
      }
    }

    // 3. Word-overlap scoring — pick the party name sharing the most words
    final spokenWords = spokenLow.split(RegExp(r'\s+')).toSet();
    String? best;
    int bestScore = 0;
    for (final name in realNames) {
      final nameWords =
          name.trim().toLowerCase().split(RegExp(r'\s+')).toSet();
      final overlap = spokenWords.intersection(nameWords).length;
      if (overlap > bestScore) {
        bestScore = overlap;
        best = name;
      }
    }
    return bestScore > 0 ? best : null;
  }
}
