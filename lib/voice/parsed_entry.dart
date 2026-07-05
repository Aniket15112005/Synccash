/// Structured result of a voice command, parsed by Gemini from raw audio.
/// This only pre-fills the Add Transaction form — it never saves on its own.
class ParsedEntry {
  final String? transcript;
  final double? amount;
  final String? type; // "income" | "expense"
  final String? category; // "Retail" | "Wholesale" | "Bank" | "UPI" | "CB"
  final String? partyName;
  final DateTime? date;

  ParsedEntry({
    this.transcript,
    this.amount,
    this.type,
    this.category,
    this.partyName,
    this.date,
  });

  factory ParsedEntry.fromJson(Map<String, dynamic> json) {
    return ParsedEntry(
      transcript: json['transcript'] as String?,
      amount: _toDouble(json['amount']),
      type: (json['type'] as String?)?.toLowerCase(),
      category: json['category'] as String?,
      partyName: json['partyName'] as String?,
      date: _toDate(json['date']),
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// True if we detected ANY usable piece of information at all — amount,
  /// type, category, party name, or date. Each field is applied to the form
  /// independently (see add_transaction_screen.dart), so a single spoken
  /// word like "income", "UPI", or a party name alone is enough to be
  /// useful. Only reject when Gemini genuinely understood nothing.
  bool get isUsable =>
      (amount != null && amount! > 0) ||
      type == 'income' ||
      type == 'expense' ||
      (category != null && category!.trim().isNotEmpty) ||
      (partyName != null && partyName!.trim().isNotEmpty) ||
      date != null;
}
