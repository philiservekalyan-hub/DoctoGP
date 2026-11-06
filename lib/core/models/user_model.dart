// lib/core/models/user_model.dart
enum UserRole {
  patient,
  owner,
  receptionist,
  doctor,
  nurse,
  lab,
  admin,
  unknown,
}

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final String? clinicId;
  final String? photoUrl;
  final bool active;
  final String? clinicCode;
  final String? clinicName;
  final String? deptId;

  /// 'clinic' | 'lab' | null
  ///
  /// Distinguishes a clinic receptionist from a lab receptionist.
  /// Only meaningful for `role == UserRole.receptionist` (and
  /// optionally for `UserRole.owner` if you ever split that too).
  /// Populated at signup / staff-invite time; may be null for
  /// legacy accounts until backfilled.
  final String? orgType;

  // ── NEW ── capability flags
  //
  // These let an owner also practise as a doctor, or a doctor also
  // manage the clinic. They don't affect which shell the user lands
  // on — that's still determined by `role`. They only gate what
  // cross-links the shells show and what writes the user is allowed
  // to make.
  final bool isDoctor;
  final bool isLabOwner;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.clinicId,
    this.photoUrl,
    this.active = true,
    this.clinicCode,
    this.clinicName,
    this.deptId,
    this.orgType,
    this.isDoctor = false,
    this.isLabOwner = false,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: _parseRole(map['role']),
      clinicId: map['clinicId'],
      photoUrl: map['photoUrl'],
      active: map['active'] ?? true,
      clinicCode: map['clinicCode'],
      clinicName: map['clinicName'],
      deptId: map['deptId'],
      orgType: map['orgType'] as String?,
      isDoctor: map['isDoctor'] == true,
      isLabOwner: map['isLabOwner'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role.name,
        'clinicId': clinicId,
        'photoUrl': photoUrl,
        'active': active,
        'clinicCode': clinicCode,
        'clinicName': clinicName,
        'deptId': deptId,
        'orgType': orgType,
        'isDoctor': isDoctor,
        'isLabOwner': isLabOwner,
      };

  static UserRole _parseRole(String? role) {
    switch (role?.trim().toLowerCase()) {
      case 'patient':
        return UserRole.patient;
      case 'owner':
        return UserRole.owner;
      case 'receptionist':
        return UserRole.receptionist;
      case 'doctor':
        return UserRole.doctor;
      case 'nurse':
        return UserRole.nurse;
      case 'lab':
        return UserRole.lab;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.unknown;
    }
  }

  /// True if the user can open the doctor/clinical shell — either
  /// because their primary role is doctor, or because they own the
  /// clinic and have the `isDoctor` flag set.
  bool get canPractise {
    if (role == UserRole.doctor) return true;
    if (role == UserRole.owner && isDoctor) return true;
    if (role == UserRole.admin) return true;
    return false;
  }

  /// True if the user can open the owner/management shell — either
  /// because their primary role is owner, or because they're an
  /// admin, or because they're a doctor with owner rights (rare,
  /// mostly for solo-practice GPs).
  bool get canManageClinic {
    if (role == UserRole.owner) return true;
    if (role == UserRole.admin) return true;
    return false;
  }

  /// True if the user can access lab-reception workflows.
  bool get canManageLabReception {
    return role == UserRole.receptionist && orgType == 'lab';
  }

  String get roleLabel {
    switch (role) {
      case UserRole.patient:
        return 'Patient';
      case UserRole.receptionist:
        return orgType == 'lab' ? 'Lab Receptionist' : 'Receptionist';
      case UserRole.doctor:
        return 'Doctor';
      case UserRole.lab:
        return 'Lab Technician';
      case UserRole.admin:
        return 'Admin';
      case UserRole.owner:
        return orgType == 'lab' ? 'Lab Owner' : 'Clinic Owner';
      case UserRole.nurse:
        return 'Nurse';
      default:
        return 'Unknown';
    }
  }
}