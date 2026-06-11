import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:synccash/features/transactions/data/models/transaction_model.dart';

import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

import 'package:synccash/features/transactions/domain/repositories/transaction_repository.dart';



class TransactionRepositoryImpl implements TransactionRepository {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;



  @override

  Future<void> addTransaction(TransactionEntity tx) async {

    try {

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

    } on FirebaseException {

      rethrow;

    }

  }



  @override

  Future<void> deleteTransaction(TransactionEntity tx) async {

    try {

      final txRef = _firestore

          .collection('cashbooks')

          .doc(tx.cashbookId)

          .collection('transactions')

          .doc(tx.transactionId);



      final cashbookRef =

          _firestore.collection('cashbooks').doc(tx.cashbookId);



      await _firestore.runTransaction((transaction) async {

        final txSnapshot = await transaction.get(txRef);



        if (!txSnapshot.exists) {

          throw Exception(

            "Transaction '${tx.transactionId}' does not exist.",

          );

        }



        final cashbookSnapshot = await transaction.get(cashbookRef);



        if (!cashbookSnapshot.exists) {

          throw Exception(

            "Cashbook '${tx.cashbookId}' does not exist.",

          );

        }



        final cashbookData = cashbookSnapshot.data();



        if (cashbookData == null) {

          throw Exception(

            "Cashbook '${tx.cashbookId}' contains no data.",

          );

        }



        final txData = txSnapshot.data()!;

        final num amount = (txData['amount'] as num?) ?? tx.amount;

        final String type = (txData['type'] as String?) ?? tx.type;



        final num currentBalance =

            (cashbookData['totalBalance'] as num?) ?? 0;

        final num currentIncome =

            (cashbookData['totalIncome'] as num?) ?? 0;

        final num currentExpense =

            (cashbookData['totalExpense'] as num?) ?? 0;



        final bool isIncome =

            type.toLowerCase().trim() == 'income';



        if (isIncome) {

          transaction.update(cashbookRef, {

            'totalBalance': currentBalance - amount,

            'totalIncome': currentIncome - amount,

          });

        } else {

          transaction.update(cashbookRef, {

            'totalBalance': currentBalance + amount,

            'totalExpense': currentExpense - amount,

          });

        }



        transaction.delete(txRef);

      });

    } on FirebaseException {

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


