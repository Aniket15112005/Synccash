// functions/index.js  —  SyncCash push notifications
// Only iOS PWA receives notifications. Android APK never receives notifications.
// Triggers: income added, income edited, income deleted → notify iOS/PWA user.

"use strict";

const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } =
  require("firebase-functions/v2/firestore");
const { initializeApp }            = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging }             = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

// ─── Helper: get sender's platform ───────────────────────────────────────────

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

// ─── Helper: find the iOS/PWA receiver in this cashbook ──────────────────────
// Returns { uid, tokens } or null.

async function getReceiver(cashbookId, senderUid) {
  try {
    const cashbookSnap = await db.collection("cashbooks").doc(cashbookId).get();
    if (!cashbookSnap.exists) {
      console.log("⏭️  Cashbook not found:", cashbookId);
      return null;
    }

    const d = cashbookSnap.data();

    // ── Fast path: tokens cached directly on the cashbook doc ────────────────
    const cachedTokens  = d.iosReceiverTokens ?? [];
    const iosReceiverId = d.iosReceiverId     ?? null;

    if (cachedTokens.length > 0 && iosReceiverId && iosReceiverId !== senderUid) {
      console.log(`✅ Fast path: receiver=${iosReceiverId} tokens=${cachedTokens.length}`);
      return { uid: iosReceiverId, tokens: cachedTokens };
    }

    // ── Slow path: look up member UIDs from cashbook doc ─────────────────────
    // Support multiple field naming conventions
    let memberUids = d.memberUids ?? d.members ?? null;
    if (!memberUids) {
      // Try ownerId / participantId pair
      const pair = [d.ownerId, d.participantId].filter(Boolean);
      if (pair.length > 0) memberUids = pair;
    }

    // ── Fallback path: query users collection for anyone in this cashbook ────
    if (!memberUids || memberUids.length === 0) {
      console.log("⚠️  No member fields on cashbook doc — falling back to users query");
      const usersSnap = await db.collection("users")
        .where("currentCashbookId", "==", cashbookId)
        .get();
      memberUids = usersSnap.docs.map((d) => d.id);
      console.log(`  Fallback found ${memberUids.length} user(s) via currentCashbookId`);
    }

    if (!memberUids || memberUids.length === 0) {
      console.log("⏭️  No members found for cashbook:", cashbookId);
      return null;
    }

    for (const uid of memberUids) {
      if (uid === senderUid) continue;
      const userSnap = await db.collection("users").doc(uid).get();
      if (!userSnap.exists) continue;
      const uData    = userSnap.data();
      const platform = uData.platform ?? "";
      const tokens   = uData.fcmTokens ?? [];

      const isWebOrIOS = platform === "ios" || platform === "web";
      if (isWebOrIOS && tokens.length > 0) {
        console.log(`✅ Slow path: receiver=${uid} platform=${platform} tokens=${tokens.length}`);
        return { uid, tokens };
      }
      console.log(`  Skipping uid=${uid} platform='${platform}' tokens=${tokens.length}`);
    }

    console.log("⏭️  No iOS/web receiver with saved tokens found in cashbook:", cashbookId);
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
    data: { title, body, cashbookId: cashbookId ?? "" },
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
        console.error(`FCM error [${i}]:`, r.error?.message ?? code);
      }
    }
  });

  if (stale.length > 0) {
    console.log(`  Removing ${stale.length} stale token(s) for ${uid}`);
    try {
      await Promise.all([
        db.collection("users").doc(uid).update({
          fcmTokens: FieldValue.arrayRemove(...stale),
        }),
        db.collection("cashbooks").doc(cashbookId).update({
          iosReceiverTokens: FieldValue.arrayRemove(...stale),
        }),
      ]);
    } catch (e) {
      console.error("Stale token cleanup error:", e.message);
    }
  }

  console.log(`✅ ${batchResponse.successCount}/${tokens.length} delivered to ${uid} — "${title}"`);
}

// ─── TRIGGER 1: Income added ──────────────────────────────────────────────────

exports.onTransactionCreated = onDocumentCreated(
  { document: "cashbooks/{cashbookId}/transactions/{transactionId}", region: "us-central1" },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { cashbookId } = event.params;
    const senderUid      = data.createdBy ?? null;
    const type           = (data.type ?? "").toLowerCase();

    console.log(`📥 onTransactionCreated type=${type} sender=${senderUid} cashbook=${cashbookId}`);

    if (type !== "income") { console.log("⏭️  Not income — silent"); return; }

    const platform = await getSenderPlatform(senderUid);
    if (platform !== "android") { console.log(`⏭️  Sender platform='${platform}' — silent`); return; }

    const receiver = await getReceiver(cashbookId, senderUid);
    if (!receiver) return;

    const amount = data.amount != null ? `₹${Number(data.amount).toLocaleString("en-IN")}` : "";
    const note   = data.note ?? data.description ?? data.category ?? "";
    const body   = [amount, note].filter(Boolean).join(" • ") || "A new income entry was added";

    await sendAndClean({ receiver, title: " Income Logged ", body, cashbookId });
  }
);

// ─── TRIGGER 2: Income edited ────────────────────────────────────────────────
// Guard: skip if no meaningful field changed (prevents double-fire with create).

exports.onTransactionUpdated = onDocumentUpdated(
  { document: "cashbooks/{cashbookId}/transactions/{transactionId}", region: "us-central1" },
  async (event) => {
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();
    if (!before || !after) return;

    const { cashbookId } = event.params;
    const senderUid      = after.updatedBy ?? after.createdBy ?? null;
    const type           = (after.type ?? "").toLowerCase();

    console.log(`✏️  onTransactionUpdated type=${type} sender=${senderUid} cashbook=${cashbookId}`);

    // Only fire if a user-visible field actually changed.
    // This prevents double notifications when the app writes metadata
    // (e.g. updatedAt, syncedAt) right after creating a transaction.
    const changed =
      before.amount      !== after.amount      ||
      before.type        !== after.type        ||
      before.note        !== after.note        ||
      before.description !== after.description ||
      before.category    !== after.category    ||
      before.date        !== after.date;

    if (!changed) { console.log("⏭️  No meaningful field changed — silent"); return; }

    // Only notify on income (not expense edits)
    if (type !== "income") { console.log("⏭️  Not income — silent"); return; }

    const platform = await getSenderPlatform(senderUid);
    if (platform !== "android") { console.log(`⏭️  Sender platform='${platform}' — silent`); return; }

    const receiver = await getReceiver(cashbookId, senderUid);
    if (!receiver) return;

    const amount = after.amount != null ? `₹${Number(after.amount).toLocaleString("en-IN")}` : "";
    const note   = after.note ?? after.description ?? after.category ?? "";
    const body   = [amount, note].filter(Boolean).join(" • ") || "An income entry was updated";

    await sendAndClean({ receiver, title: "Transaction Updated", body, cashbookId });
  }
);

// ─── TRIGGER 3: Income deleted ───────────────────────────────────────────────

exports.onTransactionDeleted = onDocumentDeleted(
  { document: "cashbooks/{cashbookId}/transactions/{transactionId}", region: "us-central1" },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { cashbookId } = event.params;
    const senderUid      = data.deletedBy ?? data.updatedBy ?? data.createdBy ?? null;
    const type           = (data.type ?? "").toLowerCase();

    console.log(`🗑️  onTransactionDeleted type=${type} sender=${senderUid} cashbook=${cashbookId}`);

    if (type !== "income") { console.log("⏭️  Not income — silent"); return; }

    const platform = await getSenderPlatform(senderUid);
    if (platform !== "android") { console.log(`⏭️  Sender platform='${platform}' — silent`); return; }

    const receiver = await getReceiver(cashbookId, senderUid);
    if (!receiver) return;

    const amount = data.amount != null ? `₹${Number(data.amount).toLocaleString("en-IN")}` : "";
    const note   = data.note ?? data.description ?? data.category ?? "";
    const body   = [amount, note].filter(Boolean).join(" • ") || "An income entry was deleted";

    await sendAndClean({ receiver, title: " Income Entry Deleted", body, cashbookId });
  }
);