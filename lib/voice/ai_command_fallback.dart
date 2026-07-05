import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Sends a raw audio clip (WAV/M4A bytes) to Gemini's multimodal API and asks
/// it to both transcribe AND extract structured transaction data in one call.
/// Handles English, Hindi, and mixed Hindi-English ("Hinglish") speech.
class AiCommandFallback {
  final String apiKey;

  AiCommandFallback(this.apiKey);

  // CORRECT:
static const _endpoint =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';

  /// Native (Android + iOS) records AAC — send as audio/aac.
  /// Web records PCM wrapped as WAV — send as audio/wav.
  static String get _mimeType => kIsWeb ? 'audio/wav' : 'audio/aac';

  /// Returns a parsed JSON map (transcript, amount, type, category, partyName,
  /// date) or null if the request failed / Gemini couldn't produce usable JSON.
  Future<Map<String, dynamic>?> parseAudio(List<int> audioBytes) async {
    final base64Audio = base64Encode(audioBytes);
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);

    final prompt = '''
You are a bilingual (English + Hindi, including mixed "Hinglish") voice
command parser for a personal cashbook app. The user will speak ONE sentence
describing a money transaction. Transcribe it, then extract structured data.

Today's date is $todayIso (YYYY-MM-DD). Use this to resolve relative dates.

Rules for understanding intent:
- Words/phrases meaning money RECEIVED → type = "income"
  Examples: "diye", "de diya", "mila", "aaya", "received", "got", "paid me"
- Words/phrases meaning money SPENT/PAID OUT → type = "expense"
  Examples: "kharch kiya", "diya" (when paying someone), "spent", "paid",
  "bought", "gaya" (as in "paisa chala gaya")
- Numbers may be spoken as digits ("500"), English words ("five hundred"),
  or Hindi words/mixed ("paanch sau", "das hazar", "5 hazar"). Always convert
  to a plain number.
- If a person's name is mentioned (e.g. "Ramesh ne", "Ramesh ko", "from Sita",
  "to the shop"), extract it as partyName, without extra words like "ne"/"ko"/"se".
- The category MUST be one of exactly these five values (case-sensitive),
  or null if nothing matches: "Retail", "Wholesale", "Bank", "UPI", "CB".
  Map spoken words like this:
    "UPI", "gpay", "phonepe", "paytm" → "UPI"
    "bank", "bank transfer", "neft", "rtgs" → "Bank"
    "cb", "cash book", "cash" → "CB"
    "wholesale" → "Wholesale"
    "retail" → "Retail"
  If no category-related word is spoken at all, leave category null (do not
  guess).
- Resolve any spoken date reference into an ISO date "YYYY-MM-DD":
    "today", "aaj" → $todayIso
    "yesterday", "kal" (in a past-referring sentence) → today minus 1 day
    "day before yesterday", "parso" (past-referring) → today minus 2 days
    an explicit date like "5 July" or "5 tarikh" → resolve to this year,
    unless a year is also mentioned
  If no date is mentioned at all, leave date null (the app will default to
  today).
- The user will NOT always say a full sentence. They may say just ONE word
  or a short fragment, meaning only that one piece of information should be
  filled — everything else must be left null. Do NOT invent or guess values
  for fields that weren't actually spoken. Examples of short/partial input:
    "income"                → only type filled, rest null
    "expense"                → only type filled, rest null
    "UPI" / "bank" / "cash" / "cb" / "wholesale" / "retail"
                              → only category filled, rest null
    "Ramesh" (just a name)   → only partyName filled, rest null
    "5000" / "paanch hazar" → only amount filled, rest null
    "yesterday" / "kal"      → only date filled, rest null
  Always still return the full JSON shape below, just with unmentioned
  fields set to null.

Respond with ONLY raw JSON (no markdown, no code fences, no extra text) in
exactly this shape:
{
  "transcript": "<the exact transcribed sentence, in original language>",
  "amount": <number or null>,
  "type": "income" | "expense" | null,
  "category": "Retail" | "Wholesale" | "Bank" | "UPI" | "CB" | null,
  "partyName": "<string or null>",
  "date": "<YYYY-MM-DD or null>"
}

Examples:
Input audio says: "Ramesh ne paanch hazar rupiye UPI se diye"
Output: {"transcript":"Ramesh ne paanch hazar rupiye UPI se diye","amount":5000,"type":"income","category":"UPI","partyName":"Ramesh","date":null}

Input audio says: "yesterday spent 200 rupees cash on groceries"
Output: {"transcript":"yesterday spent 200 rupees cash on groceries","amount":200,"type":"expense","category":"CB","partyName":null,"date":"<today-1 computed by you>"}

Input audio says: "UPI"
Output: {"transcript":"UPI","amount":null,"type":null,"category":"UPI","partyName":null,"date":null}

Input audio says: "income"
Output: {"transcript":"income","amount":null,"type":"income","category":null,"partyName":null,"date":null}

Input audio says: "Ramesh"
Output: {"transcript":"Ramesh","amount":null,"type":null,"category":null,"partyName":"Ramesh","date":null}
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': _mimeType,
                'data': base64Audio,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'response_mime_type': 'application/json',
        'maxOutputTokens': 200,
      },
    });

    // 503 = model overload → retry up to 3×; 429 = quota exhausted → friendly message.
    late http.Response response;
    for (int _attempt = 1; ; _attempt++) {
      response = await http.post(
        Uri.parse('$_endpoint?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (response.statusCode == 200) break;
      if (response.statusCode == 503 && _attempt < 3) {
        await Future.delayed(Duration(seconds: _attempt));
        continue;
      }
      if (response.statusCode == 429) {
        throw Exception(
            'Daily voice quota exceeded. Please try again tomorrow or upgrade your Gemini API plan at ai.google.dev.');
      }
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
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}