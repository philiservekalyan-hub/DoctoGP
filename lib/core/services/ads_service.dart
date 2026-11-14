// lib/core/services/ads_service.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ad_model.dart';

class AdsService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  static const _collection = 'ads';
  static const _payments = 'adPayments';
  static const _storageFolder = 'ads';

  /// All ads (newest first), optionally filtered by status.
  Stream<List<AdModel>> watchAllAds({String? status}) {
    Query q = _db.collection(_collection).orderBy('createdAt', descending: true);
    if (status != null) q = q.where('status', isEqualTo: status);
    return q.snapshots().map((s) => s.docs
        .map((d) => AdModel.fromMap(d.id, d.data() as Map<String, dynamic>))
        .toList());
  }

  /// Ads that are approved, plan-active, and in schedule window.
  Stream<List<AdModel>> watchLiveAds() {
    final now = Timestamp.now();
    return _db
        .collection(_collection)
        .where('status', isEqualTo: 'approved')
        .where('planStatus', isEqualTo: 'active')
        .where('planExpiresAt', isGreaterThan: now)
        .where('startAt', isLessThanOrEqualTo: now)
        .where('endAt', isGreaterThanOrEqualTo: now)
        .orderBy('priority', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AdModel.fromMap(d.id, d.data() as Map<String, dynamic>))
            .toList());
  }

  // -----------------------------------------------------------------
  // CREATIVE UPLOAD
  //
  // Files are compressed to WebP (fallback JPEG) and capped at 1200 px
  // on the long edge before upload. Cache-Control is set so Firebase
  // Storage's front end can serve subsequent loads from edge caches.
  //
  // The stored filename is always `creative.webp` — even the JPEG
  // fallback keeps this name so the storage path is stable per ad.
  // The content-type header is authoritative; the extension is not.
  //
  // Existing ads that were uploaded before this change still reference
  // their old `creative.png` URLs, which continue to work unchanged.
  // -----------------------------------------------------------------
  Future<String> uploadPng({
    required String adId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final encoded = await _encodeForWeb(
      bytes,
      maxDimension: 1200,
      quality: 82,
    );

    final ref = _storage.ref('$_storageFolder/$adId/creative.webp');

    final task = await ref.putData(
      encoded.bytes,
      SettableMetadata(
        contentType: encoded.contentType,
        // One year, immutable. A re-upload changes the download token
        // (via getDownloadURL), so invalidating cached copies is
        // handled by token rotation, not by Cache-Control.
        cacheControl: 'public, max-age=31536000, immutable',
        customMetadata: {
          'adId': adId,
          'uploadedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
          'uploadedAt': DateTime.now().toUtc().toIso8601String(),
          'originalFilename': filename,
        },
      ),
    );

    return task.ref.getDownloadURL();
  }

  /// Compresses [bytes] to WebP (or JPEG if the platform codec fails),
  /// downscaling so the long edge is at most [maxDimension].
  Future<_EncodedImage> _encodeForWeb(
    Uint8List bytes, {
    required int maxDimension,
    required int quality,
  }) async {
    // Try WebP first.
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: CompressFormat.webp,
      );
      if (result.isNotEmpty) {
        return _EncodedImage(bytes: result, contentType: 'image/webp');
      }
    } catch (e) {
      debugPrint('[ADS] WebP encode failed, falling back to JPEG: $e');
    }

    // Fallback to JPEG.
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result.isNotEmpty) {
        return _EncodedImage(bytes: result, contentType: 'image/jpeg');
      }
    } catch (e) {
      debugPrint('[ADS] JPEG encode failed, using raw bytes: $e');
    }

    // Last resort — upload the raw bytes so the user gets a working ad
    // even if compression fails on the platform. The image will be
    // larger, but nothing is broken.
    return _EncodedImage(bytes: bytes, contentType: 'image/png');
  }

  Future<String> createAd(AdModel ad) async {
    final ref = _db.collection(_collection).doc();
    await ref.set({
      ...ad.copyWith(status: AdStatus.draft).toMap(),
      'adId': ref.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateAd(AdModel ad) async {
    await _db.collection(_collection).doc(ad.adId).update({
      ...ad.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> submitForReview(String adId) async {
    await _db.collection(_collection).doc(adId).update({
      'status': AdStatus.pendingReview.wire,
      'rejectionReason': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> approve(String adId, String approverId) async {
    await _db.collection(_collection).doc(adId).update({
      'status': AdStatus.approved.wire,
      'approvedById': approverId,
      'approvedAt': FieldValue.serverTimestamp(),
      'rejectionReason': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reject(String adId, String approverId, String reason) async {
    await _db.collection(_collection).doc(adId).update({
      'status': AdStatus.rejected.wire,
      'approvedById': approverId,
      'rejectionReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> pause(String adId) async {
    await _db.collection(_collection).doc(adId).update({
      'status': AdStatus.paused.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archive(String adId) async {
    await _db.collection(_collection).doc(adId).update({
      'status': AdStatus.archived.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAd(String adId, String imageUrl) async {
    try {
      await _storage.refFromURL(imageUrl).delete();
    } catch (_) {}
    await _db.collection(_collection).doc(adId).delete();
  }

  // -----------------------------------------------------------------
  // PLAN PAYMENT (the only billing entry point)
  // -----------------------------------------------------------------
  /// Records a plan payment: creates an `adPayments` doc and updates
  /// the ad's plan fields. Call this whenever the admin confirms a
  /// payment (bank transfer, UPI, Razorpay, or cash).
  ///
  /// Returns the new planExpiresAt timestamp.
  Future<DateTime> recordPlanPayment({
    required String adId,
    required String labClinicId,
    required AdPlan plan,
    required String paymentMethod,   // 'upi' | 'razorpay' | 'bank_transfer' | 'cash'
    required String paymentRef,      // UTR / Razorpay ID / receipt no.
    required String recordedByUid,
    DateTime? paidAt,
  }) async {
    final now = paidAt ?? DateTime.now();
    final expiresAt = DateTime(now.year, now.month + 1, now.day);

    // Base amount + GST @ 18%
    final baseAmount = plan.amountInr;
    final gstAmount = (baseAmount * 0.18).round();
    final totalAmount = baseAmount + gstAmount;

    // Create payment record
    await _db.collection(_payments).add({
      'adId': adId,
      'labClinicId': labClinicId,
      'plan': plan.wire,
      'amount': baseAmount,
      'gstAmount': gstAmount,
      'totalAmount': totalAmount,
      'currency': 'INR',
      'paymentMethod': paymentMethod,
      'paymentRef': paymentRef,
      'status': 'paid',
      'paidAt': Timestamp.fromDate(now),
      'validFrom': Timestamp.fromDate(now),
      'validUntil': Timestamp.fromDate(expiresAt),
      'recordedByUid': recordedByUid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update ad plan fields
    await _db.collection(_collection).doc(adId).update({
      'plan': plan.wire,
      'planAmount': baseAmount,
      'planStatus': AdPlanStatus.active.wire,
      'planExpiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return expiresAt;
  }

  /// Marks a plan as pending payment (used before the admin has
  /// confirmed receipt of funds).
  Future<void> setPlanPendingPayment({
    required String adId,
    required AdPlan plan,
  }) async {
    await _db.collection(_collection).doc(adId).update({
      'plan': plan.wire,
      'planAmount': plan.amountInr,
      'planStatus': AdPlanStatus.pendingPayment.wire,
      'planExpiresAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Payments history for an ad (newest first).
  Future<List<Map<String, dynamic>>> planPaymentsFor(String adId) async {
    final snap = await _db
        .collection(_payments)
        .where('adId', isEqualTo: adId)
        .orderBy('paidAt', descending: true)
        .get();
    return snap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .toList();
  }

  // -----------------------------------------------------------------
  // EVENTS (impressions / clicks)
  // -----------------------------------------------------------------
  Future<void> logEvent({
    required String adId,
    required String type,
    String? patientId,
    String? sessionId,
    Map<String, dynamic>? metadata,
  }) async {
    await _db.collection('ad_events').add({
      'adId': adId,
      'type': type,
      'patientId': patientId,
      'sessionId': sessionId,
      'metadata': metadata,
      'occurredAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, int>> adStats(String adId) async {
    final events = await _db
        .collection('ad_events')
        .where('adId', isEqualTo: adId)
        .get();
    final counts = <String, int>{'impression': 0, 'click': 0, 'dismiss': 0};
    for (final d in events.docs) {
      final t = (d.data()['type'] ?? '').toString();
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts;
  }

  /// Convenience: current signed-in admin uid.
  static String get currentAdminUid =>
      FirebaseAuth.instance.currentUser?.uid ?? 'admin';
}

/// Internal wrapper returned by [_encodeForWeb].
class _EncodedImage {
  final Uint8List bytes;
  final String contentType;
  const _EncodedImage({required this.bytes, required this.contentType});
}

final adsServiceProvider = Provider<AdsService>((ref) => AdsService());

final allAdsProvider =
    StreamProvider.autoDispose.family<List<AdModel>, String?>((ref, status) {
  return ref.read(adsServiceProvider).watchAllAds(status: status);
});

final liveAdsProvider = StreamProvider.autoDispose<List<AdModel>>((ref) {
  return ref.read(adsServiceProvider).watchLiveAds();
});