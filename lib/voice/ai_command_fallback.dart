import 'dart:convert';
import 'package:http/http.dart' as http;
import 'voice_recorder_service.dart';
import 'groq_transcriber.dart';

/// Takes a recorded audio clip, transcribes it via Groq Whisper, then asks
/// a Groq chat model to extract structured transaction data from the
/// transcript. Handles English, Hindi, and mixed Hindi-English
/// ("Hinglish") speech.
///
/// NOTE: this previously called Gemini's multimodal endpoint directly
/// (audio in, JSON out, one call). Groq's Whisper models can't do
/// combined transcribe+extract in a single call the way Gemini's
/// generateContent could, so this is now two calls:
///   1. Whisper transcription (audio -> text)
///   2. A text-only chat completion that extracts fields from the
///      transcript, with response_format forced to JSON.
class AiCommandFallback {
  final String apiKey;

  AiCommandFallback(this.apiKey);

  static const _chatEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  /// Returns a parsed JSON map (transcript, amount, type, category, partyName,
  /// date) or null if transcription/extraction failed or produced nothing
  /// usable.
  Future<Map<String, dynamic>?> parseAudio(RecordedAudio audio) async {
    final transcript = await GroqTranscriber(apiKey).transcribe(audio);
    if (transcript == null) return null;
    return parseTranscript(transcript);
  }

  /// Extraction step split out from parseAudio so it can be tested/reused
  /// without needing an actual audio clip.
  Future<Map<String, dynamic>?> parseTranscript(String transcript) async {
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);

    final systemPrompt = '''
You are a bilingual (English + Hindi, including mixed "Hinglish") voice
command parser for a personal cashbook app. You will be given ONE already
-transcribed sentence describing a money transaction. Extract structured
data from it — do not re-transcribe, the transcript is given as-is.

Today's date is $todayIso (YYYY-MM-DD). Use this to resolve relative dates.

Rules for understanding intent:
- Words/phrases meaning money RECEIVED -> type = "income"
  Examples: "diye", "de diya", "mila", "aaya", "received", "got", "paid me"
- Words/phrases meaning money SPENT/PAID OUT -> type = "expense"
  Examples: "kharch kiya", "diya" (when paying someone), "spent", "paid",
  "bought", "gaya" (as in "paisa chala gaya")
- Numbers may be spoken as digits ("500"), English words ("five hundred"),
  or Hindi words/mixed ("paanch sau", "das hazar", "5 hazar"). Always
  convert to a plain number.
- If a person's name is mentioned (e.g. "Ramesh ne", "Ramesh ko", "from
  Sita", "to the shop"), extract it as partyName, without extra words
  like "ne"/"ko"/"se".
- The category MUST be one of exactly these five values (case-sensitive),
  or null if nothing matches: "Retail", "Wholesale", "Bank", "UPI", "CB".
  Map spoken words like this:
    "UPI", "gpay", "phonepe", "paytm" -> "UPI"
    "bank", "bank transfer", "neft", "rtgs" -> "Bank"
    "cb", "cash book", "cash" -> "CB"
    "wholesale" -> "Wholesale"
    "retail" -> "Retail"
  If no category-related word is spoken at all, leave category null (do
  not guess).
- Resolve any spoken date reference into an ISO date "YYYY-MM-DD":
    "today", "aaj" -> $todayIso
    "yesterday", "kal" (in a past-referring sentence) -> today minus 1 day
    "day before yesterday", "parso" (past-referring) -> today minus 2 days
    an explicit date like "5 July" or "5 tarikh" -> resolve to this year,
    unless a year is also mentioned
  If no date is mentioned at all, leave date null (the app will default to
  today).
- The transcript will NOT always be a full sentence. It may be just ONE
  word or a short fragment, meaning only that one piece of information
  should be filled — everything else must be left null. Do NOT invent or
  guess values for fields that weren't actually spoken. Examples of
  short/partial input:
    "income"                 -> only type filled, rest null
    "expense"                 -> only type filled, rest null
    "UPI" / "bank" / "cash" / "cb" / "wholesale" / "retail"
                               -> only category filled, rest null
    "Ramesh" (just a name)    -> only partyName filled, rest null
    "5000" / "paanch hazar"  -> only amount filled, rest null
    "yesterday" / "kal"       -> only date filled, rest null
  Always still return the full JSON shape below, just with unmentioned
  fields set to null.

Respond with ONLY raw JSON (no markdown, no code fences, no extra text) in
exactly this shape:
{
  "transcript": "<echo the transcript you were given, unchanged>",
  "amount": <number or null>,
  "type": "income" | "expense" | null,
  "category": "Retail" | "Wholesale" | "Bank" | "UPI" | "CB" | null,
  "partyName": "<string or null>",
  "date": "<YYYY-MM-DD or null>"
}

Examples:
Input: "Ramesh ne paanch hazar rupiye UPI se diye"
Output: {"transcript":"Ramesh ne paanch hazar rupiye UPI se diye","amount":5000,"type":"income","category":"UPI","partyName":"Ramesh","date":null}

Input: "yesterday spent 200 rupees cash on groceries"
Output: {"transcript":"yesterday spent 200 rupees cash on groceries","amount":200,"type":"expense","category":"CB","partyName":null,"date":"<today-1 computed by you>"}

Input: "UPI"
Output: {"transcript":"UPI","amount":null,"type":null,"category":"UPI","partyName":null,"date":null}

Input: "income"
Output: {"transcript":"income","amount":null,"type":"income","category":null,"partyName":null,"date":null}

Input: "Ramesh"
Output: {"transcript":"Ramesh","amount":null,"type":null,"category":null,"partyName":"Ramesh","date":null}
''';

    final body = jsonEncode({
      // llama-3.1-8b-instant instead of the 70b model: this is a fixed
      // 6-field extraction task (map to 5 known categories, convert number
      // words, resolve a date) — mechanical enough that the smaller/faster
      // model should hold up. If you see accuracy regressions on tricky
      // Hinglish phrasing during testing, swap back to
      // 'llama-3.3-70b-versatile'.
      'model': 'llama-3.1-8b-instant',
      'temperature': 0.1,
      'max_tokens': 200,
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
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
