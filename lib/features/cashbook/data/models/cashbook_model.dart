import 'package:synccash/features/cashbook/domain/entities/cashbook_entity.dart';

class CashbookModel extends CashbookEntity {
  const CashbookModel({
    required super.id,
    required super.inviteCode,
    required super.ownerId,
    super.participantId,
    required super.totalBalance,
    required super.totalIncome,
    required super.totalExpense,
  });

  factory CashbookModel.fromJson(Map<String, dynamic> json, String id) {
    return CashbookModel(
      id: id,
      inviteCode: json['inviteCode'] ?? '',
      ownerId: json['ownerId'] ?? '',
      participantId: json['participantId'],
      totalBalance: (json['totalBalance'] ?? 0.0).toDouble(),
      totalIncome: (json['totalIncome'] ?? 0.0).toDouble(),
      totalExpense: (json['totalExpense'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inviteCode': inviteCode,
      'ownerId': ownerId,
      'participantId': participantId,
      'totalBalance': totalBalance,
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
    };
  }
}