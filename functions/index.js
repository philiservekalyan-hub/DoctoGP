/* eslint-disable max-len */
const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");

admin.initializeApp();

// Secrets stored in Google Cloud Secret Manager
const MSG91_AUTH_KEY = defineSecret("MSG91_AUTH_KEY");
const MSG91_TEMPLATE_ID = defineSecret("MSG91_TEMPLATE_ID");
const MSG91_EMERGENCY_TEMPLATE_ID = defineSecret("MSG91_EMERGENCY_TEMPLATE_ID");

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




// =================================================================
// Chemist user creation
//
// Creates a Firebase Auth user + writes the users/{uid} Firestore
// doc + sends a password-reset email + marks the chemist doc as
// invited, all in one server-side transaction.
//
// Called from the admin dashboard's "Send invite" button.
//
// The Admin SDK bypasses Firestore security rules and doesn't touch
// the caller's auth session — no client-side auth-session juggling.
// =================================================================
exports.createChemistUser = onCall(
    { region: REGION },
    async (request) => {
      // ── Auth check: only admins can invite chemists ──
      if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "Sign in as an admin to send invites.",
        );
      }

      const callerSnap = await admin.firestore()
          .collection("users")
          .doc(request.auth.uid)
          .get();

      if (!callerSnap.exists || callerSnap.data().role !== "admin") {
        throw new HttpsError(
            "permission-denied",
            "Only STAT admins can invite chemists.",
        );
      }

      // ── Validate input ──
      const {
        email,
        name = "",
        phone = "",
        chemistDocId,
      } = request.data || {};

      if (!email || !email.includes("@")) {
        throw new HttpsError(
            "invalid-argument",
            "A valid email is required.",
        );
      }
      if (!chemistDocId) {
        throw new HttpsError(
            "invalid-argument",
            "chemistDocId is required.",
        );
      }

      // ── Verify the chemist doc exists ──
      const chemistRef = admin.firestore()
          .collection("chemists").doc(chemistDocId);
      const chemistSnap = await chemistRef.get();
      if (!chemistSnap.exists) {
        throw new HttpsError(
            "not-found",
            "Chemist record not found. Save the chemist first.",
        );
      }

      const normalizedEmail = email.trim().toLowerCase();

      // ── Create the auth user (or find existing) ──
      let uid;
      let created = false;
      try {
        const userRecord = await admin.auth().createUser({
          email: normalizedEmail,
          password: crypto.randomBytes(24).toString("base64"),
          emailVerified: false,
          disabled: false,
        });
        uid = userRecord.uid;
        created = true;
      } catch (err) {
        if (err.code === "auth/email-already-exists") {
          // Account exists — find it and re-link.
          const existing = await admin.auth()
              .getUserByEmail(normalizedEmail);
          uid = existing.uid;
        } else {
          console.error("createUser failed:", err);
          throw new HttpsError(
              "internal",
              `Failed to create user: ${err.message}`,
          );
        }
      }

      // ── Write the users/{uid} doc ──
      await admin.firestore().collection("users").doc(uid).set({
        name: name || "Chemist",
        email: normalizedEmail,
        phone: phone,
        role: "chemist",
        linkedChemistDocId: chemistDocId,
        orgType: "pharmacy",
        active: true,
        mustChangePassword: false,
        createdByUid: request.auth.uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // ── Send password reset email ──
      let resetLink = null;
      try {
        resetLink = await admin.auth()
            .generatePasswordResetLink(normalizedEmail);
      } catch (err) {
        console.warn("generatePasswordResetLink failed:", err);
      }

      // ── Mark the chemist doc as invited ──
      await chemistRef.update({
        linkedUserUid: uid,
        inviteStatus: "sent",
        inviteSentAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        uid,
        created,
        resetLink,
      };
    });

// =================================================================
// PILL REMINDERS — missed-dose escalation
//
// Runs every 5 minutes. Finds doses whose grace window has passed
// without confirmation, marks them missed, and queues an SMS to the
// patient's active emergency contact.
//
// The device path (Pill Guard) writes confirmedAt/confirmedBy='device'
// directly to pillDoses. That dose is no longer `status='pending'`, so
// this function skips it. No special-casing needed.
// =================================================================
exports.escalateMissedDoses = onSchedule(
    {
      schedule: "every 5 minutes",
      timeZone: "Asia/Kolkata",
      region: REGION,
    },
    async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      const missed = await db
          .collection("pillDoses")
          .where("status", "==", "pending")
          .where("graceUntil", "<=", now)
          .limit(200)
          .get();

      if (missed.empty) return;

      let escalated = 0;
      let noContact = 0;

      for (const dose of missed.docs) {
        const d = dose.data();
        try {
          // 1. Mark the dose as missed.
          await dose.ref.update({
            status: "missed",
            escalatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // 2. Look up the active emergency contact with SMS opt-in.
          const contacts = await db
              .collection("emergencyContacts")
              .where("patientDocId", "==", d.patientDocId)
              .where("active", "==", true)
              .where("smsOptIn", "==", true)
              .limit(1)
              .get();

          if (contacts.empty) {
            noContact++;
            continue;
          }

          const contact = contacts.docs[0].data();

          // 3. Load the schedule to include medication details.
          const scheduleSnap = await db
              .collection("pillSchedules")
              .doc(d.scheduleId)
              .get();
          const s = scheduleSnap.data() || {};

          const patientSnap = await db
              .collection("patients")
              .doc(d.patientDocId)
              .get();
          const patientName =
              patientSnap.data()?.fullName || "The patient";

          const scheduledTime = d.scheduledAt
              .toDate()
              .toLocaleTimeString("en-IN", {
                timeZone: "Asia/Kolkata",
                hour: "numeric",
                minute: "2-digit",
              });

          // 4. Queue the emergency SMS.
          await db.collection("emergencyNotifications").add({
            type: "missed_dose",
            doseId: dose.id,
            scheduleId: d.scheduleId,
            patientDocId: d.patientDocId,
            patientAuthUid: d.patientAuthUid,
            patientName,
            contactName: contact.name || "",
            contactPhone: contact.phone || "",
            templateVars: {
              var1: patientName,
              var2: `${s.medicationName || "medication"} ${s.dose || ""}`.trim(),
              var3: scheduledTime,
            },
            status: "pending",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // 5. Record the escalation on the dose.
          await dose.ref.update({
            "escalation.notifiedAt":
                admin.firestore.FieldValue.serverTimestamp(),
            "escalation.notifiedVia": "sms",
            "escalation.emergencyContactId": contacts.docs[0].id,
          });

          escalated++;
        } catch (e) {
          console.error(`escalateMissedDoses: dose ${dose.id} failed:`, e);
        }
      }

      console.log(
          `escalateMissedDoses: ${escalated} escalated, ` +
          `${noContact} skipped (no contact)`,
      );
    },
);

// =================================================================
// PILL REMINDERS — emergency SMS sender
//
// Drains `emergencyNotifications` where status='pending' and sends
// each via MSG91. Marks the doc 'sent' or 'failed' based on the
// MSG91 response. Retries on transient errors (up to 3 attempts).
// =================================================================
exports.sendEmergencySms = onSchedule(
    {
      schedule: "every 1 minutes",
      timeZone: "Asia/Kolkata",
      region: REGION,
      secrets: [MSG91_AUTH_KEY, MSG91_EMERGENCY_TEMPLATE_ID],
    },
    async () => {
      const db = admin.firestore();
      const pending = await db
          .collection("emergencyNotifications")
          .where("status", "==", "pending")
          .limit(50)
          .get();

      if (pending.empty) return;

      for (const notif of pending.docs) {
        const n = notif.data();
        const phone = (n.contactPhone || "").replace(/[^\d]/g, "");
        if (phone.length < 10) {
          await notif.ref.update({
            status: "failed",
            error: "Invalid phone number",
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }

        try {
          // MSG91 sendSMS endpoint (transactional template).
          const url = "https://control.msg91.com/api/v5/flow/";
          const body = {
            template_id: MSG91_EMERGENCY_TEMPLATE_ID.value(),
            short_url: "0",
            realTimeResponse: "1",
            recipients: [
              {
                mobiles: `91${phone}`,
                var1: n.templateVars?.var1 ?? "",
                var2: n.templateVars?.var2 ?? "",
                var3: n.templateVars?.var3 ?? "",
              },
            ],
          };

          const resp = await axios.post(url, body, {
            headers: {
              authkey: MSG91_AUTH_KEY.value(),
              "Content-Type": "application/json",
            },
            timeout: 15000,
          });

          if (resp.status >= 200 && resp.status < 300) {
            await notif.ref.update({
              status: "sent",
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
              providerResponse: resp.data,
            });
          } else {
            throw new Error(`MSG91 returned ${resp.status}`);
          }
        } catch (err) {
          const attempts = (n.attempts || 0) + 1;
          console.error(
              `sendEmergencySms: ${notif.id} attempt ${attempts} failed:`,
              err.response?.data || err.message,
          );

          if (attempts >= 3) {
            await notif.ref.update({
              status: "failed",
              attempts,
              error: JSON.stringify(
                  err.response?.data || err.message,
              ).slice(0, 500),
              failedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } else {
            // Back off, keep pending for the next run.
            await notif.ref.update({
              attempts,
              lastError: String(
                  err.response?.data?.message || err.message,
              ).slice(0, 500),
            });
          }
        }
      }
    },
);

// =================================================================
// PILL GUARD — device event handler
//
// Pill Guard (Arduino device) reports dispense events by writing to
// `pillDeviceEvents/{eventId}` via its gateway (BLE→phone→Firestore,
// or WiFi→Cloud Function→Firestore).
//
// This function matches each dispense event to the nearest pending
// dose within ±10 minutes and marks it taken with
// confirmedBy='device'. The app's escalation logic then skips it.
//
// The schema is identical to a manual "taken" confirmation — the app
// UI shows the same record, just with a different confirmedBy tag.
// =================================================================
exports.handlePillDeviceEvent = onDocumentCreated(
    { document: "pillDeviceEvents/{eventId}", region: REGION },
    async (event) => {
      const db = admin.firestore();
      const eventSnap = event.data;
      if (!eventSnap) return;

      const e = eventSnap.data();
      if (e.eventType !== "dispensed") return;

      const patientDocId = e.patientDocId;
      if (!patientDocId) {
        console.warn(`Device event ${event.params.eventId} has no patientDocId`);
        return;
      }

      // ±10 minute window around the event time.
      const occurredAt = e.occurredAt?.toDate() || new Date();
      const low = new Date(occurredAt.getTime() - 10 * 60 * 1000);
      const high = new Date(occurredAt.getTime() + 10 * 60 * 1000);

      const doses = await db
          .collection("pillDoses")
          .where("patientDocId", "==", patientDocId)
          .where("status", "==", "pending")
          .where("scheduledAt", ">=", admin.firestore.Timestamp.fromDate(low))
          .where("scheduledAt", "<=", admin.firestore.Timestamp.fromDate(high))
          .orderBy("scheduledAt")
          .limit(1)
          .get();

      if (doses.empty) {
        console.warn(
            `Pill device event ${event.params.eventId}: no matching dose ` +
            `within ±10 min for patient ${patientDocId}`,
        );
        // Record the orphan event for later inspection.
        await eventSnap.ref.update({
          matchedDoseId: null,
          matchedAt: admin.firestore.FieldValue.serverTimestamp(),
          matchResult: "no_match",
        });
        return;
      }

      const doseRef = doses.docs[0].ref;
      await doseRef.update({
        status: "taken",
        confirmedBy: "device",
        confirmedAt: e.occurredAt || admin.firestore.FieldValue.serverTimestamp(),
        deviceEventId: event.params.eventId,
      });

      await eventSnap.ref.update({
        matchedDoseId: doses.docs[0].id,
        matchedAt: admin.firestore.FieldValue.serverTimestamp(),
        matchResult: "matched",
      });

      console.log(
          `Pill device event ${event.params.eventId} → dose ` +
          `${doses.docs[0].id} marked taken`,
      );
    },
);

// =================================================================
// PILL GUARD — HTTP gateway (for Arduino devices that can't write
// to Firestore directly)
//
// The device POSTs to this endpoint with a shared device key. The
// function verifies the key, then writes the event to
// `pillDeviceEvents/{auto}`. The onDocumentCreated trigger above
// takes over from there.
//
// Until the hardware exists, this function is deployed but never
// called. That's fine — it's dormant.
// =================================================================
const PILL_DEVICE_SHARED_KEY =
    defineSecret("PILL_DEVICE_SHARED_KEY");

exports.pillDeviceGateway = onRequest(
    {
      region: REGION,
      invoker: "public",
      cors: true,
      secrets: [PILL_DEVICE_SHARED_KEY],
    },
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("Method not allowed");
        return;
      }

      // Verify the device's shared key. Simple but sufficient until
      // per-device certificates are introduced.
      const providedKey =
          req.headers["x-device-key"] || req.body?.deviceKey;
      if (providedKey !== PILL_DEVICE_SHARED_KEY.value()) {
        res.status(401).send("Unauthorized");
        return;
      }

      const {
        deviceId,
        patientDocId,
        patientAuthUid,
        eventType,
        occurredAt,
        compartmentId,
      } = req.body || {};

      if (!deviceId || !patientDocId || !eventType) {
        res.status(400).send("Missing required fields");
        return;
      }

      try {
        await admin.firestore().collection("pillDeviceEvents").add({
          deviceId,
          patientDocId,
          patientAuthUid: patientAuthUid || null,
          eventType,
          compartmentId: compartmentId || null,
          occurredAt: occurredAt
              ? admin.firestore.Timestamp.fromDate(new Date(occurredAt))
              : admin.firestore.FieldValue.serverTimestamp(),
          receivedAt: admin.firestore.FieldValue.serverTimestamp(),
          source: "http_gateway",
        });
        res.status(200).json({ success: true });
      } catch (err) {
        console.error("pillDeviceGateway error:", err);
        res.status(500).json({ success: false, error: err.message });
      }
    },
);