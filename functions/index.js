const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
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

    // 1. Get cashbook
    const cashbookDoc = await db.collection("cashbooks").doc(cashbookId).get();
    if (!cashbookDoc.exists) return;

    const cashbook = cashbookDoc.data();

    // 2. Identify sender
    const senderId =
      transaction.createdBy ||
      transaction.userId ||
      transaction.addedBy ||
      transaction.uid;

    if (!senderId) {
      console.error(
        "❌ Cannot determine senderId. Transaction is missing createdBy/userId/addedBy/uid."
      );
      return;
    }

    // 3. Fixed notification receiver — only this user ever gets notified.
    //    Set notificationReceiverId on your cashbook document in Firestore.
    //    If not set, falls back to the other member (original behaviour).
    const notificationReceiverId =
      cashbook.notificationReceiverId ||
      [cashbook.ownerId, cashbook.participantId]
        .filter(Boolean)
        .find((id) => id !== senderId);

    if (!notificationReceiverId) {
      console.log("No recipient found — cashbook may only have one member.");
      return;
    }

    // 4. Never notify the sender — even if they are somehow the designated receiver
    if (notificationReceiverId === senderId) {
      console.log(
        `Sender (${senderId}) is the designated receiver — no notification sent.`
      );
      return;
    }

    console.log(
      `senderId: ${senderId} | notificationReceiverId: ${notificationReceiverId}`
    );

    // 5. Fetch receiver's FCM tokens
    const receiverDoc = await db
      .collection("users")
      .doc(notificationReceiverId)
      .get();

    if (!receiverDoc.exists) {
      console.log("Receiver user document not found:", notificationReceiverId);
      return;
    }

    const rawTokens = receiverDoc.data().fcmTokens || [];
    if (rawTokens.length === 0) {
      console.log("No FCM tokens for receiver:", notificationReceiverId);
      return;
    }

    // Deduplicate — one device should never get two notifications
    const tokens = [...new Set(rawTokens)];

    // 6. SAFETY NET — also fetch sender's tokens and strip them out.
    //    Guards against edge cases where sender's token ends up in receiver's list.
    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderTokenSet = new Set(
      senderDoc.exists ? (senderDoc.data().fcmTokens || []) : []
    );
    const safeTokens = tokens.filter((t) => !senderTokenSet.has(t));

    if (safeTokens.length === 0) {
      console.log("No safe tokens to send to after stripping sender tokens.");
      return;
    }

    console.log(
      `Sending to ${safeTokens.length} token(s) for receiver ${notificationReceiverId}`
    );

    // 7. Build notification payload
    const isIncome = transaction.type === "income";
    const amount = Number(transaction.amount) || 0;
    const category = transaction.category || transaction.note || "Transaction";
    const senderName =
      transaction.addedByName || transaction.createdByName || "Your partner";

    const formattedAmount = new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 0,
    }).format(amount);

    const title = isIncome
      ? `+${formattedAmount} Income Added`
      : `-${formattedAmount} Expense Added`;

    const body = `${senderName} added ${category} to SyncCash`;

    const baseMessage = {
      notification: { title, body },
      android: {
        priority: "high",
        notification: {
          channelId: "synccash_transactions",
          sound: "default",
          priority: "high",
          visibility: "PUBLIC",
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
    };

    // 8. Send and collect stale tokens
    const staleTokens = [];

    const sendPromises = safeTokens.map((token) =>
      messaging
        .send({ ...baseMessage, token })
        .catch((err) => {
          if (
            err.code === "messaging/invalid-registration-token" ||
            err.code === "messaging/registration-token-not-registered"
          ) {
            staleTokens.push(token);
            console.log("Stale token queued:", token.slice(0, 20) + "...");
          } else {
            console.error("FCM error:", err.code, err.message);
          }
        })
    );

    await Promise.all(sendPromises);

    // 9. Batch-remove stale tokens
    if (staleTokens.length > 0) {
      const staleSnapshots = await Promise.all(
        staleTokens.map((token) =>
          db.collection("users").where("fcmTokens", "array-contains", token).get()
        )
      );
      const batch = db.batch();
      staleSnapshots.forEach((snapshot, i) => {
        snapshot.forEach((doc) => {
          batch.update(doc.ref, {
            fcmTokens: FieldValue.arrayRemove(staleTokens[i]),
          });
        });
      });
      await batch.commit();
      console.log(`🗑️ Removed ${staleTokens.length} stale token(s)`);
    }

    console.log(
      `✅ Notified receiver (${notificationReceiverId}) | sender (${senderId}) excluded`
    );
  }
);
