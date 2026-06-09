import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/transactions/data/models/transaction_model.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/domain/repositories/transaction_repository.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<void> addTransaction(TransactionEntity tx) async {
    try {
      print("DIAGNOSTIC ---> Cashbook ID: ${tx.cashbookId}");
      print("DIAGNOSTIC ---> Creator ID: ${tx.createdBy}");
      print("DIAGNOSTIC ---> Amount: ${tx.amount}");
      print("DIAGNOSTIC ---> Type: ${tx.type}");

      final txRef = _firestore
          .collection('cashbooks')
          .doc(tx.cashbookId)
          .collection('transactions')
          .doc();

      final cashbookRef =
          _firestore.collection('cashbooks').doc(tx.cashbookId);

      final model = TransactionModel(
        transactionId: txRef.id,
        cashbookId: tx.cashbookId,
        createdBy: tx.createdBy,
        creatorName: tx.creatorName,
        createdAt: tx.createdAt,
        amount: tx.amount,
        type: tx.type,
        category: tx.category,
        description: tx.description,
      );

      await _firestore.runTransaction((transaction) async {
        final cashbookSnapshot = await transaction.get(cashbookRef);

        if (!cashbookSnapshot.exists) {
          throw Exception(
            "Cashbook '${tx.cashbookId}' does not exist.",
          );
        }

        final data = cashbookSnapshot.data();

        if (data == null) {
          throw Exception(
            "Cashbook '${tx.cashbookId}' contains no data.",
          );
        }

        final num currentBalance =
            (data['totalBalance'] as num?) ?? 0;

        final num currentIncome =
            (data['totalIncome'] as num?) ?? 0;

        final num currentExpense =
            (data['totalExpense'] as num?) ?? 0;

        transaction.set(txRef, model.toJson());

        final bool isIncome =
            tx.type.toLowerCase().trim() == 'income';

        if (isIncome) {
          transaction.update(cashbookRef, {
            'totalBalance': currentBalance + tx.amount,
            'totalIncome': currentIncome + tx.amount,
          });
        } else {
          transaction.update(cashbookRef, {
            'totalBalance': currentBalance - tx.amount,
            'totalExpense': currentExpense + tx.amount,
          });
        }
      });

      print("SUCCESS ---> Transaction committed.");
    } on FirebaseException catch (e, stackTrace) {
      print("=================================================");
      print("FIREBASE ERROR CODE: ${e.code}");
      print("FIREBASE ERROR MESSAGE: ${e.message}");
      print(stackTrace);
      print("=================================================");
      rethrow;
    } catch (e, stackTrace) {
      print("=================================================");
      print("GENERAL ERROR: $e");
      print(stackTrace);
      print("=================================================");
      rethrow;
    }
  }

  @override
  Stream<List<TransactionEntity>> getTransactionsStream(
      String cashbookId) {
    return _firestore
        .collection('cashbooks')
        .doc(cashbookId)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => TransactionModel.fromJson(
                  doc.data(),
                  doc.id,
                ),
              )
              .toList(),
        );
  }
}