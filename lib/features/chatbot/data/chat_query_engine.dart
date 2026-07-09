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

  // ── Public entry point ──────────────────────────────────────────────────

  Future<String> answer(String question, {required String cashbookId}) async {
    final data = await _fetchAll(cashbookId);
    final intent = await _understand(question);

    switch (intent.intent) {
      case 'pending_bills':
        return _answerBills(data, status: const ['pending', 'partial'], intent: intent);
      case 'settled_bills':
        return _answerBills(data, status: const ['settled', 'paid'], intent: intent);
      case 'payment_lookup':
        return _answerPaymentLookup(data, intent, question);
      case 'party_summary':
        return _answerPartySummary(data, intent);
      default:
        return _answerGeneral(data, question);
    }
  }

  // ── Step 1: understand ───────────────────────────────────────────────────

  Future<ChatIntent> _understand(String question) async {
    const systemPrompt = '''
You classify a question asked to a personal cashbook / ledger app about
money paid or received with named parties (customers/suppliers/friends).

Return ONLY raw JSON, no markdown, in exactly this shape:
{
  "intent": "payment_lookup" | "pending_bills" | "settled_bills" | "party_summary" | "general",
  "partyName": "<string or null>",
  "amount": <number or null>,
  "direction": "paid" | "received" | null
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
- "general": anything else (e.g. "how much did I earn this month").
- Extract partyName exactly as written (preserve capitalization), or null
  if no party is named.
- Extract amount as a plain number (strip commas/currency words), or null.
''';

    final body = jsonEncode({
      'model': 'llama-3.1-8b-instant',
      'temperature': 0,
      'max_tokens': 150,
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

    double pendingSales = 0, pendingPurchases = 0;
    for (final b in data.saleBills) {
      if (!_sameParty(b['partyName'] as String? ?? '', intent.partyName!)) continue;
      final st = (b['billStatus'] as String? ?? '').toLowerCase();
      if (st == 'pending' || st == 'partial') {
        pendingSales += (b['billTotal'] as num?)?.toDouble() ?? 0;
      }
    }
    for (final b in data.purchaseBills) {
      if (!_sameParty(b['clientName'] as String? ?? '', intent.partyName!)) continue;
      final st = (b['billStatus'] as String? ?? '').toLowerCase();
      if (st == 'pending' || st == 'partial') {
        pendingPurchases += (b['billAmount'] as num?)?.toDouble() ?? 0;
      }
    }

    final parts = <String>[];
    if (pendingSales > 0) parts.add('${intent.partyName} owes you ₹${_fmt(pendingSales)}');
    if (pendingPurchases > 0) parts.add('you owe ${intent.partyName} ₹${_fmt(pendingPurchases)}');
    if (parts.isEmpty) return '${intent.partyName} has no pending balance.';
    return parts.join(' and ') + '.';
  }

  String _answerGeneral(_LedgerData data, String question) {
    // No specific structured intent matched -- summarize totals so the
    // phrasing step below has something real to work with.
    final pendingSalesTotal = data.saleBills
        .where((b) => (b['billStatus'] as String? ?? '') == 'pending')
        .fold<double>(0, (s, b) => s + ((b['billTotal'] as num?)?.toDouble() ?? 0));
    final pendingPurchaseTotal = data.purchaseBills
        .where((b) => (b['billStatus'] as String? ?? '') == 'pending')
        .fold<double>(0, (s, b) => s + ((b['billAmount'] as num?)?.toDouble() ?? 0));

    return 'I can answer questions about specific payments, pending bills, '
        'and settled bills -- try something like "when did I pay Ramesh '
        '5000" or "list pending bills". Right now you have ₹${_fmt(pendingSalesTotal)} '
        'pending to receive and ₹${_fmt(pendingPurchaseTotal)} pending to pay.';
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
