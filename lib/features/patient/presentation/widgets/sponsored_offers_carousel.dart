// lib/features/patient/presentation/widgets/sponsored_offers_carousel.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/models/ad_model.dart';
import 'ad_lab_booking_sheet.dart';

// -----------------------------------------------------------------
// Patient-facing wrapper
// -----------------------------------------------------------------
class SponsoredAd {
  final String adId;
  final String advertiserName;
  final String imageUrl;
  final String altText;
  final String? headline;
  final String? body;
  final String sponsorLabel;
  final AdPlan plan;
  final String ctaLabel;
  final String? targetLabClinicId;
  final String? targetLabClinicCode;
  final String? targetLabPackageId;
  final List<String> targetLabTestOfferingIds;
  final int priority;
  final List<String> hideOnFlows;
  final String? labPhone;
  final String? labAddress;

  const SponsoredAd({
    required this.adId,
    required this.advertiserName,
    required this.imageUrl,
    required this.altText,
    this.headline,
    this.body,
    this.sponsorLabel = 'Sponsored',
    required this.plan,
    this.ctaLabel = 'Book Now',
    this.targetLabClinicId,
    this.targetLabClinicCode,
    this.targetLabPackageId,
    this.targetLabTestOfferingIds = const [],
    this.priority = 0,
    this.hideOnFlows = const [],
    this.labPhone,
    this.labAddress,
  });

  factory SponsoredAd.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return SponsoredAd(
      adId: d.id,
      labPhone: m['labPhone'] as String?,
      labAddress: m['labAddress'] as String?,
      advertiserName: (m['advertiserName'] ?? '').toString(),
      imageUrl: (m['imageUrl'] ?? '').toString(),
      altText: (m['altText'] ?? '').toString(),
      headline: m['headline'] as String?,
      body: m['body'] as String?,
      sponsorLabel: (m['sponsorLabel'] ?? 'Sponsored').toString(),
      plan: AdPlan.fromString(m['plan'] as String?),
      ctaLabel: ((m['ctaLabel'] ?? '').toString().trim().isEmpty)
          ? 'Book Now'
          : m['ctaLabel'].toString(),
      targetLabClinicId: m['targetLabClinicId'] as String?,
      targetLabClinicCode: m['targetLabClinicCode'] as String?,
      targetLabPackageId: m['targetLabPackageId'] as String?,
      targetLabTestOfferingIds:
          (m['targetLabTestOfferingIds'] as List?)?.cast<String>() ?? const [],
      priority: (m['priority'] ?? 0) as int,
      hideOnFlows: (m['hideOnFlows'] as List?)?.cast<String>() ?? const [],
    );
  }

  AdCtaType get ctaType => plan.ctaType;
  bool get hasCta => ctaType != AdCtaType.none;
}

// -----------------------------------------------------------------
// Provider
// -----------------------------------------------------------------
final _liveAdsProvider =
    StreamProvider.autoDispose<List<SponsoredAd>>((ref) {
  final now = Timestamp.now();
  return FirebaseFirestore.instance
      .collection('ads')
      .where('status', isEqualTo: 'approved')
      .where('planStatus', isEqualTo: 'active')
      .where('planExpiresAt', isGreaterThan: now)
      .where('startAt', isLessThanOrEqualTo: now)
      .where('endAt', isGreaterThanOrEqualTo: now)
      .orderBy('priority', descending: true)
      .snapshots()
      .map((s) => s.docs.map(SponsoredAd.fromDoc).toList());
});

// -----------------------------------------------------------------
// Widget
// -----------------------------------------------------------------
class SponsoredOffersCarousel extends ConsumerStatefulWidget {
  final String flow;
  final String? patientUid;
  final Map<String, dynamic>? patient;

  /// How long each ad is shown before auto-advancing to the next one.
  /// Set to [Duration.zero] to disable auto-advance.
  final Duration autoAdvanceInterval;

  const SponsoredOffersCarousel({
    super.key,
    this.flow = 'dashboard',
    this.patientUid,
    this.patient,
    this.autoAdvanceInterval = const Duration(seconds: 10),
  });

  @override
  ConsumerState<SponsoredOffersCarousel> createState() =>
      _SponsoredOffersCarouselState();
}

class _SponsoredOffersCarouselState
    extends ConsumerState<SponsoredOffersCarousel> {
  int _idx = 0;
  bool _dismissed = false;
  final Set<String> _impressed = {};
  final String _sessionId =
      DateTime.now().microsecondsSinceEpoch.toString();

  /// Timer that advances `_idx` every [SponsoredOffersCarousel.autoAdvanceInterval].
  /// Created only when there are 2+ ads to rotate through.
  Timer? _autoAdvanceTimer;

  /// Snapshot of the currently displayed ads, used by the timer callback
  /// to compute the next index without re-reading the provider.
  List<SponsoredAd> _currentAds = const [];

  /// Timestamp of the most recent manual navigation (chevron or dot tap).
  /// Used to skip a single auto-advance tick if it would fire within
  /// [_manualCooldown] of the manual action.
  DateTime _lastManualInteraction = DateTime.fromMillisecondsSinceEpoch(0);

  static const _manualCooldown = Duration(seconds: 3);

  static const _blockedFlows = {
    'abnormal_results',
    'critical_results',
    'medication_reminder',
    'emergency',
    'appointment_prep',
  };

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  /// Ensure the auto-advance timer matches the current ad count.
  /// Starts it when there is something to rotate, cancels it otherwise.
  void _syncAutoAdvance(int adCount) {
    final shouldRun = !_dismissed &&
        widget.autoAdvanceInterval > Duration.zero &&
        adCount > 1;

    if (!shouldRun) {
      _autoAdvanceTimer?.cancel();
      _autoAdvanceTimer = null;
      return;
    }

    if (_autoAdvanceTimer?.isActive ?? false) return;

    _autoAdvanceTimer = Timer.periodic(widget.autoAdvanceInterval, (_) {
      if (!mounted) return;

      // Give the user a moment after any manual tap.
      if (DateTime.now().difference(_lastManualInteraction) <
          _manualCooldown) {
        return;
      }

      final total = _currentAds.length;
      if (total <= 1) return;

      setState(() => _idx = (_idx + 1) % total);

      final newAd = _currentAds[_idx];
      if (_impressed.add(newAd.adId)) {
        _logEvent(newAd.adId, 'impression');
      }
    });
  }

  void _onManualNav(int newIdx) {
    _lastManualInteraction = DateTime.now();
    setState(() => _idx = newIdx);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) {
      _syncAutoAdvance(0);
      return const SizedBox.shrink();
    }
    if (_blockedFlows.contains(widget.flow)) {
      _syncAutoAdvance(0);
      return const SizedBox.shrink();
    }

    final adsAsync = ref.watch(_liveAdsProvider);

    // Using `when` instead of `maybeWhen` makes query errors visible in the
    // console — useful for spotting missing indexes or permission-denied.
    return adsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) {
        debugPrint('[ADS] stream error: $e');
        _syncAutoAdvance(0);
        return const SizedBox.shrink();
      },
      data: (all) {
        final ads = all
            .where((a) => !a.hideOnFlows.contains(widget.flow))
            .toList();

        _currentAds = ads;

        if (ads.isEmpty) {
          _syncAutoAdvance(0);
          return const SizedBox.shrink();
        }
        if (_idx >= ads.length) _idx = 0;

        _syncAutoAdvance(ads.length);

        final ad = ads[_idx];
        if (_impressed.add(ad.adId)) {
          _logEvent(ad.adId, 'impression');
        }

        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: _buildCard(ad, ads.length),
        );
      },
    );
  }

  Widget _buildCard(SponsoredAd ad, int total) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder, width: 1),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(ad),
          const SizedBox(height: 10),
          _buildBody(ad),
          if (total > 1) ...[
            const SizedBox(height: 10),
            _buildPagination(total),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(SponsoredAd ad) => Row(children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(.13),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            ad.sponsorLabel.toUpperCase(),
            style: const TextStyle(
              color: AppColors.info,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ad.advertiserName,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            _logEvent(ad.adId, 'dismiss');
            _syncAutoAdvance(0);
            setState(() => _dismissed = true);
          },
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close_rounded,
                size: 18, color: AppColors.textMuted),
          ),
        ),
      ]);

  Widget _buildBody(SponsoredAd ad) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ad.imageUrl.isNotEmpty) _buildImageBlock(ad),
        if ((ad.headline ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            ad.headline!,
            style: AppTextStyles.h3,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if ((ad.body ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            ad.body!,
            style: AppTextStyles.caption,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (ad.hasCta) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _handleClick(ad),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(
                ad.ctaLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImageBlock(SponsoredAd ad) {
    const double minH = 130;
    const double maxH = 260;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        const placeholderHeight = (minH + maxH) / 2;

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: minH,
              maxHeight: maxH,
              minWidth: cardWidth,
              maxWidth: cardWidth,
            ),
            child: Image.network(
              ad.imageUrl,
              width: cardWidth,
              height: placeholderHeight,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => Container(
                height: placeholderHeight,
                color: AppColors.cardBorder,
                child: const Center(
                  child: Icon(
                    Icons.image_not_supported_rounded,
                    color: AppColors.textMuted,
                    size: 28,
                  ),
                ),
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: placeholderHeight,
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder.withOpacity(.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPagination(int total) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _onManualNav((_idx - 1 + total) % total),
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            color: AppColors.textMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          for (int i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => _onManualNav(i),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _idx
                        ? AppColors.primary
                        : AppColors.textMuted.withOpacity(.35),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _onManualNav((_idx + 1) % total),
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            color: AppColors.textMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      );

  Future<void> _handleClick(SponsoredAd ad) async {
    _logEvent(ad.adId, 'click');
    if (!ad.hasCta) return;

    switch (ad.ctaType) {
      case AdCtaType.externalUrl:
        return;

      case AdCtaType.internalBooking:
        final labId = ad.targetLabClinicId;
        if (labId == null || labId.isEmpty) return;

        final patient = widget.patient;
        if (patient == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please complete your profile first'),
            ),
          );
          return;
        }

        if (!mounted) return;
        final booked = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => AdLabBookingSheet(
            adId: ad.adId,
            labClinicId: labId,
            labClinicCode: ad.targetLabClinicCode,
            labName: ad.advertiserName,
            labPhone: ad.labPhone,
            labAddress: ad.labAddress,
            headline: ad.headline,
            body: ad.body,
            patient: patient,
          ),
        );

        if (booked == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your booking request has been sent to the lab'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        return;

      case AdCtaType.none:
        return;
    }
  }

  void _logEvent(String adId, String type) {
    FirebaseFirestore.instance.collection('ad_events').add({
      'adId': adId,
      'type': type,
      'patientId': widget.patientUid,
      'sessionId': _sessionId,
      'flow': widget.flow,
      'occurredAt': FieldValue.serverTimestamp(),
    }).ignore();
  }
}