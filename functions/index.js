const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.notifyTransactionAdded = onDocumentCreated(
  {
    document: "cashbooks/{cashbookId}/transactions/{transactionId}",
    region: "asia-south2",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const transaction = snap.data();
    const cashbookId = event.params.cashbookId;

    const db = getFirestore();
    const messaging = getMessaging();

    // 1. Get the cashbook to find both user IDs
    const cashbookDoc = await db.collection("cashbooks").doc(cashbookId).get();
    if (!cashbookDoc.exists) return;

    const cashbook = cashbookDoc.data();
    // Adjust field names to match YOUR Firestore cashbook document
    const memberIds = cashbook.memberIds || cashbook.members || [];

    // 2. The sender is the one who created the transaction
    const senderId = transaction.createdBy || transaction.userId || transaction.addedBy;

    // 3. Recipients = everyone in cashbook EXCEPT the sender
    const recipientIds = memberIds.filter((id) => id !== senderId);
    if (recipientIds.length === 0) return;

    // 4. Collect all FCM tokens of recipients
    const tokenFetches = recipientIds.map((uid) =>
      db.collection("users").doc(uid).get()
    );
    const userDocs = await Promise.all(tokenFetches);

    const allTokens = [];
    userDocs.forEach((doc) => {
      if (doc.exists) {
        const tokens = doc.data().fcmTokens || [];
        allTokens.push(...tokens);
      }
    });

    if (allTokens.length === 0) return;

    // 5. Build a professional bank-style notification
    const isIncome = transaction.type === "income";
    const amount = transaction.amount || 0;
    const category = transaction.category || transaction.note || "Transaction";
    const senderName = transaction.addedByName || "Your partner";

    const formattedAmount = new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 0,
    }).format(amount);

    const title = isIncome
      ? `+${formattedAmount} Income Added`
      : `-${formattedAmount} Expense Added`;

    const body = `${senderName} added ${category} to SyncCash`;

    // 6. Send to each token individually (handles stale tokens gracefully)
    const sendPromises = allTokens.map((token) =>
      messaging
        .send({
          token,
          notification: { title, body },
          android: {
            priority: "high",
            notification: {
              channelId: "synccash_transactions",
              sound: "default",
              priority: "high",
              visibility: "PUBLIC",
              // Makes it look like a bank notification
              color: isIncome ? "#22C55E" : "#EF4444",
            },
          },
          apns: {
            payload: {
              aps: {
                alert: { title, body },
                sound: "default",
                badge: 1,
              },
            },
          },
          data: {
            cashbookId,
            transactionId: event.params.transactionId,
            type: transaction.type || "expense",
            amount: String(amount),
          },
        })
        .catch((err) => {
          // If token is invalid/expired, remove it from Firestore
          if (
            err.code === "messaging/invalid-registration-token" ||
            err.code === "messaging/registration-token-not-registered"
          ) {
            return db
              .collection("users")
              .where("fcmTokens", "array-contains", token)
              .get()
              .then((snapshot) => {
                snapshot.forEach((doc) => {
                  doc.ref.update({
                    fcmTokens: getFirestore.FieldValue
                      ? getFirestore.FieldValue.arrayRemove(token)
                      : snap.ref.firestore.FieldValue?.arrayRemove(token),
                  });
                });
              });
          }
          console.error("FCM send error:", err.code, err.message);
        })
    );

    await Promise.all(sendPromises);
    console.log(`✅ Notified ${allTokens.length} device(s) for transaction in cashbook ${cashbookId}`);
  }
);