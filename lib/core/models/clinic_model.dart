// lib/core/models/clinic_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ClinicModel {
  final String id;

  // Type — "clinic" | "lab"
  final String? type;
  final String? clinicCode;

  final String name;
  final String? displayName;
  final String? tagline;
  final String? address;
  final String? phone;
  final String? secondaryPhone;
  final String? email;
  final String? website;
  final String? whatsappNumber;
  final String? logoUrl;
  final String? brandColor;

  // Registration & compliance
  final String? clinicRegistrationNumber;
  final String? gstNumber;
  final String? panNumber;
  final String? dltEntityId;

  // Financial
  final String currency;
  final num taxPercent;
  final num consultationFee;
  final num followUpFee;
  final num teleconsultFee;
  final bool acceptsInsurance;
  final List<String> paymentMethods;
  final String? upiId;

  // Appointment defaults
  final int slotDurationMinutes;
  final int maxAdvanceBookingDays;
  final int confirmationWindowHours;
  final String tokenPrefix;

  // Communication
  final bool whatsappEnabled;
  final bool emailEnabled;
  final bool pushNotificationsEnabled;

  // Status
  final bool active;
  final String subscriptionPlan;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ClinicModel({
    required this.id,
    this.type,
    this.clinicCode,
    required this.name,
    this.displayName,
    this.tagline,
    this.address,
    this.phone,
    this.secondaryPhone,
    this.email,
    this.website,
    this.whatsappNumber,
    this.logoUrl,
    this.brandColor,
    this.clinicRegistrationNumber,
    this.gstNumber,
    this.panNumber,
    this.dltEntityId,
    this.currency = 'INR',
    this.taxPercent = 18,
    this.consultationFee = 500,
    this.followUpFee = 250,
    this.teleconsultFee = 400,
    this.acceptsInsurance = false,
    this.paymentMethods = const ['cash', 'upi'],
    this.upiId,
    this.slotDurationMinutes = 15,
    this.maxAdvanceBookingDays = 30,
    this.confirmationWindowHours = 24,
    this.tokenPrefix = 'A',
    this.whatsappEnabled = true,
    this.emailEnabled = true,
    this.pushNotificationsEnabled = true,
    this.active = true,
    this.subscriptionPlan = 'starter',
    this.createdAt,
    this.updatedAt,
  });

  bool get isLab => type == 'lab';
  bool get isClinic => type != 'lab'; // default = clinic for backward compat

  factory ClinicModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    List<String> strList(dynamic v) =>
        v == null ? [] : List<String>.from(v);

    String? flatAddress = map['address'];
    if (flatAddress == null && map['practiceAddress'] is Map) {
      final a = Map<String, dynamic>.from(map['practiceAddress']);
      final parts = [
        a['line1'],
        a['line2'],
        a['area'],
        a['city'],
        a['state'],
        a['pincode'],
      ].where((e) => e != null && e.toString().trim().isNotEmpty);
      if (parts.isNotEmpty) flatAddress = parts.join(', ');
    }

    String? flatPhone = map['phone'] ?? map['primaryPhone'];

    return ClinicModel(
      id: id,
      type: map['type']?.toString(),
      clinicCode: map['clinicCode']?.toString(),
      name: map['name'] ?? 'Clinic',
      displayName: map['displayName'],
      tagline: map['tagline'],
      address: flatAddress,
      phone: flatPhone,
      secondaryPhone: map['secondaryPhone'],
      email: map['email'],
      website: map['website'],
      whatsappNumber: map['whatsappNumber'],
      logoUrl: map['logoUrl'],
      brandColor: map['brandColor'],
      clinicRegistrationNumber: map['clinicRegistrationNumber'],
      gstNumber: map['gstNumber'],
      panNumber: map['panNumber'],
      dltEntityId: map['dltEntityId'],
      currency: map['currency'] ?? 'INR',
      taxPercent: map['taxPercent'] ?? 18,
      consultationFee: map['consultationFee'] ?? 500,
      followUpFee: map['followUpFee'] ?? 250,
      teleconsultFee: map['teleconsultFee'] ?? 400,
      acceptsInsurance: map['acceptsInsurance'] ?? false,
      paymentMethods: strList(map['paymentMethods']).isEmpty
          ? const ['cash', 'upi']
          : strList(map['paymentMethods']),
      upiId: map['upiId'],
      slotDurationMinutes: map['slotDurationMinutes'] ?? 15,
      maxAdvanceBookingDays: map['maxAdvanceBookingDays'] ?? 30,
      confirmationWindowHours: map['confirmationWindowHours'] ?? 24,
      tokenPrefix: map['tokenPrefix'] ?? 'A',
      whatsappEnabled: map['whatsappEnabled'] ?? true,
      emailEnabled: map['emailEnabled'] ?? true,
      pushNotificationsEnabled: map['pushNotificationsEnabled'] ?? true,
      active: map['active'] ?? true,
      subscriptionPlan: map['subscriptionPlan'] ?? 'starter',
      createdAt: parse(map['createdAt']),
      updatedAt: parse(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'clinicCode': clinicCode,
        'name': name,
        'displayName': displayName,
        'tagline': tagline,
        'address': address,
        'phone': phone,
        'secondaryPhone': secondaryPhone,
        'email': email,
        'website': website,
        'whatsappNumber': whatsappNumber,
        'logoUrl': logoUrl,
        'brandColor': brandColor,
        'clinicRegistrationNumber': clinicRegistrationNumber,
        'gstNumber': gstNumber,
        'panNumber': panNumber,
        'dltEntityId': dltEntityId,
        'currency': currency,
        'taxPercent': taxPercent,
        'consultationFee': consultationFee,
        'followUpFee': followUpFee,
        'teleconsultFee': teleconsultFee,
        'acceptsInsurance': acceptsInsurance,
        'paymentMethods': paymentMethods,
        'upiId': upiId,
        'slotDurationMinutes': slotDurationMinutes,
        'maxAdvanceBookingDays': maxAdvanceBookingDays,
        'confirmationWindowHours': confirmationWindowHours,
        'tokenPrefix': tokenPrefix,
        'whatsappEnabled': whatsappEnabled,
        'emailEnabled': emailEnabled,
        'pushNotificationsEnabled': pushNotificationsEnabled,
        'active': active,
        'subscriptionPlan': subscriptionPlan,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}