import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient_model.dart';

/// A lab customer match found while searching linked labs before
/// creating a new clinic patient. Returned to the UI so the receptionist
/// can confirm "yes, this is the same person."
class LabCustomerMatch {
  final String labClinicId;
  final String labName;
  final String customerDocId;
  final String displayPatientId; // e.g. LAB-BPL-0939-2026-0001
  final String fullName;
  final String phone;
  final String email;
  final DateTime? createdAt;

  LabCustomerMatch({
    required this.labClinicId,
    required this.labName,
    required this.customerDocId,
    required this.displayPatientId,
    required this.fullName,
    required this.phone,
    required this.email,
    this.createdAt,
  });
}

class PatientService {
  final _db = FirebaseFirestore.instance;

  // =================================================================
  // ID generation
  // =================================================================

  /// Generates a human-readable patient ID using an atomic per-clinic
  /// transaction.
  ///
  /// Format: PT-{SHORT}-{LAST4}-{YEAR}-{NNNN}
  ///   SHORT  — derived from the clinic name (e.g. "Lifeline Family
  ///            Clinic" → "LFC")
  ///   LAST4  — last 4 digits of the clinic's `clinicCode`
  ///   YEAR   — current year
  ///   NNNN   — 4-digit counter, per clinic per year
  ///
  /// Example: PT-LFC-8685-2026-0001
  Future<String> _nextPatientId(String clinicId) async {
    final clinicDoc = await _db.collection('clinics').doc(clinicId).get();
    if (!clinicDoc.exists) {
      throw StateError('Clinic $clinicId not found.');
    }
    final data = clinicDoc.data() ?? {};

    final clinicName = (data['name'] ?? 'Clinic').toString();
    final clinicCode = (data['clinicCode'] ?? '').toString();

    final shortName = _deriveShortName(clinicName);
    final regnSuffix = _last4Digits(clinicCode, fallback: clinicId);

    final year = DateTime.now().year;
    final counterRef = _db
        .collection('counters')
        .doc('patient_${clinicId}_$year');

    return await _db.runTransaction<String>((tx) async {
      final snap = await tx.get(counterRef);
      final current = (snap.data()?['count'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      tx.set(
        counterRef,
        {'count': next, 'year': year, 'clinicId': clinicId},
        SetOptions(merge: true),
      );
      return 'PT-$shortName-$regnSuffix-$year-'
          '${next.toString().padLeft(4, '0')}';
    });
  }

  /// "Lifeline Family Clinic" → "LFC"; "Diagnostics" → "DIA"
  String _deriveShortName(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'ORG';

    final initials = words.map((w) => w[0].toUpperCase()).join();
    if (initials.length >= 2) {
      return initials.length > 4 ? initials.substring(0, 4) : initials;
    }

    final single = words.first.toUpperCase();
    return single.length >= 3 ? single.substring(0, 3) : single.padRight(3, 'X');
  }

  /// Extract last 4 digits from a code/ID. Falls back to `fallback` if
  /// no digits are present.
  String _last4Digits(String code, {required String fallback}) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      final fallbackDigits = fallback.replaceAll(RegExp(r'\D'), '');
      if (fallbackDigits.isEmpty) return '0000';
      return fallbackDigits.length <= 4
          ? fallbackDigits.padLeft(4, '0')
          : fallbackDigits.substring(fallbackDigits.length - 4);
    }
    return digits.length <= 4
        ? digits.padLeft(4, '0')
        : digits.substring(digits.length - 4);
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    return digits;
  }

  // =================================================================
  // Cross-lab lookup (used by the clinic "New Patient" flow)
  // =================================================================

  /// Search `labCustomers` across the labs linked to this clinic,
  /// matching by phone (primary) or email (fallback). Sorted by
  /// createdAt ascending so the earliest record (canonical first
  /// sighting) comes first.
  Future<List<LabCustomerMatch>> findLabCustomersAcrossLinkedLabs({
    required String clinicId,
    String? phone,
    String? email,
    String? name,
  }) async {
    // Prefer explicit args; fall back to detecting from a single `name`
    // that might actually be a phone or email.
    final rawQuery = (name ?? '').trim();
    final phoneInput = phone ?? (isPhoneLike(rawQuery) ? rawQuery : null);
    final emailInput = email ?? (isEmailLike(rawQuery) ? rawQuery : null);
    final nameInput =
        isEmailLike(rawQuery) || isPhoneLike(rawQuery) ? null : rawQuery;

    final phoneDigits = phoneInput == null ? '' : _normalizePhone(phoneInput);
    final normalizedEmail = emailInput?.trim().toLowerCase() ?? '';
    final nameQuery = (nameInput ?? '').trim().toLowerCase();

    if (phoneDigits.isEmpty &&
        normalizedEmail.isEmpty &&
        nameQuery.isEmpty) {
      return const [];
    }

    // Get linked labs.
    final linkedSnap = await _db
        .collection('clinics')
        .doc(clinicId)
        .collection('linkedLabs')
        .where('active', isEqualTo: true)
        .get();
    if (linkedSnap.docs.isEmpty) return const [];

    final labIds = <String, String>{};
    for (final d in linkedSnap.docs) {
      final id = (d.data()['labClinicId'] ?? '').toString();
      final nm = (d.data()['labName'] ?? 'Lab').toString();
      if (id.isNotEmpty) labIds[id] = nm;
    }
    if (labIds.isEmpty) return const [];

    final results = <LabCustomerMatch>[];
    final seenDocIds = <String>{};

    // ── 1. Phone search ──
    if (phoneDigits.isNotEmpty) {
      for (final entry in labIds.entries) {
        final snap = await _db
            .collection('labCustomers')
            .where('labClinicId', isEqualTo: entry.key)
            .where('phone', isEqualTo: phoneDigits)
            .limit(10)
            .get();
        for (final d in snap.docs) {
          if (seenDocIds.add(d.id)) {
            results.add(_matchFrom(entry.key, entry.value, d));
          }
        }
      }
    }

    // ── 2. Email search ──
    if (normalizedEmail.isNotEmpty) {
      for (final entry in labIds.entries) {
        final snap = await _db
            .collection('labCustomers')
            .where('labClinicId', isEqualTo: entry.key)
            .where('email', isEqualTo: normalizedEmail)
            .limit(10)
            .get();
        for (final d in snap.docs) {
          if (seenDocIds.add(d.id)) {
            results.add(_matchFrom(entry.key, entry.value, d));
          }
        }
      }
    }

    // ── 3. Name search — client-side contains over a page ──
    if (nameQuery.isNotEmpty) {
      for (final entry in labIds.entries) {
        final snap = await _db
            .collection('labCustomers')
            .where('labClinicId', isEqualTo: entry.key)
            .limit(300)
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          final fullName =
              (data['fullName'] ?? '').toString().toLowerCase();
          final pid =
              (data['displayPatientId'] ?? '').toString().toLowerCase();
          if (!fullName.contains(nameQuery) &&
              !pid.contains(nameQuery)) {
            continue;
          }
          if (seenDocIds.add(d.id)) {
            results.add(_matchFrom(entry.key, entry.value, d));
          }
        }
      }
    }

    // Sort earliest-first (canonical first sighting).
    results.sort((a, b) {
      final at = a.createdAt ?? DateTime(2000);
      final bt = b.createdAt ?? DateTime(2000);
      return at.compareTo(bt);
    });
    return results;
  }

  LabCustomerMatch _matchFrom(
    String labClinicId,
    String labName,
    DocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data() ?? {};
    return LabCustomerMatch(
      labClinicId: labClinicId,
      labName: labName,
      customerDocId: d.id,
      displayPatientId: (data['displayPatientId'] ?? '').toString(),
      fullName: (data['fullName'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// "someone@x.com" → true
  bool isEmailLike(String s) => s.contains('@');

  /// "  +91 98-xxx-xxxx  " → true (≥6 digits, only phone-safe chars)
  bool isPhoneLike(String s) {
    if (s.isEmpty) return false;
    final stripped = s.replaceAll(RegExp(r'[\s\+\-\(\)]'), '');
    if (!RegExp(r'^\d+$').hasMatch(stripped)) return false;
    return stripped.length >= 6;
  }

  // =================================================================
  // Patient create / update
  // =================================================================

  /// Add patient.
  ///
  /// If `patient.patientId` is already set (i.e., the receptionist
  /// adopted an existing LAB- ID from a linked lab), that ID is used
  /// as-is. Otherwise a fresh PT- ID is generated.
  ///
  /// If `patient.linkedLabCustomerDocId` is set, the corresponding
  /// `labCustomers` doc is updated with the reverse link
  /// (`linkedPatientDocId`, `linkedPatientId`, `source` upgrade) so the
  /// lab knows this customer is now a clinic patient.
  Future<PatientModel> addPatient(PatientModel patient) async {
    final clinicId = patient.clinicId;
    if (clinicId == null || clinicId.isEmpty) {
      throw StateError('Cannot create patient without a clinic context.');
    }

    // Respect an adopted ID; only generate when empty.
    final patientId = patient.patientId.trim().isNotEmpty
        ? patient.patientId.trim()
        : await _nextPatientId(clinicId);

    final docRef = _db.collection('patients').doc();

    final withId = PatientModel(
      docId: docRef.id,
      patientId: patientId,
      fullName: patient.fullName,
      phone: patient.phone,
      email: patient.email,
      gender: patient.gender,
      dob: patient.dob,
      bloodGroup: patient.bloodGroup,
      maritalStatus: patient.maritalStatus,
      occupation: patient.occupation,
      address: patient.address,
      city: patient.city,
      pincode: patient.pincode,
      emergencyContactName: patient.emergencyContactName,
      emergencyContactPhone: patient.emergencyContactPhone,
      referredBy: patient.referredBy,
      allergies: patient.allergies,
      chronicConditions: patient.chronicConditions,
      currentMedicationNotes: patient.currentMedicationNotes,
      currentMedications: patient.currentMedications,
      pastMedicalHistory: patient.pastMedicalHistory,
      pastSurgeries: patient.pastSurgeries,
      pastTreatments: patient.pastTreatments,
      smoking: patient.smoking,
      alcohol: patient.alcohol,
      diet: patient.diet,
      activityLevel: patient.activityLevel,
      doctorNotes: patient.doctorNotes,
      clinicId: clinicId,
      primaryDoctorId: patient.primaryDoctorId,
      primaryDoctorName: patient.primaryDoctorName,
      createdByUserId: patient.createdByUserId,
      active: patient.active,
      linkedLabCustomerDocId: patient.linkedLabCustomerDocId,
      linkedLabClinicId: patient.linkedLabClinicId,
      linkedLabCustomerDocIds: patient.linkedLabCustomerDocIds,
    );

    await docRef.set(withId.toMap());

    // Update the linked labCustomer with the reverse pointer, so the
    // lab sees that this walk-in customer is now a clinic patient.
    final linkedCustomerDocId = patient.linkedLabCustomerDocId;
    if (linkedCustomerDocId != null && linkedCustomerDocId.isNotEmpty) {
      try {
        final customerRef =
            _db.collection('labCustomers').doc(linkedCustomerDocId);
        final customerSnap = await customerRef.get();
        if (customerSnap.exists) {
          final currentSource =
              (customerSnap.data()?['source'] ?? '').toString();
          await customerRef.update({
            'linkedPatientDocId': docRef.id,
            'linkedPatientId': patientId,
            'linkedAt': FieldValue.serverTimestamp(),
            // Upgrade source to clinic_linked only if it was 'direct'.
            // If it was already clinic_linked, keep as-is.
            'source': currentSource == 'direct' ? 'clinic_linked' : currentSource,
            if (patient.clinicId != null) 'sourceClinicId': patient.clinicId,
            'sourcePatientDocId': docRef.id,
            'sourcePatientId': patientId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {
        // Non-fatal — patient is created; the lab-side link can be
        // repaired later if needed.
      }
    }

    // Also update the user doc if a matching user exists — so the
    // patient dashboard switches from lab-only to clinic-patient tabs.
    try {
      final userByPhone = await _db
          .collection('users')
          .where('phone', isEqualTo: _normalizePhone(patient.phone))
          .limit(1)
          .get();
      if (userByPhone.docs.isNotEmpty) {
        await userByPhone.docs.first.reference.update({
          'linkedPatientDocId': docRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // Non-fatal.
    }

    return withId;
  }

  Future<void> updatePatient(PatientModel patient) async {
    await _db
        .collection('patients')
        .doc(patient.docId)
        .update(patient.toMap());
  }

  Future<PatientModel?> getPatientByDocId(String docId) async {
    final doc = await _db.collection('patients').doc(docId).get();
    if (!doc.exists) return null;
    return PatientModel.fromMap(doc.id, doc.data()!);
  }

  Future<PatientModel?> getPatientByPatientId(String patientId) async {
    final snap = await _db
        .collection('patients')
        .where('patientId', isEqualTo: patientId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return PatientModel.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  // =================================================================
  // Search
  // =================================================================

  /// Search within a clinic — by patientId, phone, email, or
  /// name prefix. Name matching is case-insensitive (uses the
  /// denormalized `nameLower` field).
  Future<List<PatientModel>> search(
    String query, {
    required String clinicId,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // Exact match on patientId (PT- or LAB- prefixed).
    final upper = q.toUpperCase();
    if (upper.startsWith('PT-') || upper.startsWith('LAB-')) {
      final snap = await _db
          .collection('patients')
          .where('clinicId', isEqualTo: clinicId)
          .where('patientId', isEqualTo: upper)
          .limit(10)
          .get();
      return snap.docs
          .map((d) => PatientModel.fromMap(d.id, d.data()))
          .toList();
    }

    // Phone search — exact match on normalized digits.
    final phoneDigits = _normalizePhone(q);
    if (phoneDigits.length >= 6 && phoneDigits == q.replaceAll(' ', '')) {
      final snap = await _db
          .collection('patients')
          .where('clinicId', isEqualTo: clinicId)
          .where('phone', isEqualTo: phoneDigits)
          .limit(10)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs
            .map((d) => PatientModel.fromMap(d.id, d.data()))
            .toList();
      }
    }

    // Email search.
    if (q.contains('@')) {
      final email = q.toLowerCase();
      final snap = await _db
          .collection('patients')
          .where('clinicId', isEqualTo: clinicId)
          .where('email', isEqualTo: email)
          .limit(10)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs
            .map((d) => PatientModel.fromMap(d.id, d.data()))
            .toList();
      }
    }

    // Prefix search on full name — case-insensitive via `nameLower`.
    final lower = q.toLowerCase();
    var snap = await _db
        .collection('patients')
        .where('clinicId', isEqualTo: clinicId)
        .orderBy('nameLower')
        .startAt([lower])
        .endAt(['$lower\uf8ff'])
        .limit(20)
        .get();

    // Fallback for patients created before `nameLower` was added.
    // Remove this block once the one-off backfill has been run.
    if (snap.docs.isEmpty) {
      snap = await _db
          .collection('patients')
          .where('clinicId', isEqualTo: clinicId)
          .orderBy('fullName')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(20)
          .get();
    }

    return snap.docs
        .map((d) => PatientModel.fromMap(d.id, d.data()))
        .toList();
  }

  /// Live list of patients for a specific clinic.
  Stream<List<PatientModel>> watchPatients({
    required String clinicId,
    int limit = 100,
  }) {
    return _db
        .collection('patients')
        .where('clinicId', isEqualTo: clinicId)
        .where('active', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => PatientModel.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<List<Map<String, dynamic>>> searchInClinic({
    required String clinicId,
    required String query,
  }) {
    final q = query.trim();
    if (q.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('patients')
        .where('clinicId', isEqualTo: clinicId)
        .where('fullName', isGreaterThanOrEqualTo: q)
        .where('fullName', isLessThan: '$q\uf8ff')
        .limit(20)
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{'docId': d.id, ...d.data()})
            .toList());
  }
}