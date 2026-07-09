// lib/features/chatbot/domain/chat_models.dart
//
// Plain data models for the chatbot feature. No Firestore/HTTP imports here
// on purpose -- keep this file dependency-free so it's easy to test.

enum ChatRole { user, bot }

class ChatMessage {
  final ChatRole role;
  final String text;
  final DateTime createdAt;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Structured intent extracted from the user's free-text question by the
/// LLM. Every field is optional -- the engine falls back gracefully when a
/// field wasn't mentioned.
class ChatIntent {
  /// One of: "payment_lookup", "pending_bills", "settled_bills",
  /// "party_summary", "date_totals", "general".
  final String intent;

  /// Party/person name mentioned in the question, if any (e.g. "A", "Ramesh").
  final String? partyName;

  /// Amount mentioned in the question, if any (e.g. 25000).
  final double? amount;

  /// "paid" (you -> them, expense/purchase side) or "received"
  /// (them -> you, income/sale side). Null when direction is ambiguous or
  /// not relevant to the question.
  final String? direction;

  /// Start/end of a date range mentioned in the question (inclusive), for
  /// intent == "date_totals" (e.g. "on 8th July" -> dateFrom == dateTo).
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// For intent == "date_totals": "income" | "expense" | "total" | null
  /// (null/"total" means both income and expense).
  final String? metric;

  const ChatIntent({
    required this.intent,
    this.partyName,
    this.amount,
    this.direction,
    this.dateFrom,
    this.dateTo,
    this.metric,
  });

  factory ChatIntent.fromJson(Map<String, dynamic> json) {
    return ChatIntent(
      intent: (json['intent'] as String?)?.trim().isNotEmpty == true
          ? json['intent'] as String
          : 'general',
      partyName: (json['partyName'] as String?)?.trim().isEmpty == true
          ? null
          : json['partyName'] as String?,
      amount: json['amount'] is num ? (json['amount'] as num).toDouble() : null,
      direction: json['direction'] as String?,
      dateFrom: _parseDate(json['dateFrom']),
      dateTo: _parseDate(json['dateTo']),
      metric: (json['metric'] as String?)?.trim().isEmpty == true
          ? null
          : json['metric'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v is! String || v.trim().isEmpty) return null;
    try {
      return DateTime.parse(v.trim());
    } catch (_) {
      return null;
    }
  }

  ChatIntent copyWith({
    String? intent,
    String? partyName,
    double? amount,
    String? direction,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? metric,
  }) {
    return ChatIntent(
      intent: intent ?? this.intent,
      partyName: partyName ?? this.partyName,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      metric: metric ?? this.metric,
    );
  }
}

/// A single matched payment/transaction fact, used both to compute the
/// answer and to show a "sources" list under the chat bubble if you want to.
class PaymentFact {
  final String partyName;
  final double amount;
  final DateTime date;

  /// "received" (income, party paid you) or "paid" (expense, you paid party).
  final String direction;

  /// Optional linked bill number, for display.
  final String? billNumber;

  const PaymentFact({
    required this.partyName,
    required this.amount,
    required this.date,
    required this.direction,
    this.billNumber,
  });
}

class BillFact {
  final String partyName;
  final String billNumber;
  final double amount;
  final DateTime date;
  final String status; // 'pending' | 'partial' | 'settled' | 'paid'

  /// "sale" (they owe you) or "purchase" (you owe them).
  final String kind;

  const BillFact({
    required this.partyName,
    required this.billNumber,
    required this.amount,
    required this.date,
    required this.status,
    required this.kind,
  });
}
