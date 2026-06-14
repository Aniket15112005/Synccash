"use strict";

const { onDocumentCreated, onDocumentUpdated } =
  require("firebase-functions/v2/firestore");

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

// ─────────────────────────────────────────────────────────────
// FORMAT DATE
// ─────────────────────────────────────────────────────────────

function formatDate(timestamp) {
  if (!timestamp) return "";
  const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);

  const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

  const day = date.getDate();
  const month = months[date.getMonth()];
  const hours = date.getHours();
  const mins = date.getMinutes().toString().padStart(2, "0");
  const ampm = hours >= 12 ? "PM" : "AM";
  const hour12 = hours % 12 || 12;

  return `${day} ${month}, ${hour12}:${mins} ${ampm}`;
}

// ─────────────────────────────────────────────────────────────
// PLATFORM
// ─────────────────────────────────────────────────────────────

async function getSenderPlatform(uid) {
  if (!uid) return null;

  try {
    const snap = await db.collection("users").doc(uid).get();
    return snap.exists ? (snap.data().platform ?? null) : null;
  } catch (e) {
    console.error("getSenderPlatform error:", e.message);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────
// RECEIVER LOGIC
// ─────────────────────────────────────────────────────────────

async function getReceiver(cashbookId, senderUid) {
  try {
    const snap = await db.collection("cashbooks").doc(cashbookId).get();
    if (!snap.exists) return null;

    const d = snap.data();

    const cachedTokens = d.iosReceiverTokens ?? [];
    const iosReceiverId = d.iosReceiverId ?? null;

    if (cachedTokens.length > 0 && iosReceiverId && iosReceiverId !== senderUid) {
      return { uid: iosReceiverId, tokens: cachedTokens };
    }

    let memberUids = d.memberUids ?? d.members ?? null;

    if (!memberUids) {
      memberUids = [d.ownerId, d.participantId].filter(Boolean);
    }

    if (!memberUids.length) {
      const usersSnap = await db
        .collection("users")
        .where("currentCashbookId", "==", cashbookId)
        .get();

      memberUids = usersSnap.docs.map((d) => d.id);
    }

    for (const uid of memberUids) {
      if (uid === senderUid) continue;

      const userSnap = await db.collection("users").doc(uid).get();
      if (!userSnap.exists) continue;

      const uData = userSnap.data();
      const platform = (uData.platform || "").toLowerCase().trim();
      const tokens = uData.fcmTokens ?? [];

      const isValidReceiver =
        (platform === "ios" ||
         platform === "web" ||
         platform === "pwa");

      if (isValidReceiver && tokens.length > 0) {
        return { uid, tokens };
      }
    }

    return null;

  } catch (e) {
    console.error("getReceiver error:", e.message);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────
// SEND NOTIFICATIONS
// ─────────────────────────────────────────────────────────────

async function sendAndClean({ receiver, title, body, cashbookId }) {
  if (!receiver?.tokens?.length) {
    console.log("❌ No tokens found for receiver");
    return;
  }

  const { uid, tokens } = receiver;

  const messages = tokens.map((token) => ({
    token,
    data: { title, body, cashbookId: cashbookId ?? "" },
    webpush: {
      fcmOptions: { link: "/" },
      headers: { Urgency: "high" },
    },
    apns: {
      payload: {
        aps: {
          alert: { title, body },
          sound: "default",
          badge: 1,
          "content-available": 1,
        },
      },
      headers: { "apns-priority": "10" },
    },
    android: { priority: "high" },
  }));

  let response;
  try {
    response = await getMessaging().sendEach(messages);
  } catch (e) {
    console.error("sendEach failed:", e.message);
    return;
  }

  console.log(`✅ Sent: ${response.successCount}/${tokens.length}`);
}

// ─────────────────────────────────────────────────────────────
// TRIGGER 1 - CREATE
// ─────────────────────────────────────────────────────────────

exports.onTransactionCreated = onDocumentCreated(
  {
    document: "cashbooks/{cashbookId}/transactions/{transactionId}",
    region: "us-central1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data || data.isImport) return;

    const { cashbookId } = event.params;
    const senderUid = data.createdBy ?? null;
    const editorUid = data.lastEditedBy ?? null;
    const type = (data.type ?? "").toLowerCase();

    if (type !== "income") return;

    if (editorUid && editorUid !== senderUid) {
      const editorPlatform = await getSenderPlatform(editorUid);
      if (editorPlatform !== "android") return;
    }

    const platform = await getSenderPlatform(senderUid);
    if (platform !== "android") return;

    const receiver = await getReceiver(cashbookId, senderUid);
    if (!receiver) {
      console.log("❌ No receiver found");
      return;
    }

    const amount = data.amount
      ? `₹${Number(data.amount).toLocaleString("en-IN")}`
      : "";

    const cap = (s) => s ? s.charAt(0).toUpperCase() + s.slice(1).toLowerCase() : "";

    const title = `↓ ${amount} Income  ·  SyncCash`;
    const body  = `${data.creatorName ?? "Someone"}  ·  ${cap(data.category ?? "")}  ·  ${formatDate(data.createdAt)}`;

    await sendAndClean({ receiver, title, body, cashbookId });
  }
);

// ─────────────────────────────────────────────────────────────
// TRIGGER 2 - UPDATE
// ─────────────────────────────────────────────────────────────

exports.onTransactionUpdated = onDocumentUpdated(
  {
    document: "cashbooks/{cashbookId}/transactions/{transactionId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const { cashbookId } = event.params;

    const senderUid =
      after.lastEditedBy ?? after.updatedBy ?? after.createdBy ?? null;

    const type = (after.type ?? "").toLowerCase();

    if (type !== "income") return;

    const changed =
      before.amount !== after.amount ||
      before.description !== after.description ||
      before.category !== after.category;

    if (!changed) return;

    const platform = await getSenderPlatform(senderUid);
    if (platform !== "android") return;

    const receiver = await getReceiver(cashbookId, senderUid);
    if (!receiver) return;

    const cap = (s) => s ? s.charAt(0).toUpperCase() + s.slice(1).toLowerCase() : "";
    const fmt = (n) => `₹${Number(n).toLocaleString("en-IN")}`;

    const changes = [];
    if (before.amount !== after.amount) {
      changes.push(`${fmt(before.amount)} → ${fmt(after.amount)}`);
    }
    if (before.description !== after.description) {
      const bDesc = before.description || "—";
      const aDesc = after.description || "—";
      changes.push(`${bDesc} → ${aDesc}`);
    }
    if (before.category !== after.category) {
      changes.push(`${cap(before.category)} → ${cap(after.category)}`);
    }

    const title = `❌ Entry Modified  ·  SyncCash`;
    const body  = `${after.creatorName ?? "Someone"}  ·  ${changes.join("  ·  ")}`;

    await sendAndClean({ receiver, title, body, cashbookId });
  }
);

// ─────────────────────────────────────────────────────────────
// ONE-TIME BALANCE RECALCULATE (HTTP trigger)
// Call once from Firebase Console > Functions > recalculateBalance
// or via: curl -X POST https://<region>-<project>.cloudfunctions.net/recalculateBalance
// ─────────────────────────────────────────────────────────────
const { onRequest } = require('firebase-functions/v2/https');

exports.recalculateBalance = onRequest(
  { region: 'us-central1' },
  async (req, res) => {
    try {
      const cashbooksSnap = await db.collection('cashbooks').get();
      const results = [];

      for (const cbDoc of cashbooksSnap.docs) {
        const cashbookId = cbDoc.id;
        const txSnap = await db
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('transactions')
          .get();

        let income  = 0;
        let expense = 0;

        for (const txDoc of txSnap.docs) {
          const d      = txDoc.data();
          const amount = Number(d.amount) || 0;
          const type   = (d.type ?? '').toLowerCase().trim();
          if (type === 'income') {
            income  += amount;
          } else {
            expense += amount;
          }
        }

        await db.collection('cashbooks').doc(cashbookId).update({
          totalIncome:  income,
          totalExpense: expense,
          totalBalance: income - expense,
        });

        results.push({ cashbookId, income, expense, balance: income - expense });
        console.log(`Recalculated ${cashbookId}: income=${income} expense=${expense} balance=${income - expense}`);
      }

      res.json({ ok: true, recalculated: results.length, results });
    } catch (err) {
      console.error('recalculateBalance error:', err.message);
      res.status(500).json({ ok: false, error: err.message });
    }
  }
);
