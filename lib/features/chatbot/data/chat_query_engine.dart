// lib/features/chatbot/data/chat_query_engine.dart
//
// The brain of the chatbot. Two Groq calls per question:
//   1. Understand   -- free text -> structured ChatIntent (small, cheap model)
//   2. Phrase        -- matched facts -> natural-language answer
// All numbers/filtering happen in Dart against real Firestore data, never
// invented by the LLM -- the LLM only classifies intent and writes prose.
//
// Mirrors the same "who paid what, linked to which bill" logic already used
// in party_detail_screen.dart, generalized across ALL parties instead of one.

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../domain/chat_models.dart';

class ChatQueryEngine {
  final String groqApiKey;
  final FirebaseFirestore _db;

  ChatQueryEngine({required this.groqApiKey, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const _chatEndpoint = 'https://api.groq.com/openai/v1/chat/completions';

  // Short-lived cache so rapid-fire questions (very common in a chat UI)
  // don't each re-read every bill/transaction from Firestore -- shaves the
  // slowest part of the round trip off every question except the first.
  _LedgerData? _cachedData;
  String? _cachedCashbookId;
  DateTime? _cachedAt;
  static const _cacheTtl = Duration(seconds: 20);

  // ── Public entry point ──────────────────────────────────────────────────

  Future<String> answer(String question, {required String cashbookId}) async {
    // Fetching Firestore data and classifying intent don't depend on each
    // other -- run them concurrently instead of one after another so the
    // user isn't waiting on two sequential network round trips.
    final results = await Future.wait([
      _fetchAllCached(cashbookId),
      _understand(question),
    ]);
    final data = results[0] as _LedgerData;
    final intent = results[1] as ChatIntent;

    switch (intent.intent) {
      case 'pending_bills':
        return _answerBills(data, status: const ['pending', 'partial'], intent: intent);
      case 'settled_bills':
        return _answerBills(data, status: const ['settled', 'paid'], intent: intent);
      case 'payment_lookup':
        return _answerPaymentLookup(data, intent, question);
      case 'party_summary':
        return _answerPartySummary(data, intent);
      case 'date_totals':
        return _answerDateTotals(data, _withFallbackDates(intent, question));
      default:
        // Safety net: the LLM sometimes misses date/money phrasing and
        // returns "general". If the question clearly mentions a date-ish
        // word alongside money wording, force a date_totals answer using a
        // Dart-side date resolver instead of giving up.
        final fallback = _withFallbackDates(intent, question);
        if (fallback.dateFrom != null && _looksLikeMoneyQuestion(question)) {
          return _answerDateTotals(data, fallback.copyWith(intent: 'date_totals'));
        }
        return _answerGeneral(data, question);
    }
  }

  bool _looksLikeMoneyQuestion(String q) {
    final t = q.toLowerCase();
    return t.contains('income') ||
        t.contains('expense') ||
        t.contains('spend') ||
        t.contains('spent') ||
        t.contains('earn') ||
        t.contains('total') ||
        t.contains('transaction') ||
        t.contains('paid') ||
        t.contains('received') ||
        t.contains('sale') ||
        t.contains('purchase') ||
        t.contains('₹') ||
        t.contains('rs.') ||
        t.contains('rupee');
  }

  /// If the LLM didn't resolve a date range but the question contains an
  /// obvious relative/absolute date phrase, resolve it ourselves so the
  /// feature stays accurate even when the model misses it.
  ChatIntent _withFallbackDates(ChatIntent intent, String question) {
    if (intent.dateFrom != null) return intent;

    final now = DateTime.now();
    final t = question.toLowerCase();
    DateTime? from;
    DateTime? to;

    DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

    if (t.contains('today')) {
      from = to = dayOnly(now);
    } else if (t.contains('yesterday')) {
      from = to = dayOnly(now.subtract(const Duration(days: 1)));
    } else if (t.contains('this week')) {
      final start = dayOnly(now.subtract(Duration(days: now.weekday - 1)));
      from = start;
      to = dayOnly(now);
    } else if (t.contains('last week')) {
      final startOfThisWeek = dayOnly(now.subtract(Duration(days: now.weekday - 1)));
      from = startOfThisWeek.subtract(const Duration(days: 7));
      to = startOfThisWeek.subtract(const Duration(days: 1));
    } else if (t.contains('this month')) {
      from = DateTime(now.year, now.month, 1);
      to = dayOnly(now);
    } else if (t.contains('last month')) {
      final firstOfThisMonth = DateTime(now.year, now.month, 1);
      to = firstOfThisMonth.subtract(const Duration(days: 1));
      from = DateTime(to.year, to.month, 1);
    } else {
      // Try "8th july", "8 july", "july 8" style absolute dates.
      const months = {
        'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
        'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7,
        'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
        'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12,
        'december': 12,
      };
      final monthPattern = months.keys.join('|');
      final dayFirst = RegExp(
          '(\\d{1,2})(?:st|nd|rd|th)?\\s+of?\\s*($monthPattern)',
          caseSensitive: false);
      final monthFirst = RegExp(
          '($monthPattern)\\s+(\\d{1,2})(?:st|nd|rd|th)?',
          caseSensitive: false);

      final m1 = dayFirst.firstMatch(t);
      final m2 = monthFirst.firstMatch(t);
      int? day;
      int? month;
      if (m1 != null) {
        day = int.tryParse(m1.group(1)!);
        month = months[m1.group(2)!.toLowerCase()];
      } else if (m2 != null) {
        month = months[m2.group(1)!.toLowerCase()];
        day = int.tryParse(m2.group(2)!);
      }
      if (day != null && month != null) {
        from = to = DateTime(now.year, month, day);
      }
    }

    if (from == null) return intent;
    return intent.copyWith(dateFrom: from, dateTo: to ?? from);
  }

  // ── Step 1: understand ───────────────────────────────────────────────────

  Future<ChatIntent> _understand(String question) async {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final systemPrompt = '''
You classify a question asked to a personal cashbook / ledger app about
money paid or received with named parties (customers/suppliers/friends).
Today's date is $today (YYYY-MM-DD). Use this to resolve relative/partial
dates like "8th July" or "yesterday" -- assume the current year unless a
year is explicitly stated, and never invent a year in the past or future
relative to today unless the question implies it.

Return ONLY raw JSON, no markdown, in exactly this shape:
{
  "intent": "payment_lookup" | "pending_bills" | "settled_bills" | "party_summary" | "date_totals" | "general",
  "partyName": "<string or null>",
  "amount": <number or null>,
  "direction": "paid" | "received" | null,
  "dateFrom": "<YYYY-MM-DD or null>",
  "dateTo": "<YYYY-MM-DD or null>",
  "metric": "income" | "expense" | "total" | null
}

Rules:
- "payment_lookup": asking WHEN or WHETHER a specific payment happened,
  e.g. "when did I pay A 25000", "did I receive 1000 from Ramesh",
  "whom did I pay 1000 to". "direction"="paid" means money went OUT from
  the user to the party. "direction"="received" means money came IN from
  the party to the user. If the question doesn't make direction clear,
  leave it null.
- "pending_bills": asking for outstanding/unpaid/due bills, for one party
  or all parties.
- "settled_bills": asking for settled/paid/cleared bills.
- "party_summary": asking for a party's overall balance/status ("how much
  does Ramesh owe me", "what's A's balance").
- "date_totals": asking for a TOTAL/SUM/count of money or transactions over
  a date or date range, e.g. "total transactions on 8th July", "what was
  the income on 7th July", "how much did I spend last week", "total sales
  this month", "income added today", "what did I earn yesterday". This
  covers ANY question mentioning a date/day/week/month word ("today",
  "yesterday", "this week", "last week", "this month", "last month", a
  weekday name, or a specific date) together with money/income/expense/
  transaction wording. Set dateFrom/dateTo to the resolved date range
  (inclusive, same day if a single day is meant -- "today" and "yesterday"
  both resolve to a single day). Set "metric" to "income" if asking about
  money received/earned/sales, "expense" if asking about money paid/spent,
  otherwise "total". If the question also names a party (e.g. "income from
  Ramesh this month"), still fill partyName.
- "general": anything else that doesn't fit the above (e.g. vague chat,
  app help, questions with no financial data to look up).
- Extract partyName exactly as written (preserve capitalization), or null
  if no party is named.
- Extract amount as a plain number (strip commas/currency words), or null.
- dateFrom/dateTo/metric are only relevant for "date_totals"; leave them
  null for every other intent.

Examples:
Q: "what was the total income added today"
A: {"intent":"date_totals","partyName":null,"amount":null,"direction":null,"dateFrom":"$today","dateTo":"$today","metric":"income"}

Q: "what was the total transaction on 8th july"
A: {"intent":"date_totals","partyName":null,"amount":null,"direction":null,"dateFrom":"${now.year}-07-08","dateTo":"${now.year}-07-08","metric":"total"}

Q: "how much did I spend yesterday"
A: {"intent":"date_totals","partyName":null,"amount":null,"direction":null,"dateFrom":"<yesterday's date>","dateTo":"<yesterday's date>","metric":"expense"}

Q: "when did I pay Ramesh 5000"
A: {"intent":"payment_lookup","partyName":"Ramesh","amount":5000,"direction":"paid","dateFrom":null,"dateTo":null,"metric":null}
''';

    final body = jsonEncode({
      'model': 'llama-3.3-70b-versatile',
      'temperature': 0,
      'max_tokens': 250,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': question},
      ],
    });

    try {
      final res = await http
          .post(Uri.parse(_chatEndpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $groqApiKey',
              },
              body: body)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return const ChatIntent(intent: 'general');

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final content =
          (decoded['choices'] as List?)?.first['message']?['content'] as String?;
      if (content == null) return const ChatIntent(intent: 'general');

      final cleaned = content
          .trim()
          .replaceAll(RegExp(r'^```json'), '')
          .replaceAll(RegExp(r'^```'), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      return ChatIntent.fromJson(jsonDecode(cleaned) as Map<String, dynamic>);
    } catch (_) {
      return const ChatIntent(intent: 'general');
    }
  }

  // ── Step 2: fetch raw data (one-shot reads, not live streams) ──────────

  /// Wraps [_fetchAll] with a short in-memory cache. Chat questions tend to
  /// arrive in quick bursts (follow-ups within the same conversation), so
  /// this avoids re-downloading every bill/transaction for each one --
  /// noticeably smoother without risking stale answers for more than a
  /// few seconds.
  Future<_LedgerData> _fetchAllCached(String cashbookId) async {
    final now = DateTime.now();
    final cached = _cachedData;
    if (cached != null &&
        _cachedCashbookId == cashbookId &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return cached;
    }
    final fresh = await _fetchAll(cashbookId);
    _cachedData = fresh;
    _cachedCashbookId = cashbookId;
    _cachedAt = now;
    return fresh;
  }

  Future<_LedgerData> _fetchAll(String cashbookId) async {
    final base = _db.collection('cashbooks').doc(cashbookId);

    final salesSnap = await base.collection('sale_bills').get();
    final purchaseSnap = await base.collection('purchase_bills').get();
    final txSnap = await base.collection('transactions').get();

    final saleBills = salesSnap.docs.map((d) => d.data()).toList();
    final purchaseBills = purchaseSnap.docs.map((d) => d.data()).toList();
    final txs = txSnap.docs.map((d) => d.data()).toList();

    return _LedgerData(saleBills: saleBills, purchaseBills: purchaseBills, txs: txs);
  }

  // ── Answer builders ──────────────────────────────────────────────────────

  String _answerBills(_LedgerData data, {required List<String> status, required ChatIntent intent}) {
    final bills = <BillFact>[];

    for (final b in data.saleBills) {
      final st = (b['billStatus'] as String? ?? 'pending').toLowerCase();
      if (!status.contains(st)) continue;
      final party = (b['partyName'] as String? ?? '').trim();
      if (intent.partyName != null && !_sameParty(party, intent.partyName!)) continue;
      bills.add(BillFact(
        partyName: party,
        billNumber: b['billNumber'] as String? ?? '',
        amount: (b['billTotal'] as num?)?.toDouble() ?? 0,
        date: (b['billDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        status: st,
        kind: 'sale',
      ));
    }
    for (final b in data.purchaseBills) {
      final st = (b['billStatus'] as String? ?? 'pending').toLowerCase();
      if (!status.contains(st)) continue;
      final party = (b['clientName'] as String? ?? '').trim();
      if (intent.partyName != null && !_sameParty(party, intent.partyName!)) continue;
      bills.add(BillFact(
        partyName: party,
        billNumber: b['billNumber'] as String? ?? '',
        amount: (b['billAmount'] as num?)?.toDouble() ?? 0,
        date: (b['billDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        status: st,
        kind: 'purchase',
      ));
    }

    if (bills.isEmpty) {
      final who = intent.partyName != null ? ' for ${intent.partyName}' : '';
      final label = status.contains('pending') ? 'pending' : 'settled';
      return "No $label bills$who.";
    }

    bills.sort((a, b) => b.date.compareTo(a.date));
    final label = status.contains('pending') ? 'Pending' : 'Settled';
    final lines = bills.map((b) {
      final side = b.kind == 'sale' ? 'they owe you' : 'you owe them';
      return '- ${b.partyName}: ₹${_fmt(b.amount)} (bill ${b.billNumber}, ${_fmtDate(b.date)}, $side)';
    }).join('\n');
    final total = bills.fold<double>(0, (s, b) => s + b.amount);

    return '$label bills (${bills.length}, total ₹${_fmt(total)}):\n$lines';
  }

  String _answerPaymentLookup(_LedgerData data, ChatIntent intent, String question) {
    final facts = _buildPaymentFacts(data);

    var matches = facts.where((f) {
      if (intent.partyName != null && !_sameParty(f.partyName, intent.partyName!)) return false;
      if (intent.amount != null && (f.amount - intent.amount!).abs() > 0.5) return false;
      if (intent.direction != null && f.direction != intent.direction) return false;
      return true;
    }).toList();

    // If nothing matched with the exact amount, retry without the amount
    // filter so we can at least tell the user what we DID find.
    if (matches.isEmpty && intent.amount != null) {
      matches = facts.where((f) {
        if (intent.partyName != null && !_sameParty(f.partyName, intent.partyName!)) return false;
        if (intent.direction != null && f.direction != intent.direction) return false;
        return true;
      }).toList();
    }

    if (matches.isEmpty) {
      final who = intent.partyName != null ? ' with ${intent.partyName}' : '';
      return "I couldn't find a matching payment$who.";
    }

    matches.sort((a, b) => b.date.compareTo(a.date));
    final lines = matches.take(10).map((f) {
      final verb = f.direction == 'received' ? 'received from' : 'paid to';
      final bill = f.billNumber != null ? ' (bill ${f.billNumber})' : '';
      return '- $verb ${f.partyName}: ₹${_fmt(f.amount)} on ${_fmtDate(f.date)}$bill';
    }).join('\n');

    return matches.length == 1
        ? 'Found it:\n${lines}'
        : 'Found ${matches.length} matching payments:\n$lines';
  }

  String _answerPartySummary(_LedgerData data, ChatIntent intent) {
    if (intent.partyName == null) return 'Which party do you mean?';
    final party = intent.partyName!;

    double pendingSales = 0, pendingPurchases = 0;
    double totalBilledSales = 0, totalBilledPurchases = 0;
    var saleBillCount = 0, purchaseBillCount = 0;

    for (final b in data.saleBills) {
      if (!_sameParty(b['partyName'] as String? ?? '', party)) continue;
      final st = (b['billStatus'] as String? ?? '').toLowerCase();
      final amt = (b['billTotal'] as num?)?.toDouble() ?? 0;
      saleBillCount++;
      totalBilledSales += amt;
      if (st == 'pending' || st == 'partial') pendingSales += amt;
    }
    for (final b in data.purchaseBills) {
      if (!_sameParty(b['clientName'] as String? ?? '', party)) continue;
      final st = (b['billStatus'] as String? ?? '').toLowerCase();
      final amt = (b['billAmount'] as num?)?.toDouble() ?? 0;
      purchaseBillCount++;
      totalBilledPurchases += amt;
      if (st == 'pending' || st == 'partial') pendingPurchases += amt;
    }

    // Cumulative money actually received from / paid to this party so far,
    // built from real transaction records (not just bill totals).
    final facts = _buildPaymentFacts(data)
        .where((f) => _sameParty(f.partyName, party))
        .toList();
    final totalReceived = facts
        .where((f) => f.direction == 'received')
        .fold<double>(0, (s, f) => s + f.amount);
    final totalPaid = facts
        .where((f) => f.direction == 'paid')
        .fold<double>(0, (s, f) => s + f.amount);
    final receivedCount = facts.where((f) => f.direction == 'received').length;
    final paidCount = facts.where((f) => f.direction == 'paid').length;

    if (saleBillCount == 0 && purchaseBillCount == 0 && facts.isEmpty) {
      return "I couldn't find any bills or payments for '$party'. Check the "
          'spelling, or it may be recorded under a slightly different name.';
    }

    final lines = <String>[];
    if (totalReceived > 0) {
      lines.add('- Received from $party so far: ₹${_fmt(totalReceived)} '
          '($receivedCount payment${receivedCount == 1 ? '' : 's'})');
    }
    if (totalPaid > 0) {
      lines.add('- Paid to $party so far: ₹${_fmt(totalPaid)} '
          '($paidCount payment${paidCount == 1 ? '' : 's'})');
    }
    if (saleBillCount > 0) {
      lines.add('- Sale bills: $saleBillCount, totalling ₹${_fmt(totalBilledSales)}'
          '${pendingSales > 0 ? ' (₹${_fmt(pendingSales)} still pending)' : ' (all settled)'}');
    }
    if (purchaseBillCount > 0) {
      lines.add('- Purchase bills: $purchaseBillCount, totalling ₹${_fmt(totalBilledPurchases)}'
          '${pendingPurchases > 0 ? ' (₹${_fmt(pendingPurchases)} still pending)' : ' (all settled)'}');
    }

    final balanceParts = <String>[];
    if (pendingSales > 0) balanceParts.add('$party owes you ₹${_fmt(pendingSales)}');
    if (pendingPurchases > 0) balanceParts.add('you owe $party ₹${_fmt(pendingPurchases)}');
    final balanceLine = balanceParts.isEmpty
        ? 'No pending balance with $party.'
        : balanceParts.join(' and ') + '.';

    return '$balanceLine\n${lines.join('\n')}';
  }

  String _answerDateTotals(_LedgerData data, ChatIntent intent) {
    final from = intent.dateFrom;
    final to = intent.dateTo ?? from;
    if (from == null || to == null) {
      return "I couldn't figure out which date you meant -- try something "
          'like "total income on 8th July" or "total transactions on '
          '1st to 5th July".';
    }

    final startOfDay = DateTime(from.year, from.month, from.day);
    final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);

    double income = 0, expense = 0;
    var count = 0;

    for (final tx in data.txs) {
      final date = (tx['createdAt'] as Timestamp?)?.toDate();
      if (date == null) continue;
      if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) continue;

      final type = (tx['type'] as String? ?? '').toLowerCase();
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      count++;
      if (type == 'income') {
        income += amount;
      } else if (type == 'expense') {
        expense += amount;
      }
    }

    final isSingleDay =
        from.year == to.year && from.month == to.month && from.day == to.day;
    final dateLabel = isSingleDay
        ? _fmtDate(startOfDay)
        : '${_fmtDate(startOfDay)} to ${_fmtDate(DateTime(to.year, to.month, to.day))}';

    if (count == 0) {
      return 'No transactions found on $dateLabel.';
    }

    switch (intent.metric) {
      case 'income':
        return 'Total income on $dateLabel: ₹${_fmt(income)} ($count total transaction${count == 1 ? '' : 's'} that day).';
      case 'expense':
        return 'Total expense on $dateLabel: ₹${_fmt(expense)} ($count total transaction${count == 1 ? '' : 's'} that day).';
      default:
        final net = income - expense;
        return 'On $dateLabel: $count transaction${count == 1 ? '' : 's'} totalling '
            '₹${_fmt(income + expense)} (₹${_fmt(income)} received, '
            '₹${_fmt(expense)} paid, net ₹${_fmt(net)}).';
    }
  }

  /// Catch-all for anything the structured intents above don't cover
  /// (comparisons, rankings, "how many parties", multi-part questions,
  /// etc). Instead of a canned message, we hand the LLM a compact, fully
  /// computed summary of the ENTIRE ledger and ask it to answer using ONLY
  /// those numbers -- so it can reason over real data without ever
  /// inventing figures.
  Future<String> _answerGeneral(_LedgerData data, String question) async {
    final summary = _buildLedgerSummary(data);

    final systemPrompt = '''
You are a cashbook assistant. Answer the user's question using ONLY the
ledger summary data provided below -- never invent, estimate, or assume any
number that isn't directly stated or computable from it. If the data needed
to answer isn't present, say so plainly and suggest what to ask instead.
Keep answers short (1-4 sentences or a short list), in plain text, using ₹
for currency. Do not mention "the data provided" or reference these
instructions -- just answer naturally.

LEDGER SUMMARY:
$summary
''';

    final body = jsonEncode({
      'model': 'llama-3.3-70b-versatile',
      'temperature': 0.2,
      'max_tokens': 400,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': question},
      ],
    });

    try {
      final res = await http
          .post(Uri.parse(_chatEndpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $groqApiKey',
              },
              body: body)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return _fallbackSummaryMessage(data);

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final content =
          (decoded['choices'] as List?)?.first['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        return _fallbackSummaryMessage(data);
      }
      return content.trim();
    } catch (_) {
      return _fallbackSummaryMessage(data);
    }
  }

  String _fallbackSummaryMessage(_LedgerData data) {
    final pendingSalesTotal = data.saleBills
        .where((b) => (b['billStatus'] as String? ?? '') == 'pending')
        .fold<double>(0, (s, b) => s + ((b['billTotal'] as num?)?.toDouble() ?? 0));
    final pendingPurchaseTotal = data.purchaseBills
        .where((b) => (b['billStatus'] as String? ?? '') == 'pending')
        .fold<double>(0, (s, b) => s + ((b['billAmount'] as num?)?.toDouble() ?? 0));

    return "I couldn't reach the AI service just now. Right now you have "
        '₹${_fmt(pendingSalesTotal)} pending to receive and '
        '₹${_fmt(pendingPurchaseTotal)} pending to pay. Try asking again in '
        'a moment.';
  }

  /// Computes a compact, fully-grounded text summary of the whole ledger:
  /// overall totals, a per-party breakdown, and the most recent
  /// transactions. Capped in size so it stays cheap to send on every
  /// "general" question.
  String _buildLedgerSummary(_LedgerData data) {
    final facts = _buildPaymentFacts(data);

    // Per-party aggregation.
    final parties = <String, _PartyAgg>{};
    _PartyAgg agg(String name) =>
        parties.putIfAbsent(name.trim(), () => _PartyAgg());

    for (final b in data.saleBills) {
      final name = (b['partyName'] as String? ?? 'Unknown').trim();
      final st = (b['billStatus'] as String? ?? '').toLowerCase();
      final amt = (b['billTotal'] as num?)?.toDouble() ?? 0;
      final a = agg(name);
      a.saleBillCount++;
      a.saleBilled += amt;
      if (st == 'pending' || st == 'partial') a.salePending += amt;
    }
    for (final b in data.purchaseBills) {
      final name = (b['clientName'] as String? ?? 'Unknown').trim();
      final st = (b['billStatus'] as String? ?? '').toLowerCase();
      final amt = (b['billAmount'] as num?)?.toDouble() ?? 0;
      final a = agg(name);
      a.purchaseBillCount++;
      a.purchaseBilled += amt;
      if (st == 'pending' || st == 'partial') a.purchasePending += amt;
    }
    for (final f in facts) {
      final a = agg(f.partyName);
      if (f.direction == 'received') {
        a.received += f.amount;
        a.receivedCount++;
      } else {
        a.paid += f.amount;
        a.paidCount++;
      }
    }

    final totalPendingReceivable =
        parties.values.fold<double>(0, (s, a) => s + a.salePending);
    final totalPendingPayable =
        parties.values.fold<double>(0, (s, a) => s + a.purchasePending);
    final totalReceivedAllTime =
        parties.values.fold<double>(0, (s, a) => s + a.received);
    final totalPaidAllTime = parties.values.fold<double>(0, (s, a) => s + a.paid);

    final buf = StringBuffer();
    buf.writeln('Overall: ₹${_fmt(totalPendingReceivable)} pending to receive, '
        '₹${_fmt(totalPendingPayable)} pending to pay, '
        '₹${_fmt(totalReceivedAllTime)} received all-time, '
        '₹${_fmt(totalPaidAllTime)} paid all-time, '
        '${parties.length} parties total, ${data.saleBills.length} sale bills, '
        '${data.purchaseBills.length} purchase bills, ${data.txs.length} transactions.');

    buf.writeln('\nPer-party breakdown:');
    final sortedParties = parties.entries.toList()
      ..sort((a, b) => (b.value.saleBilled + b.value.purchaseBilled)
          .compareTo(a.value.saleBilled + a.value.purchaseBilled));
    for (final e in sortedParties.take(60)) {
      final a = e.value;
      buf.writeln('- ${e.key}: sold ₹${_fmt(a.saleBilled)} '
          '(${a.saleBillCount} bills, ₹${_fmt(a.salePending)} pending), '
          'purchased ₹${_fmt(a.purchaseBilled)} '
          '(${a.purchaseBillCount} bills, ₹${_fmt(a.purchasePending)} pending), '
          'received ₹${_fmt(a.received)} (${a.receivedCount} payments), '
          'paid ₹${_fmt(a.paid)} (${a.paidCount} payments)');
    }

    final recent = [...facts]..sort((a, b) => b.date.compareTo(a.date));
    buf.writeln('\nMost recent transactions (up to 40):');
    for (final f in recent.take(40)) {
      final verb = f.direction == 'received' ? 'received from' : 'paid to';
      buf.writeln('- ${_fmtDate(f.date)}: $verb ${f.partyName} ₹${_fmt(f.amount)}');
    }

    return buf.toString();
  }

  // ── Building payment facts from raw transactions (mirrors party_detail_screen) ──

  List<PaymentFact> _buildPaymentFacts(_LedgerData data) {
    final saleBillById = {for (final b in data.saleBills) (b['saleBillId'] as String? ?? ''): b};
    final purchaseBillById = {
      for (final b in data.purchaseBills) (b['purchaseBillId'] as String? ?? ''): b
    };

    final facts = <PaymentFact>[];

    for (final tx in data.txs) {
      final type = (tx['type'] as String? ?? '').toLowerCase();
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      final date = (tx['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final linkedSale = tx['linkedSaleBillId'] as String?;
      final linkedPurchase = tx['linkedPurchaseBillId'] as String?;
      final isObPayment = tx['isObPayment'] as bool? ?? false;
      final obPartyName = (tx['obPartyName'] as String? ?? '').trim();
      final desc = (tx['description'] as String? ?? '').trim();

      if (type == 'income' && linkedSale != null && saleBillById.containsKey(linkedSale)) {
        final bill = saleBillById[linkedSale]!;
        facts.add(PaymentFact(
          partyName: bill['partyName'] as String? ?? '',
          amount: amount,
          date: date,
          direction: 'received',
          billNumber: bill['billNumber'] as String?,
        ));
      } else if (type == 'expense' &&
          linkedPurchase != null &&
          purchaseBillById.containsKey(linkedPurchase)) {
        final bill = purchaseBillById[linkedPurchase]!;
        facts.add(PaymentFact(
          partyName: bill['clientName'] as String? ?? '',
          amount: amount,
          date: date,
          direction: 'paid',
          billNumber: bill['billNumber'] as String?,
        ));
      } else if (isObPayment && obPartyName.isNotEmpty) {
        facts.add(PaymentFact(
          partyName: obPartyName,
          amount: amount,
          date: date,
          direction: type == 'income' ? 'received' : 'paid',
        ));
      } else if (desc.isNotEmpty) {
        // Old-style unlinked payment -- description often IS the party name
        // or contains it (e.g. "Payment from Ramesh").
        facts.add(PaymentFact(
          partyName: desc,
          amount: amount,
          date: date,
          direction: type == 'income' ? 'received' : 'paid',
        ));
      }
    }

    return facts;
  }

  bool _sameParty(String a, String b) => a.trim().toLowerCase().contains(b.trim().toLowerCase()) ||
      b.trim().toLowerCase().contains(a.trim().toLowerCase());

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _LedgerData {
  final List<Map<String, dynamic>> saleBills;
  final List<Map<String, dynamic>> purchaseBills;
  final List<Map<String, dynamic>> txs;

  const _LedgerData({
    required this.saleBills,
    required this.purchaseBills,
    required this.txs,
  });
}

/// Running totals for one party, used to build the grounded ledger summary
/// fed to the LLM for open-ended questions.
class _PartyAgg {
  double saleBilled = 0;
  double salePending = 0;
  int saleBillCount = 0;

  double purchaseBilled = 0;
  double purchasePending = 0;
  int purchaseBillCount = 0;

  double received = 0;
  int receivedCount = 0;

  double paid = 0;
  int paidCount = 0;
}
