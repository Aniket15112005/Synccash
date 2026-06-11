const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

admin.initializeApp();

exports.notifyTransactionAdded = onDocumentCreated(
  "cashbooks/{cashbookId}/transactions/{transactionId}",
  async (event) => {
    try {
      if (!event.data) {
        logger.error("No transaction data received");
        return;
      }

      const transaction = event.data.data();
      const cashbookId = event.params.cashbookId;

      logger.info(`New transaction in cashbook ${cashbookId}`);

      // Get cashbook document
      const cashbookRef = admin.firestore()
        .collection("cashbooks")
        .doc(cashbookId);

      const cashbookSnap = await cashbookRef.get();

      if (!cashbookSnap.exists) {
        logger.error("Cashbook document not found");
        return;
      }

      const cashbook = cashbookSnap.data();

      const ownerId = cashbook.ownerId;
      const participantId = cashbook.participantId;

      const createdBy = transaction.createdBy;

      if (!createdBy) {
        logger.error("Transaction missing createdBy field");
        return;
      }

      // Determine recipient
      let receiverId;

      if (createdBy === ownerId) {
        receiverId = participantId;
      } else if (createdBy === participantId) {
        receiverId = ownerId;
      } else {
        logger.error("createdBy does not match owner or participant");
        return;
      }

      // Load recipient user document
      const userSnap = await admin.firestore()
        .collection("users")
        .doc(receiverId)
        .get();

      if (!userSnap.exists) {
        logger.error(`User ${receiverId} not found`);
        return;
      }

      const user = userSnap.data();

      if (
        !user.fcmTokens ||
        !Array.isArray(user.fcmTokens) ||
        user.fcmTokens.length === 0
      ) {
        logger.info(`No FCM tokens for user ${receiverId}`);
        return;
      }

      const amount = transaction.amount || 0;
      const description = transaction.description || "Transaction";
      const creatorName = transaction.creatorName || "Someone";
      const type = transaction.type || "";

      const message = {
        notification: {
          title: "Cashbook Updated",
          body: `${creatorName}: ₹${amount} - ${description}`,
        },
        data: {
          cashbookId: cashbookId,
          transactionId: event.params.transactionId,
          type: type,
        },
        tokens: user.fcmTokens,
      };

      const response = await admin.messaging().sendMulticast(message);
      logger.info(
        `Notification sent. Success: ${response.successCount}, Failure: ${response.failureCount}`
      );

      // Remove invalid tokens automatically
      const invalidTokens = [];

      response.responses.forEach((resp, index) => {
        if (!resp.success) {
          const code = resp.error?.code || "";

          if (
            code.includes("registration-token-not-registered") ||
            code.includes("invalid-registration-token")
          ) {
            invalidTokens.push(user.fcmTokens[index]);
          }
        }
      });

      if (invalidTokens.length > 0) {
        await admin.firestore()
          .collection("users")
          .doc(receiverId)
          .update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(
              ...invalidTokens
            ),
          });

        logger.info(
          `Removed ${invalidTokens.length} invalid FCM token(s)`
        );
      }

      return;
    } catch (error) {
      logger.error("Notification function failed:", error);
      return;
    }
  }
);