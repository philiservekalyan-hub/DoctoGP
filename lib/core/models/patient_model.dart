import 'package:cloud_firestore/cloud_firestore.dart';

class PatientModel {
  final String docId;
  final String patientId;
  final String fullName;
  final String phone;
  final String? email;
  final String gender;
  final DateTime? dob;
  final String? bloodGroup;
  final String? maritalStatus;
  final String? occupation;
  final String? address;
  final String? city;
  final String? pincode;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? referredBy;

  final List<String> allergies;
  final List<String> chronicConditions;
  final String? currentMedicationNotes;
  final List<Map<String, dynamic>> currentMedications;

  final List<Map<String, dynamic>> pastMedicalHistory;
  final List<Map<String, dynamic>> pastSurgeries;
  final List<Map<String, dynamic>> pastTreatments;

  final String? smoking;
  final String? alcohol;
  final String? diet;
  final String? activityLevel;

  final String? doctorNotes;

  // Clinic scoping
  final String? clinicId;
  final String? primaryDoctorId;
  final String? primaryDoctorName;
  final String? createdByUserId;
  final bool active;

  // Lab linkage — set when this patient record adopts an existing
  // labCustomers record (scenario 3). Null for pure clinic-originated
  // patients.
  final String? linkedLabCustomerDocId;
  final String? linkedLabClinicId;
  final List<String> linkedLabCustomerDocIds;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  PatientModel({
    required this.docId,
    required this.patientId,
    required this.fullName,
    required this.phone,
    this.email,
    required this.gender,
    this.dob,
    this.bloodGroup,
    this.maritalStatus,
    this.occupation,
    this.address,
    this.city,
    this.pincode,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.referredBy,
    this.allergies = const [],
    this.chronicConditions = const [],
    this.currentMedicationNotes,
    this.currentMedications = const [],
    this.pastMedicalHistory = const [],
    this.pastSurgeries = const [],
    this.pastTreatments = const [],
    this.smoking,
    this.alcohol,
    this.diet,
    this.activityLevel,
    this.doctorNotes,
    this.clinicId,
    this.primaryDoctorId,
    this.primaryDoctorName,
    this.createdByUserId,
    this.active = true,
    this.linkedLabCustomerDocId,
    this.linkedLabClinicId,
    this.linkedLabCustomerDocIds = const [],
    this.createdAt,
    this.updatedAt,
  });

  bool get isLabAdopted => linkedLabCustomerDocId != null;

  /// Lowercased full name — used for case-insensitive prefix search.
  String get fullNameLower => fullName.trim().toLowerCase();

  Map<String, dynamic> toMap() => {
        'patientId': patientId,
        'fullName': fullName,
        'nameLower': fullNameLower,
        'phone': phone,
        'email': email,
        'gender': gender,
        'dob': dob?.toIso8601String(),
        'bloodGroup': bloodGroup,
        'maritalStatus': maritalStatus,
        'occupation': occupation,
        'address': address,
        'city': city,
        'pincode': pincode,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'referredBy': referredBy,
        'allergies': allergies,
        'chronicConditions': chronicConditions,
        'currentMedicationNotes': currentMedicationNotes,
        'currentMedications': currentMedications,
        'pastMedicalHistory': pastMedicalHistory,
        'pastSurgeries': pastSurgeries,
        'pastTreatments': pastTreatments,
        'smoking': smoking,
        'alcohol': alcohol,
        'diet': diet,
        'activityLevel': activityLevel,
        'doctorNotes': doctorNotes,
        'clinicId': clinicId,
        'primaryDoctorId': primaryDoctorId,
        'primaryDoctorName': primaryDoctorName,
        'createdByUserId': createdByUserId,
        'active': active,
        'linkedLabCustomerDocId': linkedLabCustomerDocId,
        'linkedLabClinicId': linkedLabClinicId,
        'linkedLabCustomerDocIds': linkedLabCustomerDocIds,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory PatientModel.fromMap(String docId, Map<String, dynamic> map) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    List<String> strList(dynamic v) =>
        v == null ? [] : List<String>.from(v);

    List<Map<String, dynamic>> mapList(dynamic v) => v == null
        ? []
        : List<Map<String, dynamic>>.from(
            (v as List).map((e) => Map<String, dynamic>.from(e)));

    return PatientModel(
      docId: docId,
      patientId: map['patientId'] ?? '',
      fullName: map['fullName'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'],
      gender: map['gender'] ?? 'male',
      dob: parse(map['dob']),
      bloodGroup: map['bloodGroup'],
      maritalStatus: map['maritalStatus'],
      occupation: map['occupation'],
      address: map['address'],
      city: map['city'],
      pincode: map['pincode'],
      emergencyContactName: map['emergencyContactName'],
      emergencyContactPhone: map['emergencyContactPhone'],
      referredBy: map['referredBy'],
      allergies: strList(map['allergies']),
      chronicConditions: strList(map['chronicConditions']),
      currentMedicationNotes: map['currentMedicationNotes'],
      currentMedications: mapList(map['currentMedications']),
      pastMedicalHistory: mapList(map['pastMedicalHistory']),
      pastSurgeries: mapList(map['pastSurgeries']),
      pastTreatments: mapList(map['pastTreatments']),
      smoking: map['smoking'],
      alcohol: map['alcohol'],
      diet: map['diet'],
      activityLevel: map['activityLevel'],
      doctorNotes: map['doctorNotes'],
      clinicId: map['clinicId'],
      primaryDoctorId: map['primaryDoctorId'],
      primaryDoctorName: map['primaryDoctorName'],
      createdByUserId: map['createdByUserId'],
      active: _parseBool(map['active'], defaultVal: true),
      linkedLabCustomerDocId: map['linkedLabCustomerDocId']?.toString(),
      linkedLabClinicId: map['linkedLabClinicId']?.toString(),
      linkedLabCustomerDocIds: ((map['linkedLabCustomerDocIds'] as List?) ??
              const [])
          .map((e) => e.toString())
          .toList(),
      createdAt: parse(map['createdAt']),
      updatedAt: parse(map['updatedAt']),
    );
  }

  static bool _parseBool(dynamic v, {bool defaultVal = false}) {
    if (v == null) return defaultVal;
    if (v is bool) return v;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    if (v is num) return v != 0;
    return defaultVal;
  }
}