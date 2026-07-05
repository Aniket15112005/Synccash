import 'dart:convert';
import 'package:http/http.dart' as http;

/// Sends a short voice command (e.g. "open New Fashion party statement") to
/// Gemini and extracts JUST the party/client name being referred to, ignoring
/// filler words like "open", "show", "party", "statement", "details".
/// Bilingual (English + Hindi + Hinglish), mirrors ai_command_fallback.dart's
/// approach but is scoped to navigation-only intent (never transaction data).
class PartyVoiceNavigator {
  final String apiKey;
  PartyVoiceNavigator(this.apiKey);

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';

  /// Returns the extracted party name (raw, as spoken/transcribed) or null
  /// if nothing usable was said.
  Future<String?> extractPartyName(List<int> audioBytes) async {
    final base64Audio = base64Encode(audioBytes);

    const prompt = '''
You are a bilingual (English + Hindi, including mixed "Hinglish") voice
command parser for a business app. The user is trying to NAVIGATE to a
specific client/party's statement screen by speaking a short command.

Examples of commands and what to extract:
- "Open New Fashion party statement" → "New Fashion"
- "Show Ramesh details" → "Ramesh"
- "Ramesh ka statement kholo" → "Ramesh"
- "Naya Fashion party dikhao" → "Naya Fashion"
- "Go to Sita" → "Sita"
- "New Fashion" (just the name alone) → "New Fashion"

Strip filler/command words like: "open", "show", "go to", "display",
"kholo", "dikhao", "party", "statement", "details", "screen", "page".
Keep only the actual client/party name being referred to, exactly as
spoken (do not translate it, do not guess a name that wasn't said).

Respond with ONLY raw JSON (no markdown, no code fences, no extra text) in
exactly this shape:
{"partyName": "<extracted name or null if none was said>"}
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'audio/wav',
                'data': base64Audio,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'response_mime_type': 'application/json',
        'maxOutputTokens': 100,
        'thinkingConfig': {'thinkingBudget': 0},
      },
    });

    final response = await http.post(
      Uri.parse('$_endpoint?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini API error (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;

    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;

    final rawText = parts.first['text'] as String?;
    if (rawText == null || rawText.trim().isEmpty) return null;

    try {
      final cleaned = rawText.trim()
          .replaceAll(RegExp(r'^```json'), '')
          .replaceAll(RegExp(r'^```'), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final name = json['partyName'] as String?;
      if (name == null || name.trim().isEmpty || name.trim().toLowerCase() == 'null') {
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
      final nameWords = name.trim().toLowerCase().split(RegExp(r'\s+')).toSet();
      final overlap = spokenWords.intersection(nameWords).length;
      if (overlap > bestScore) {
        bestScore = overlap;
        best = name;
      }
    }
    return bestScore > 0 ? best : null;
  }
}
