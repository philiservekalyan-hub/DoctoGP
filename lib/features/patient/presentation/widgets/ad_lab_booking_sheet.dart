// lib/features/patient/presentation/widgets/ad_lab_booking_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/booking_reference.dart';

class AdLabBookingSheet extends StatefulWidget {
  final String adId;
  final String labClinicId;

  /// Human-readable clinic code (e.g. "SBL-001"). When present, the sheet
  /// resolves it to a fresh clinic doc ID before writing the order. This
  /// keeps the ad portable across environments where doc IDs differ but
  /// clinic codes stay the same.
  final String? labClinicCode;

  final String labName;
  final String? labPhone;
  final String? labAddress;
  final String? headline;
  final String? body;
  final Map<String, dynamic> patient;

  const AdLabBookingSheet({
    super.key,
    required this.adId,
    required this.labClinicId,
    this.labClinicCode,
    required this.labName,
    required this.patient,
    this.labPhone,
    this.labAddress,
    this.headline,
    this.body,
  });

  @override
  State<AdLabBookingSheet> createState() => _AdLabBookingSheetState();
}

class _AdLabBookingSheetState extends State<AdLabBookingSheet> {
  bool _submitting = false;
  bool _sent = false;
  String? _error;
  String? _bookingRef;

  /// The resolved clinic doc ID to write into the order. Populated lazily
  /// from the code on first read, or set to [widget.labClinicId] as a
  /// fallback. Cached so we only look up once per sheet open.
  String? _resolvedClinicId;
  Future<String>? _resolveFuture;

  @override
  void initState() {
    super.initState();
    _resolveFuture = _resolveLabClinicId();
  }

  /// Resolve [AdLabBookingSheet.labClinicCode] → `clinics/{docId}`.
  /// Falls back to [AdLabBookingSheet.labClinicId] when the code is null,
  /// empty, or doesn't match any clinic.
  Future<String> _resolveLabClinicId() async {
    final code = widget.labClinicCode?.trim();
    if (code != null && code.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('clinics')
            .where('clinicCode', isEqualTo: code)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) return snap.docs.first.id;
        debugPrint(
            '[BOOKING] no clinic with code "$code" — falling back to labClinicId');
      } catch (e) {
        debugPrint('[BOOKING] clinic code lookup failed: $e');
      }
    }
    return widget.labClinicId;
  }

  double? _extractPrice(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(
      r'(?:₹|Rs\.?|INR)\s*(\d{2,6}(?:\.\d{1,2})?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
  }

  Future<void> _sendBooking() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final patientDocId = widget.patient['patientDocId'] as String?;
      if (patientDocId == null || patientDocId.isEmpty) {
        setState(() {
          _error =
              'No patient profile linked. Please complete your profile.';
          _submitting = false;
        });
        return;
      }

      // Resolve the clinic ID fresh (or use the cached result if already
      // resolved by a prior build).
      _resolvedClinicId ??= await _resolveFuture!;
      final clinicId = _resolvedClinicId!;

      final now = FieldValue.serverTimestamp();
      final price = _extractPrice(widget.headline);

      final orderRef =
          FirebaseFirestore.instance.collection('labOrders').doc();
      final bookingRef = bookingRefFromDocId(orderRef.id);

      await orderRef.set({
        'labClinicId': clinicId,
        'labClinicCode': widget.labClinicCode,
        'labName': widget.labName,
        'patientDocId': patientDocId,
        'patientId': widget.patient['patientId'],
        'patientName': widget.patient['fullName'] ?? 'Patient',
        'patientPhone': widget.patient['phone'] ?? '',
        'patientAuthUid': widget.patient['authUid'],
        'tests': [
          {
            'name': widget.headline ?? 'Lab test',
            if (price != null) 'unitPrice': price,
          }
        ],
        'instructions': widget.body,
        'status': 'ordered',
        'released': false,
        'orderedAt': now,
        'createdAt': now,
        'updatedAt': now,
        'source': 'ad_booking',
        'sourceAdId': widget.adId,
        'attributionAt': now,
        'bookingRef': bookingRef,
      });

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _sent = true;
        _bookingRef = bookingRef;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not send booking: $e';
      });
    }
  }

  Future<void> _callLab() async {
    final phone = widget.labPhone?.trim() ?? '';
    if (phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: _sent ? _buildConfirmation() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    final money = NumberFormat.currency(
        locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final price = _extractPrice(widget.headline);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text('Book at ${widget.labName}',
                style: AppTextStyles.h3),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded),
          ),
        ]),
        Text(
          'Send a booking request. The lab will call you to confirm '
          'your sample collection time.',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 18),
        _infoCard(
          icon: Icons.science_rounded,
          iconColor: AppColors.info,
          label: 'Test',
          title: widget.headline ?? 'Lab test',
          subtitle: widget.body,
          trailing: price != null ? money.format(price) : null,
        ),
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.local_hospital_rounded,
          iconColor: AppColors.patientAccent,
          label: 'Lab',
          title: widget.labName,
          subtitle: widget.labAddress,
          phone: widget.labPhone,
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_error!,
                style: const TextStyle(color: AppColors.error)),
          ),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _submitting ? null : _sendBooking,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send booking request'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Payment is collected by the lab at sample collection.',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmation() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: AppColors.success, size: 34),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text('Booking request sent',
              style: AppTextStyles.h2, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 6),
        Text(
          'The lab has received your booking. Please call them to '
          'confirm your sample collection time.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 18),
        if (_bookingRef != null)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withOpacity(.3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'BOOKING ID',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _bookingRef!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Show or mention this ID when you call the lab.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.science_rounded,
          iconColor: AppColors.info,
          label: 'Test',
          title: widget.headline ?? 'Lab test',
          subtitle: widget.body,
        ),
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.local_hospital_rounded,
          iconColor: AppColors.patientAccent,
          label: 'Lab',
          title: widget.labName,
          subtitle: widget.labAddress,
          phone: widget.labPhone,
        ),
        const SizedBox(height: 18),
        if ((widget.labPhone ?? '').isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _callLab,
              icon: const Icon(Icons.call_rounded, size: 18),
              label: Text('Call ${widget.labName}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String title,
    String? subtitle,
    String? phone,
    String? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted)),
            const Spacer(),
            if (trailing != null)
              Text(trailing, style: AppTextStyles.h3),
          ]),
          const SizedBox(height: 6),
          Text(title, style: AppTextStyles.h3),
          if ((subtitle ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: AppTextStyles.bodyMuted),
          ],
          if ((phone ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.phone_rounded,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(phone!, style: AppTextStyles.body),
            ]),
          ],
        ],
      ),
    );
  }
}