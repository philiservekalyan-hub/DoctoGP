/* eslint-disable max-len */
const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

// Secrets stored in Google Cloud Secret Manager
const MSG91_AUTH_KEY = defineSecret("MSG91_AUTH_KEY");
const MSG91_TEMPLATE_ID = defineSecret("MSG91_TEMPLATE_ID");

// Common region for all functions
const REGION = "asia-south1";
const RUNTIME_OPTS = {
  region: REGION,
  secrets: [MSG91_AUTH_KEY, MSG91_TEMPLATE_ID],
};

// =================================================================
// Role custom-claim sync
// =================================================================

/**
 * Sets { role } custom claim when a new user doc is created.
 * Triggered on: users/{uid} create
 */
exports.onUserCreated = onDocumentCreated(
    { document: "users/{uid}", region: REGION },
    async (event) => {
      const uid = event.params.uid;
      const data = event.data?.data() || {};
      const role = data.role || "patient";

      try {
        await admin.auth().setCustomUserClaims(uid, { role });
        console.log(`Set role=${role} for new user ${uid}`);
      } catch (error) {
        console.error(`Failed to set role for ${uid}:`, error);
      }
    });

/**
 * Syncs { role } custom claim when a user doc's role field changes.
 * Triggered on: users/{uid} update
 */
exports.onUserUpdated = onDocumentUpdated(
    { document: "users/{uid}", region: REGION },
    async (event) => {
      const uid = event.params.uid;
      const before = event.data?.before.data() || {};
      const after = event.data?.after.data() || {};

      if (before.role === after.role) return;

      try {
        await admin.auth().setCustomUserClaims(uid, {
          role: after.role || "patient",
        });
        console.log(`Updated role to ${after.role} for user ${uid}`);
      } catch (error) {
        console.error(`Failed to update role for ${uid}:`, error);
      }
    });

/**
 * One-off HTTP function to backfill role claims for all existing users.
 * Call once via browser: https://...cloudfunctions.net/backfillRoles
 * Safe to leave deployed; does nothing destructive.
 */
exports.backfillRoles = onRequest(
    { region: REGION, invoker: "public", cors: true },
    async (req, res) => {
      try {
        const usersSnap = await admin.firestore().collection("users").get();
        let updated = 0;
        let skipped = 0;

        for (const doc of usersSnap.docs) {
          const role = doc.data().role || "patient";
          try {
            await admin.auth().setCustomUserClaims(doc.id, { role });
            updated++;
          } catch (e) {
            skipped++;
            console.error(`Skipped ${doc.id}:`, e.message);
          }
        }

        res.status(200).send(
            `Backfilled ${updated} users. Skipped ${skipped}.`,
        );
      } catch (error) {
        console.error("Backfill error:", error);
        res.status(500).send(`Error: ${error.message}`);
      }
    });

// =================================================================
// Scheduled confirmations
// =================================================================

// Runs every hour, marks appointments starting in the next 24-25h as
// confirmation-requested
exports.requestVisitConfirmations = onSchedule(
    {
      schedule: "every 60 minutes",
      timeZone: "Asia/Kolkata",
      region: REGION,
    },
    async () => {
      const now = new Date();
      const lower = new Date(now.getTime() + 24 * 3600 * 1000);
      const upper = new Date(now.getTime() + 25 * 3600 * 1000);

      const snap = await admin.firestore()
          .collection("appointments")
          .where("status", "==", "booked")
          .where("confirmationRequested", "==", false)
          .where("slot", ">=", admin.firestore.Timestamp.fromDate(lower))
          .where("slot", "<", admin.firestore.Timestamp.fromDate(upper))
          .get();

      const batch = admin.firestore().batch();
      snap.forEach((doc) => {
        batch.update(doc.ref, {confirmationRequested: true});
      });
      await batch.commit();
      console.log(`Marked ${snap.size} appointments for confirmation`);
    });

// =================================================================
// OTP / MFA (MSG91)
// =================================================================

// ---------------------------------------------------------------
// Send OTP for MFA enrollment
// ---------------------------------------------------------------
exports.sendOtp = onCall(RUNTIME_OPTS, async (request) => {
  const context = request;
  if (!context.auth) {
    throw new HttpsError(
        "unauthenticated",
        "User must be logged in to enroll MFA.",
    );
  }

  const {phoneNumber} = request.data;

  if (!phoneNumber || !phoneNumber.startsWith("+91")) {
    throw new HttpsError(
        "invalid-argument",
        "A valid Indian phone number (+91) is required.",
    );
  }

  // Rate limiting: max 5 OTPs per phone per hour
  const rateLimitRef = admin
      .firestore()
      .collection("otpRateLimits")
      .doc(phoneNumber.replace("+", ""));

  const now = Date.now();
  const windowStart = now - 3600000;

  const rateLimitDoc = await rateLimitRef.get();
  let requests = rateLimitDoc.exists ? rateLimitDoc.data().requests : [];
  requests = requests.filter((ts) => ts > windowStart);

  if (requests.length >= 5) {
    throw new HttpsError(
        "resource-exhausted",
        "Too many OTP requests. Please try again later.",
    );
  }

  requests.push(now);
  await rateLimitRef.set({
    requests,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Send OTP via MSG91
  const mobile = phoneNumber.replace("+", "");
  const url =
    "https://control.msg91.com/api/v5/otp" +
    `?template_id=${MSG91_TEMPLATE_ID.value()}` +
    `&mobile=${mobile}&otp_length=6&otp_expiry=10`;

  try {
    await axios.post(
        url,
        {},
        {
          headers: {
            authkey: MSG91_AUTH_KEY.value(),
            "Content-Type": "application/json",
          },
        },
    );

    const verificationId = `msg91_${phoneNumber}_${now}`;
    await admin
        .firestore()
        .collection("otpSessions")
        .doc(verificationId)
        .set({
          phoneNumber,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: new Date(now + 600000),
          userId: context.auth.uid,
        });

    return {success: true, verificationId};
  } catch (error) {
    console.error(
        "MSG91 Send OTP error:",
        error.response?.data || error.message,
    );
    throw new HttpsError(
        "internal",
        "Failed to send OTP. Please try again.",
    );
  }
});

// ---------------------------------------------------------------
// Send OTP for MFA challenge (during login)
// ---------------------------------------------------------------
exports.sendOtpForMfa = onCall(RUNTIME_OPTS, async (request) => {
  const {phoneNumber, session} = request.data;

  if (!phoneNumber || !phoneNumber.startsWith("+91")) {
    throw new HttpsError(
        "invalid-argument",
        "A valid Indian phone number is required.",
    );
  }

  const mobile = phoneNumber.replace("+", "");
  const url =
    "https://control.msg91.com/api/v5/otp" +
    `?template_id=${MSG91_TEMPLATE_ID.value()}` +
    `&mobile=${mobile}&otp_length=6&otp_expiry=10`;

  try {
    await axios.post(
        url,
        {},
        {
          headers: {
            authkey: MSG91_AUTH_KEY.value(),
            "Content-Type": "application/json",
          },
        },
    );

    const verificationId = `mfa_${phoneNumber}_${Date.now()}`;
    await admin
        .firestore()
        .collection("otpSessions")
        .doc(verificationId)
        .set({
          phoneNumber,
          mfaSession: session,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: new Date(Date.now() + 600000),
        });

    return {success: true, verificationId};
  } catch (error) {
    console.error(
        "MSG91 MFA Send error:",
        error.response?.data || error.message,
    );
    throw new HttpsError("internal", "Failed to send OTP.");
  }
});

// ---------------------------------------------------------------
// Verify OTP
// ---------------------------------------------------------------
exports.verifyOtp = onCall(RUNTIME_OPTS, async (request) => {
  const {phoneNumber, code} = request.data;

  const mobile = phoneNumber.replace("+", "");
  const url =
    "https://control.msg91.com/api/v5/otp/verify" +
    `?mobile=${mobile}&otp=${code}`;

  try {
    const response = await axios.get(url, {
      headers: {authkey: MSG91_AUTH_KEY.value()},
    });

    if (response.data.type === "success") {
      const verificationId =
        `msg91_verified_${phoneNumber}_${Date.now()}`;

      await admin.firestore().collection("auditLogs").add({
        action: "mfa_verification",
        phoneNumber: phoneNumber.replace(
            /(\+\d{2})\d+(\d{4})/, "$1****$2"),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        success: true,
      });

      return {verified: true, verificationId};
    }

    await admin.firestore().collection("auditLogs").add({
      action: "mfa_verification",
      phoneNumber: phoneNumber.replace(
          /(\+\d{2})\d+(\d{4})/, "$1****$2"),
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      success: false,
    });

    return {verified: false};
  } catch (error) {
    console.error(
        "MSG91 Verify error:",
        error.response?.data || error.message,
    );
    return {verified: false};
  }
});

/**
 * One-time backfill: add `type: "clinic"` to every existing clinic doc
 * that doesn't already have a `type` field. Safe to run multiple times.
 *
 * Call once via:
 *   https://backfillclinictypes-<hash>-el.a.run.app
 */
exports.backfillClinicTypes = onRequest(
    { region: REGION, invoker: "public", cors: true },
    async (req, res) => {
      try {
        const snap = await admin.firestore().collection("clinics").get();
        let updated = 0;
        let skipped = 0;

        for (const doc of snap.docs) {
          const data = doc.data();
          if (data.type) {
            skipped++;
            continue;
          }
          await doc.ref.update({ type: "clinic" });
          updated++;
        }

        res.status(200).send(
            `Backfilled ${updated} clinics. Skipped ${skipped}.`,
        );
      } catch (error) {
        console.error("backfillClinicTypes error:", error);
        res.status(500).send(`Error: ${error.message}`);
      }
    });

/**
 * One-time migration: for each doc in `labs/`, create a matching
 * `clinics/{labId}` doc with `type: "lab"`. Also backfills both sides
 * of the clinic↔lab link based on each lab's existing `clinicId`.
 *
 * After running, the old `labs/` collection can be deleted.
 *
 * Call once via:
 *   https://migratelabsstoclinics-<hash>-el.a.run.app
 */
exports.migrateLabsToClinics = onRequest(
    { region: REGION, invoker: "public", cors: true },
    async (req, res) => {
      try {
        const labsSnap = await admin.firestore().collection("labs").get();
        let migrated = 0;
        let linksCreated = 0;
        let skipped = 0;

        for (const labDoc of labsSnap.docs) {
          const labId = labDoc.id;
          const labData = labDoc.data();

          // Skip if already migrated
          const alreadyMigrated =
              await admin.firestore().collection("clinics").doc(labId).get();
          if (alreadyMigrated.exists &&
              alreadyMigrated.data()?.type === "lab") {
            skipped++;
            continue;
          }

          // 1. Create the clinic doc with type="lab"
          await admin.firestore().collection("clinics").doc(labId).set({
            "type": "lab",
            "name": labData.name ?? "Unnamed Lab",
            "clinicCode": labData.clinicCode ?? "",
            "ownerEmail": labData.ownerEmail ?? labData.email ?? "",
            "address": labData.address ?? "",
            "phone": labData.phone ?? "",
            "active": labData.active !== false,
            "createdAt": labData.createdAt ?? FieldValue.serverTimestamp(),
            "migratedFromLabsCollection": true,
          }, { merge: true });
          migrated++;

          // 2. Create both sides of the link with any clinic this lab
          //    was previously attached to.
          const referringClinicId = labData.clinicId;
          if (referringClinicId) {
            const clinicDoc = await admin.firestore()
                .collection("clinics").doc(referringClinicId).get();
            const clinicName = clinicDoc.data()?.name ?? "Clinic";

            const linkBase = {
              "clinicId": referringClinicId,
              "clinicName": clinicName,
              "labClinicId": labId,
              "labName": labData.name ?? "Lab",
              "linkedAt": FieldValue.serverTimestamp(),
              "linkedByAdminUid": "migration",
              "active": true,
            };

            await admin.firestore()
                .collection("clinics").doc(referringClinicId)
                .collection("linkedLabs").doc(labId)
                .set(linkBase, { merge: true });

            await admin.firestore()
                .collection("clinics").doc(labId)
                .collection("linkedClinics").doc(referringClinicId)
                .set(linkBase, { merge: true });

            linksCreated++;
          }
        }

        res.status(200).send(
            `Migrated ${migrated} labs. Created ${linksCreated} links. Skipped ${skipped}.`,
        );
      } catch (error) {
        console.error("migrateLabsToClinics error:", error);
        res.status(500).send(`Error: ${error.message}`);
      }
    });

/**
 * One-time backfill for existing `labOrders` docs:
 *   - Rename `clinicId` → `referringClinicId` (keep the old field for
 *     safety, but also write the new one).
 *   - Rename `labId` → `labClinicId`.
 *   - Add `deptId: null` if missing.
 *
 * Safe to run multiple times — skips docs already migrated.
 *
 * Call once via:
 *   https://backfilllabordersfields-<hash>-el.a.run.app
 */
exports.backfillLabOrdersFields = onRequest(
    { region: REGION, invoker: "public", cors: true },
    async (req, res) => {
      try {
        const snap = await admin.firestore().collection("labOrders").get();
        let updated = 0;
        let skipped = 0;

        for (const doc of snap.docs) {
          const data = doc.data();

          // Already migrated?
          if (data.referringClinicId && data.labClinicId) {
            skipped++;
            continue;
          }

          const update = {};

          if (!data.referringClinicId && data.clinicId) {
            update.referringClinicId = data.clinicId;
          }

          if (!data.labClinicId && data.labId) {
            update.labClinicId = data.labId;
          }

          if (data.deptId === undefined) {
            update.deptId = null;
          }

          // If nothing to change, skip
          if (Object.keys(update).length === 0) {
            skipped++;
            continue;
          }

          await doc.ref.update(update);
          updated++;
        }

        res.status(200).send(
            `Backfilled ${updated} lab orders. Skipped ${skipped}.`,
        );
      } catch (error) {
        console.error("backfillLabOrdersFields error:", error);
        res.status(500).send(`Error: ${error.message}`);
      }
    });