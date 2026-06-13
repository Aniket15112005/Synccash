// functions/index.js  —  SyncCash push notifications
// Compatible: firebase-functions ^7, firebase-admin ^13, Node 24
//
// Rules:
//   Android adds INCOME        → iOS/PWA user notified  ✅
//   Android edits ANY entry    → iOS/PWA user notified  ✅
//   Android deletes INCOME     → iOS/PWA user notified  ✅  ← ADDED
//   Android adds EXPENSE       → silent                 ❌
//   Android deletes EXPENSE    → silent                 ❌
//   iOS/PWA does ANYTHING      → Android never notified ❌

"use strict";

// ── CHANGED: added onDocumentDeleted to imports ──────────────────────────────
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } =
  require("firebase-functions/v2/firestore");
const { initializeApp }            = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging }             = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

// ─── Helper: sender's platform ───────────────────────────────────────────────

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

// ─── Helper: find receiver tokens ────────────────────────────────────────────

async function getReceiver(cashbookId, senderUid) {
  try {
    const cashbookSnap = await db.collection("cashbooks").doc(cashbookId).get();
    if (!cashbookSnap.exists) {
      console.log("⏭️  Cashbook not found:", cashbookId);
      return null;
    }

    const d             = cashbookSnap.data();
    const cachedTokens  = d.iosReceiverTokens ?? [];
    const iosReceiverId = d.iosReceiverId     ?? null;

    // Fast path — FCMService writes this to the cashbook doc on every login
    if (cachedTokens.length > 0 && iosReceiverId && iosReceiverId !== senderUid) {
      console.log(`✅ Fast path receiver: ${iosReceiverId} (${cachedTokens.length} token(s))`);
      return { uid: iosReceiverId, tokens: cachedTokens };
    }

    const memberUids =
      d.memberUids ??
      d.members ??
      [d.ownerId, d.participantId].filter(Boolean);

    console.log(`🔍 Slow path — checking members: ${memberUids}`);

    for (const uid of memberUids) {
      if (uid === senderUid) continue;
      const userSnap = await db.collection("users").doc(uid).get();
      if (!userSnap.exists) continue;
      const uData    = userSnap.data();
      const platform = uData.platform ?? "";
      const tokens   = uData.fcmTokens ?? [];

      const isNonAndroid = platform === "ios" || platform === "web";

      if (isNonAndroid && tokens.length > 0) {
        console.log(`✅ Slow path receiver: ${uid} platform=${platform} (${tokens.length} token(s))`);
        return { uid, tokens };
      }
    }

    console.log("⏭️  No non-Android receiver with tokens found");
    return null;
  } catch (e) {
    console.error("getReceiver error:", e.message);
    return null;
  }
}

// ─── Helper: send + clean stale tokens ───────────────────────────────────────

async function sendAndClean({ receiver, title, body, cashbookId }) {
  const { uid, tokens } = receiver;

  const messages = tokens.map((token) => ({
    token,
    data: {
      title,
      body,
      cashbookId: cashbookId ?? "",
    },
    webpush: {
      fcmOptions: { link: "/" },
      headers:    { Urgency: "high" },
    },
    apns: {
      payload: {
        aps: {
          alert:               { title, body },
          sound:               "default",
          badge:               1,
          "content-available": 1,
        },
      },
      headers: { "apns-priority": "10" },
    },
    android: { priority: "high" },
  }));

  let batchResponse;
  try {
    batchResponse = await getMessaging().sendEach(messages);
  } catch (e) {
    console.error("sendEach failed:", e.message);
    return;
  }

  const stale = [];
  batchResponse.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error?.code ?? "";
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        stale.push(tokens[i]);
      } else {
        console.error(`FCM send error [token ${i}]:`, r.error?.message ?? code);
      }
    }
  });

  if (stale.length > 0) {
    try {
      // ── CHANGED: also clean stale tokens from cashbooks doc ──────────────
      await Promise.all([
        db.collection("users").doc(uid).update({
          fcmTokens: FieldValue.arrayRemove(...stale),
        }),
        db.collection("cashbooks").doc(cashbookId).update({
          iosReceiverTokens: FieldValue.arrayRemove(...stale),
        }),
      ]);
      console.log(`  Removed ${stale.length} stale token(s) for ${uid}`);
    } catch (e) {
      console.error("Stale token cleanup error:", e.message);
    }
  }

  console.log(`✅ ${batchResponse.successCount}/${tokens.length} sent to ${uid} — "${title}"`);
}

// ─── TRIGGER 1: New transaction added ────────────────────────────────────────

exports.onTransactionCreated = onDocumentCreated(
  {
    document: "cashbooks/{cashbookId}/transactions/{transactionId}",
    region:   "us-central1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { cashbookId } = event.params;
    const senderUid      = data.createdBy ?? null;
    const type           = (data.type ?? "").toLowerCase();

    console.log(`📥 onTransactionCreated — type:${type} sender:${senderUid} cashbook:${cashbookId}`);

    if (type !== "income") {
      console.log("⏭️  Expense addition — silent");
      return;
    }

    const platform = await getSenderPlatform(senderUid);
    if (platform !== "android") {
      console.log(`⏭️  Sender platform '${platform}' — silent`);
      return;
    }

    const receiver = await getReceiver(cashbookId, senderUid);
    if (!receiver) return;

    const amount = data.amount != null
      ? `₹${Number(data.amount).toLocaleString("en-IN")}` : "";
    const note   = data.note ?? data.description ?? data.category ?? "";
    const body   = [amount, note].filter(Boolean).join(" • ") ||
                   "A new income entry was added";

    await sendAndClean({ receiver, title: "💰 New Income Added", body, cashbookId });
  }
);

// ─── TRIGGER 2: Transaction edited ───────────────────────────────────────────

exports.onTransactionUpdated = onDocumentUpdated(
  {
    document: "cashbooks/{cashbookId}/transactions/{transactionId}",
    region:   "us-central1",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();
    if (!before || !after) return;

    const { cashbookId } = event.params;
    const senderUid      = after.updatedBy ?? after.createdBy ?? null;
    const type           = (after.type ?? "").toLowerCase();

    console.log(`✏️  onTransactionUpdated — type:${type} sender:${senderUid} cashbook:${cashbookId}`);

    const changed =
      before.amount      !== after.amount      ||
      before.type        !== after.type        ||
      before.note        !== after.note        ||
      before.description !== after.description ||
      before.category    !== after.category    ||
      before.date        !== after.date;

    if (!changed) {
      console.log("⏭️  No meaningful field changed — silent");
      return;
    }

    const platform = await getSenderPlatform(senderUid);
    if (platform !== "android") {
      console.log(`⏭️  Sender platform '${platform}' — silent`);
      return;
    }

    const receiver = await getReceiver(cashbookId, senderUid);
    if (!receiver) return;

    const amount    = after.amount != null
      ? `₹${Number(after.amount).toLocaleString("en-IN")}` : "";
    const note      = after.note ?? after.description ?? after.category ?? "";
    const typeLabel = type === "income" ? "Income" : "Expense";
    const body      = [amount, note].filter(Boolean).join(" • ") ||
                      `A ${type} entry was updated`;

    await sendAndClean({
      receiver,
      title: `✏️ ${typeLabel} Entry Edited`,
      body,
      cashbookId,
    });
  }
);

// ─── TRIGGER 3: Transaction deleted ──────────────────────────────────────────
// ── CHANGED: entire block below is new ───────────────────────────────────────

exports.onTransactionDeleted = onDocumentDeleted(
  {
    document: "cashbooks/{cashbookId}/transactions/{transactionId}",
    region:   "us-central1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { cashbookId } = event.params;
    const senderUid      = data.deletedBy ?? data.updatedBy ?? data.createdBy ?? null;
    const type           = (data.type ?? "").toLowerCase();

    console.log(`🗑️  onTransactionDeleted — type:${type} sender:${senderUid} cashbook:${cashbookId}`);

    // Only notify on income deletion; expense deletion is silent
    if (type !== "income") {
      console.log("⏭️  Expense deletion — silent");
      return;
    }

    const platform = await getSenderPlatform(senderUid);
    if (platform !== "android") {
      console.log(`⏭️  Sender platform '${platform}' — silent`);
      return;
    }

    const receiver = await getReceiver(cashbookId, senderUid);
    if (!receiver) return;

    const amount = data.amount != null
      ? `₹${Number(data.amount).toLocaleString("en-IN")}` : "";
    const note   = data.note ?? data.description ?? data.category ?? "";
    const body   = [amount, note].filter(Boolean).join(" • ") ||
                   "An income entry was deleted";

    await sendAndClean({ receiver, title: "🗑️ Income Entry Deleted", body, cashbookId });
  }
);