// lib/core/models/ad_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum AdStatus {
  draft,
  pendingReview,
  approved,
  rejected,
  paused,
  archived;

  static AdStatus fromString(String? s) {
    switch (s) {
      case 'pending_review':
        return AdStatus.pendingReview;
      case 'approved':
        return AdStatus.approved;
      case 'rejected':
        return AdStatus.rejected;
      case 'paused':
        return AdStatus.paused;
      case 'archived':
        return AdStatus.archived;
      default:
        return AdStatus.draft;
    }
  }

  String get wire => switch (this) {
        AdStatus.pendingReview => 'pending_review',
        _ => name,
      };

  String get label => switch (this) {
        AdStatus.draft => 'Draft',
        AdStatus.pendingReview => 'Pending review',
        AdStatus.approved => 'Approved',
        AdStatus.rejected => 'Rejected',
        AdStatus.paused => 'Paused',
        AdStatus.archived => 'Archived',
      };
}

/// How the ad's action button behaves — derived from `plan`.
enum AdCtaType {
  none,
  externalUrl,
  internalBooking;

  static AdCtaType fromString(String? s) {
    switch (s) {
      case 'external_url':
        return AdCtaType.externalUrl;
      case 'internal_booking':
        return AdCtaType.internalBooking;
      default:
        return AdCtaType.none;
    }
  }

  String get wire => switch (this) {
        AdCtaType.externalUrl => 'external_url',
        AdCtaType.internalBooking => 'internal_booking',
        AdCtaType.none => 'none',
      };
}

/// Two billing tiers.
///
///   advertise_only     — ₹500/month · no button, subscription only
///   advertise_and_book — ₹2,000/month · "Book Now" button, unlimited
///                        in-app bookings, no per-order commission
enum AdPlan {
  advertiseOnly,
  advertiseAndBook;

  static AdPlan fromString(String? s) {
    switch (s) {
      case 'advertise_and_book':
        return AdPlan.advertiseAndBook;
      default:
        return AdPlan.advertiseOnly;
    }
  }

  String get wire => switch (this) {
        AdPlan.advertiseAndBook => 'advertise_and_book',
        AdPlan.advertiseOnly => 'advertise_only',
      };

  int get amountInr => switch (this) {
        AdPlan.advertiseOnly => 500,
        AdPlan.advertiseAndBook => 2000,
      };

  String get label => switch (this) {
        AdPlan.advertiseOnly => 'Advertise only',
        AdPlan.advertiseAndBook => 'Advertise + Bookings',
      };

  /// What kind of button this plan enables.
  AdCtaType get ctaType => switch (this) {
        AdPlan.advertiseOnly => AdCtaType.none,
        AdPlan.advertiseAndBook => AdCtaType.internalBooking,
      };
}

enum AdPlanStatus {
  active,
  expired,
  pendingPayment;

  static AdPlanStatus fromString(String? s) {
    switch (s) {
      case 'expired':
        return AdPlanStatus.expired;
      case 'pending_payment':
        return AdPlanStatus.pendingPayment;
      default:
        return AdPlanStatus.active;
    }
  }

  String get wire => switch (this) {
        AdPlanStatus.active => 'active',
        AdPlanStatus.expired => 'expired',
        AdPlanStatus.pendingPayment => 'pending_payment',
      };

  String get label => switch (this) {
        AdPlanStatus.active => 'Active',
        AdPlanStatus.expired => 'Expired',
        AdPlanStatus.pendingPayment => 'Pending payment',
      };
}

class AdModel {
  final String adId;
  final String name;
  final String advertiserName;
  final String advertiserId;
  final String? labPhone;
  final String? labAddress;

  // ── Plan / billing ──
  final AdPlan plan;
  final AdPlanStatus planStatus;
  final int planAmount;
  final DateTime? planExpiresAt;

  // ── Creative ──
  final String imageUrl;
  final int imageWidth;
  final int imageHeight;
  final String altText;
  final String? headline;
  final String? body;
  final String sponsorLabel;

  // ── Booking target ──
  /// The Firestore doc ID of the target lab clinic.
  /// Kept for legacy ads and for internal lookups — new ads should also
  /// populate [targetLabClinicCode] so admins never have to see this.
  final String? targetLabClinicId;

  /// Human-readable clinic code (e.g. `SBL-001`). This is what the admin
  /// types when creating an ad. When present, the booking sheet resolves
  /// it to the current `clinics/{docId}` for the environment.
  final String? targetLabClinicCode;

  final String? targetLabPackageId;
  final List<String> targetLabTestOfferingIds;

  // ── External CTA (only used if plan.ctaType == externalUrl; not used by current plans) ──
  final String ctaUrl;
  final String ctaLabel;

  // ── Schedule ──
  final DateTime? startAt;
  final DateTime? endAt;

  // ── Workflow ──
  final AdStatus status;
  final String? rejectionReason;
  final String createdById;
  final String? approvedById;
  final DateTime? approvedAt;

  // ── Serving ──
  final int priority;
  final int weight;
  final int? frequencyCapPerDay;
  final int? frequencyCapPerSession;
  final List<String> hideOnFlows;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdModel({
    required this.adId,
    required this.name,
    required this.advertiserName,
    required this.advertiserId,
    this.plan = AdPlan.advertiseOnly,
    this.planStatus = AdPlanStatus.pendingPayment,
    this.planAmount = 500,
    this.planExpiresAt,
    required this.imageUrl,
    required this.imageWidth,
    required this.imageHeight,
    required this.altText,
    this.headline,
    this.body,
    this.sponsorLabel = 'Sponsored',
    this.targetLabClinicId,
    this.targetLabClinicCode,
    this.targetLabPackageId,
    this.targetLabTestOfferingIds = const [],
    this.ctaUrl = '',
    this.ctaLabel = 'Book Now',
    this.startAt,
    this.endAt,
    this.status = AdStatus.draft,
    this.rejectionReason,
    this.createdById = '',
    this.approvedById,
    this.approvedAt,
    this.priority = 0,
    this.weight = 100,
    this.frequencyCapPerDay,
    this.frequencyCapPerSession,
    this.hideOnFlows = const [],
    this.createdAt,
    this.updatedAt,
    this.labPhone,
    this.labAddress,
  });

  factory AdModel.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(dynamic v) =>
        v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

    return AdModel(
      adId: id,
      name: (m['name'] ?? '').toString(),
      labPhone: m['labPhone'] as String?,
      labAddress: m['labAddress'] as String?,
      advertiserName: (m['advertiserName'] ?? '').toString(),
      advertiserId: (m['advertiserId'] ?? '').toString(),
      plan: AdPlan.fromString(m['plan'] as String?),
      planStatus: AdPlanStatus.fromString(m['planStatus'] as String?),
      planAmount: (m['planAmount'] as num?)?.toInt() ?? 500,
      planExpiresAt: ts(m['planExpiresAt']),
      imageUrl: (m['imageUrl'] ?? '').toString(),
      imageWidth: (m['imageWidth'] ?? 0) as int,
      imageHeight: (m['imageHeight'] ?? 0) as int,
      altText: (m['altText'] ?? '').toString(),
      headline: m['headline'] as String?,
      body: m['body'] as String?,
      sponsorLabel: (m['sponsorLabel'] ?? 'Sponsored').toString(),
      targetLabClinicId: m['targetLabClinicId'] as String?,
      targetLabClinicCode: m['targetLabClinicCode'] as String?,
      targetLabPackageId: m['targetLabPackageId'] as String?,
      targetLabTestOfferingIds:
          (m['targetLabTestOfferingIds'] as List?)?.cast<String>() ?? const [],
      ctaUrl: (m['ctaUrl'] ?? '').toString(),
      ctaLabel: ((m['ctaLabel'] ?? '').toString().trim().isEmpty)
          ? 'Book Now'
          : m['ctaLabel'].toString(),
      startAt: ts(m['startAt']),
      endAt: ts(m['endAt']),
      status: AdStatus.fromString(m['status'] as String?),
      rejectionReason: m['rejectionReason'] as String?,
      createdById: (m['createdById'] ?? '').toString(),
      approvedById: m['approvedById'] as String?,
      approvedAt: ts(m['approvedAt']),
      priority: (m['priority'] ?? 0) as int,
      weight: (m['weight'] ?? 100) as int,
      frequencyCapPerDay: m['frequencyCapPerDay'] as int?,
      frequencyCapPerSession: m['frequencyCapPerSession'] as int?,
      hideOnFlows: (m['hideOnFlows'] as List?)?.cast<String>() ?? const [],
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'labPhone': labPhone,
        'labAddress': labAddress,
        'advertiserName': advertiserName,
        'advertiserId': advertiserId,
        'plan': plan.wire,
        'planStatus': planStatus.wire,
        'planAmount': planAmount,
        'planExpiresAt': planExpiresAt,
        'imageUrl': imageUrl,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'altText': altText,
        'headline': headline,
        'body': body,
        'sponsorLabel': sponsorLabel,
        // Derived — kept for backward compat with patient reads
        'ctaType': plan.ctaType.wire,
        'targetLabClinicId': targetLabClinicId,
        'targetLabClinicCode': targetLabClinicCode,
        'targetLabPackageId': targetLabPackageId,
        'targetLabTestOfferingIds': targetLabTestOfferingIds,
        'ctaUrl': ctaUrl,
        'ctaLabel': ctaLabel,
        'startAt': startAt,
        'endAt': endAt,
        'status': status.wire,
        'rejectionReason': rejectionReason,
        'createdById': createdById,
        'approvedById': approvedById,
        'approvedAt': approvedAt,
        'priority': priority,
        'weight': weight,
        'frequencyCapPerDay': frequencyCapPerDay,
        'frequencyCapPerSession': frequencyCapPerSession,
        'hideOnFlows': hideOnFlows,
      };

  AdModel copyWith({
    String? name,
    String? advertiserName,
    String? advertiserId,
    AdPlan? plan,
    AdPlanStatus? planStatus,
    int? planAmount,
    DateTime? planExpiresAt,
    String? imageUrl,
    int? imageWidth,
    int? imageHeight,
    String? altText,
    String? headline,
    String? body,
    String? sponsorLabel,
    String? targetLabClinicId,
    String? targetLabClinicCode,
    String? targetLabPackageId,
    List<String>? targetLabTestOfferingIds,
    String? ctaUrl,
    String? ctaLabel,
    DateTime? startAt,
    DateTime? endAt,
    AdStatus? status,
    String? rejectionReason,
    String? approvedById,
    DateTime? approvedAt,
    int? priority,
    int? weight,
    int? frequencyCapPerDay,
    int? frequencyCapPerSession,
    List<String>? hideOnFlows,
    String? labPhone,
    String? labAddress,
  }) =>
      AdModel(
        adId: adId,
        name: name ?? this.name,
        labPhone: labPhone ?? this.labPhone,
        labAddress: labAddress ?? this.labAddress,
        advertiserName: advertiserName ?? this.advertiserName,
        advertiserId: advertiserId ?? this.advertiserId,
        plan: plan ?? this.plan,
        planStatus: planStatus ?? this.planStatus,
        planAmount: planAmount ?? this.planAmount,
        planExpiresAt: planExpiresAt ?? this.planExpiresAt,
        imageUrl: imageUrl ?? this.imageUrl,
        imageWidth: imageWidth ?? this.imageWidth,
        imageHeight: imageHeight ?? this.imageHeight,
        altText: altText ?? this.altText,
        headline: headline ?? this.headline,
        body: body ?? this.body,
        sponsorLabel: sponsorLabel ?? this.sponsorLabel,
        targetLabClinicId: targetLabClinicId ?? this.targetLabClinicId,
        targetLabClinicCode:
            targetLabClinicCode ?? this.targetLabClinicCode,
        targetLabPackageId: targetLabPackageId ?? this.targetLabPackageId,
        targetLabTestOfferingIds:
            targetLabTestOfferingIds ?? this.targetLabTestOfferingIds,
        ctaUrl: ctaUrl ?? this.ctaUrl,
        ctaLabel: ctaLabel ?? this.ctaLabel,
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        status: status ?? this.status,
        rejectionReason: rejectionReason ?? this.rejectionReason,
        createdById: createdById,
        approvedById: approvedById ?? this.approvedById,
        approvedAt: approvedAt ?? this.approvedAt,
        priority: priority ?? this.priority,
        weight: weight ?? this.weight,
        frequencyCapPerDay: frequencyCapPerDay ?? this.frequencyCapPerDay,
        frequencyCapPerSession:
            frequencyCapPerSession ?? this.frequencyCapPerSession,
        hideOnFlows: hideOnFlows ?? this.hideOnFlows,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Derived — what kind of button the patient sees.
  AdCtaType get ctaType => plan.ctaType;

  bool get hasCta => ctaType != AdCtaType.none;

  bool get isServing {
    final now = DateTime.now();
    return status == AdStatus.approved &&
        planStatus == AdPlanStatus.active &&
        planExpiresAt != null &&
        planExpiresAt!.isAfter(now) &&
        startAt != null &&
        endAt != null &&
        now.isAfter(startAt!) &&
        now.isBefore(endAt!);
  }

  /// Whole days until plan expiry (negative if already expired).
  int? get daysUntilPlanExpiry {
    if (planExpiresAt == null) return null;
    return planExpiresAt!.difference(DateTime.now()).inDays;
  }
}