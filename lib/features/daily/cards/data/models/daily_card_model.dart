// lib/features/daily/cards/data/models/daily_card_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';

class DailyCardModel extends DailyCardEntity {
  DailyCardModel({
    required super.cardId,
    required super.cashbookId,
    required super.name,
    super.number,
    super.bankName,
    required super.colorIndex,
    required super.createdBy,
    required super.creatorName,
    required super.createdAt,
  });

  factory DailyCardModel.fromJson(
      Map<String, dynamic> json, String documentId) {
    return DailyCardModel(
      cardId: documentId,
      cashbookId: json['cashbookId'] as String? ?? '',
      name: json['name'] as String? ?? 'Card',
      number: json['number'] as String?,
      bankName: json['bankName'] as String?,
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
      createdBy: json['createdBy'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? 'Partner',
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  factory DailyCardModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return DailyCardModel.fromJson(doc.data()!, doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'cashbookId': cashbookId,
      'name': name,
      if (number != null && number!.isNotEmpty) 'number': number,
      if (bankName != null && bankName!.isNotEmpty) 'bankName': bankName,
      'colorIndex': colorIndex,
      'createdBy': createdBy,
      'creatorName': creatorName.isEmpty ? 'Partner' : creatorName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
