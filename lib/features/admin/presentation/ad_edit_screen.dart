// lib/features/admin/presentation/ad_edit_screen.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/ad_model.dart';
import '../../../core/services/ads_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import 'widgets/ad_status_chip.dart';

class AdEditScreen extends ConsumerStatefulWidget {
  final AdModel? existing;
  const AdEditScreen({super.key, this.existing});

  @override
  ConsumerState<AdEditScreen> createState() => _AdEditScreenState();
}

class _AdEditScreenState extends ConsumerState<AdEditScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Content ──
  late final TextEditingController _name;
  late final TextEditingController _advertiser;
  late final TextEditingController _altText;
  late final TextEditingController _headline;
  late final TextEditingController _body;

  // ── Lab / booking ──
  /// Human-readable clinic code (e.g. "SBL-001") — the only lab
  /// identifier the admin sees or edits.
  late final TextEditingController _targetLabClinicCode;

  late final TextEditingController _targetLabPackageId;
  late final TextEditingController _ctaLabel;
  late final TextEditingController _labPhone;
  late final TextEditingController _labAddress;

  // ── Serving ──
  late final TextEditingController _priority;
  late final TextEditingController _weight;

  // ── Payment ──
  late final TextEditingController _paymentRef;

  // ── State ──
  AdPlan _plan = AdPlan.advertiseOnly;
  bool _paymentReceived = false;
  String _paymentMethod = 'upi';

  DateTime? _startAt;
  DateTime? _endAt;

  String _imageUrl = '';
  int _imageWidth = 0;
  int _imageHeight = 0;
  Uint8List? _pendingBytes;
  bool _uploading = false;
  bool _saving = false;
  bool _resolvingCode = false;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;

    _name = TextEditingController(text: a?.name ?? '');
    _advertiser = TextEditingController(text: a?.advertiserName ?? '');
    _altText = TextEditingController(text: a?.altText ?? '');
    _headline = TextEditingController(text: a?.headline ?? '');
    _body = TextEditingController(text: a?.body ?? '');

    _targetLabClinicCode =
        TextEditingController(text: a?.targetLabClinicCode ?? '');

    _targetLabPackageId =
        TextEditingController(text: a?.targetLabPackageId ?? '');
    _ctaLabel = TextEditingController(text: a?.ctaLabel ?? 'Book Now');
    _labPhone = TextEditingController(text: a?.labPhone ?? '');
    _labAddress = TextEditingController(text: a?.labAddress ?? '');

    _priority = TextEditingController(text: (a?.priority ?? 0).toString());
    _weight = TextEditingController(text: (a?.weight ?? 100).toString());
    _paymentRef = TextEditingController();

    _imageUrl = a?.imageUrl ?? '';
    _imageWidth = a?.imageWidth ?? 0;
    _imageHeight = a?.imageHeight ?? 0;
    _startAt = a?.startAt;
    _endAt = a?.endAt;

    if (a != null) {
      _plan = a.plan;
      _paymentReceived = a.planStatus == AdPlanStatus.active;
    } else {
      _paymentReceived = true;
      _startAt = DateTime.now();
      _endAt = DateTime.now().add(const Duration(days: 7));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name, _advertiser, _altText, _headline, _body,
      _targetLabClinicCode, _targetLabPackageId, _ctaLabel,
      _labPhone, _labAddress, _priority, _weight, _paymentRef,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────
  // Clinic code → doc ID resolution
  // ────────────────────────────────────────────────────────────────

  Future<String?> _resolveClinicCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('clinics')
          .where('clinicCode', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.id;
    } catch (e) {
      debugPrint('[AD_EDIT] clinic code lookup failed: $e');
      return null;
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final decoded = await decodeImageFromList(bytes);
    if (!mounted) return;
    setState(() {
      _pendingBytes = bytes;
      _imageWidth = decoded.width;
      _imageHeight = decoded.height;
    });
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (d == null) return null;
    if (!mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? DateTime.now()),
    );
    if (t == null) return d;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save({required AdStatus status}) async {
    if (!_formKey.currentState!.validate()) return;

    if (_pendingBytes == null && _imageUrl.isEmpty) {
      _snack('Please upload a PNG first');
      return;
    }
    if (_startAt == null || _endAt == null) {
      _snack('Please set a start and end date');
      return;
    }
    if (!_endAt!.isAfter(_startAt!)) {
      _snack('End date must be after start date');
      return;
    }

    final codeInput = _targetLabClinicCode.text.trim();
    if (codeInput.isEmpty) {
      _snack('Lab clinic code is required');
      return;
    }

    if (_plan == AdPlan.advertiseAndBook &&
        _labPhone.text.trim().isEmpty) {
      _snack('Lab phone is required for the booking plan');
      return;
    }
    if (_paymentReceived && _paymentRef.text.trim().isEmpty) {
      _snack('Payment reference is required');
      return;
    }

    setState(() {
      _saving = true;
      _resolvingCode = true;
    });

    final resolvedId = await _resolveClinicCode(codeInput);
    if (!mounted) return;
    setState(() => _resolvingCode = false);
    if (resolvedId == null) {
      setState(() => _saving = false);
      _snack(
          'No clinic found with code "$codeInput". Check the code and try again.');
      return;
    }

    final service = ref.read(adsServiceProvider);

    try {
      String adId = widget.existing?.adId ?? '';

      if (adId.isEmpty) {
        adId = await service.createAd(AdModel(
          adId: '',
          name: _name.text.trim(),
          advertiserName: _advertiser.text.trim(),
          advertiserId: _advertiser.text
              .trim()
              .toLowerCase()
              .replaceAll(' ', '-'),
          imageUrl: '',
          imageWidth: 0,
          imageHeight: 0,
          altText: _altText.text.trim(),
        ));
      }

      if (_pendingBytes != null) {
        setState(() => _uploading = true);
        _imageUrl = await service.uploadPng(
          adId: adId,
          bytes: _pendingBytes!,
          filename: 'creative.png',
        );
        setState(() => _uploading = false);
      }

      final ad = AdModel(
        adId: adId,
        name: _name.text.trim(),
        advertiserName: _advertiser.text.trim(),
        advertiserId: _advertiser.text
            .trim()
            .toLowerCase()
            .replaceAll(' ', '-'),
        plan: _plan,
        planAmount: _plan.amountInr,
        planStatus: widget.existing?.planStatus ??
            (_paymentReceived
                ? AdPlanStatus.active
                : AdPlanStatus.pendingPayment),
        planExpiresAt: widget.existing?.planExpiresAt ??
            (_paymentReceived
                ? DateTime.now().add(const Duration(days: 30))
                : null),
        imageUrl: _imageUrl,
        imageWidth: _imageWidth,
        imageHeight: _imageHeight,
        altText: _altText.text.trim(),
        headline:
            _headline.text.trim().isEmpty ? null : _headline.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        ctaLabel: _ctaLabel.text.trim().isEmpty
            ? 'Book Now'
            : _ctaLabel.text.trim(),
        targetLabClinicId: resolvedId,
        targetLabClinicCode: codeInput,
        targetLabPackageId: _targetLabPackageId.text.trim().isEmpty
            ? null
            : _targetLabPackageId.text.trim(),
        labPhone: _plan == AdPlan.advertiseAndBook
            ? _labPhone.text.trim()
            : null,
        labAddress: _plan == AdPlan.advertiseAndBook &&
                _labAddress.text.trim().isNotEmpty
            ? _labAddress.text.trim()
            : null,
        startAt: _startAt,
        endAt: _endAt,
        status: status,
        priority: int.tryParse(_priority.text) ?? 0,
        weight: int.tryParse(_weight.text) ?? 100,
        createdById: widget.existing?.createdById ??
            (FirebaseAuth.instance.currentUser?.uid ?? ''),
      );

      await service.updateAd(ad);

      if (status == AdStatus.pendingReview) {
        await service.submitForReview(adId);
      }

      if (_paymentReceived) {
        await service.recordPlanPayment(
          adId: adId,
          labClinicId: resolvedId,
          plan: _plan,
          paymentMethod: _paymentMethod,
          paymentRef: _paymentRef.text.trim(),
          recordedByUid:
              FirebaseAuth.instance.currentUser?.uid ?? 'admin',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final ad = widget.existing;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar:
          ClinicAppBar(title: editing ? 'Edit ad' : 'New sponsored ad'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (ad != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AdStatusChip(status: ad.status),
                      _planStatusChip(ad),
                      if (ad.rejectionReason != null)
                        Text('Reason: ${ad.rejectionReason}',
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12)),
                    ],
                  ),
                ),

              // ── Plan ──
              _section('Plan'),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      RadioListTile<AdPlan>(
                        value: AdPlan.advertiseOnly,
                        groupValue: _plan,
                        onChanged: (v) => setState(() => _plan = v!),
                        title: const Text(
                            'Advertise only — ₹500/month'),
                        subtitle: const Text(
                            'Image, headline, body. No button.'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<AdPlan>(
                        value: AdPlan.advertiseAndBook,
                        groupValue: _plan,
                        onChanged: (v) => setState(() => _plan = v!),
                        title: const Text(
                            'Advertise + Bookings — ₹2,000/month'),
                        subtitle: const Text(
                            'Adds a "Book Now" button. Unlimited bookings.'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Lab ──
              const SizedBox(height: 16),
              _section('Lab'),
              _field(
                'Lab clinic code',
                _targetLabClinicCode,
                required: true,
                hint: 'e.g. SBL-001',
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Lab clinic code is required';
                  if (s.length > 40) return 'Code looks too long';
                  return null;
                },
              ),
              if (_plan == AdPlan.advertiseAndBook) ...[
                _field(
                  'Lab phone (patient will call this to confirm)',
                  _labPhone,
                  required: true,
                  keyboard: TextInputType.phone,
                  hint: 'e.g. +91 98765 43210',
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Lab phone is required';
                    final digits =
                        s.replaceAll(RegExp(r'[^\d]'), '');
                    if (digits.length < 8) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
                _field(
                  'Lab address (optional)',
                  _labAddress,
                  maxLength: 200,
                  minLines: 2,
                  hint: 'e.g. 12 MG Road, Bengaluru 560001',
                ),
                _field(
                  'Package ID (optional)',
                  _targetLabPackageId,
                  hint: 'e.g. pkg-full-body-1499',
                ),
                _field(
                  'Button label',
                  _ctaLabel,
                  maxLength: 40,
                  hint: 'e.g. Book Now',
                ),
              ],

              // ── Creative ──
              const SizedBox(height: 16),
              _section('Creative'),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _imagePreview(),
                      const SizedBox(height: 10),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: _uploading ? null : _pickImage,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: Text(
                              _uploading ? 'Uploading…' : 'Upload PNG'),
                        ),
                        const SizedBox(width: 8),
                        if (_imageWidth > 0)
                          Text('${_imageWidth}×$_imageHeight',
                              style: AppTextStyles.caption),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        'Recommended: 1200×400 (3:1) or 800×400 (2:1). '
                        'Square images ≥600×600 also work.',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Content ──
              const SizedBox(height: 16),
              _section('Content'),
              _field(
                'Internal name',
                _name,
                required: true,
                hint: 'e.g. Sai Baba Labs — Full Body Checkup',
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Internal name is required';
                  if (s.length > 60) return 'Keep it under 60 characters';
                  return null;
                },
              ),
              _field(
                'Advertiser name',
                _advertiser,
                required: true,
                hint: 'e.g. Sai Baba Labs',
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Advertiser name is required';
                  if (s.length > 40) return 'Keep it under 40 characters';
                  return null;
                },
              ),
              _field(
                'Alt text (for accessibility)',
                _altText,
                required: true,
                maxLength: 200,
                minLines: 2,
                hint:
                    'e.g. Sai Baba Labs full body checkup — 60+ parameters for ₹1,499',
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Alt text is required';
                  if (s.length < 10) {
                    return 'Describe the image in at least 10 characters';
                  }
                  return null;
                },
              ),
              _field(
                'Headline',
                _headline,
                maxLength: 80,
                hint: 'e.g. Full Body Check-up @ Rs. 1499/-',
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isNotEmpty && s.length > 80) {
                    return 'Headline must be 80 characters or fewer';
                  }
                  return null;
                },
              ),
              _field(
                'Body',
                _body,
                maxLength: 160,
                minLines: 2,
                hint:
                    'e.g. 60+ Parameter !! Includes CBC, Lipid, LFT, KFT & Thyroid',
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isNotEmpty && s.length > 160) {
                    return 'Body must be 160 characters or fewer';
                  }
                  return null;
                },
              ),

              // ── Schedule ──
              const SizedBox(height: 16),
              _section('Schedule'),
              Row(children: [
                Expanded(
                  child: _dateTile('Starts', _startAt, () async {
                    final picked = await _pickDateTime(_startAt);
                    if (picked != null && mounted) {
                      setState(() => _startAt = picked);
                    }
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateTile('Ends', _endAt, () async {
                    final picked = await _pickDateTime(_endAt);
                    if (picked != null && mounted) {
                      setState(() => _endAt = picked);
                    }
                  }),
                ),
              ]),

              // ── Payment ──
              const SizedBox(height: 16),
              _section('Payment'),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            'Plan: ${_plan.label}',
                            style: AppTextStyles.body,
                          ),
                        ),
                        Text(
                          '₹${_plan.amountInr} + GST',
                          style: AppTextStyles.h3,
                        ),
                      ]),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Payment received'),
                        subtitle: Text(
                          _paymentReceived
                              ? 'Ad will activate for 30 days from today.'
                              : 'Ad will stay as "Pending payment".',
                          style: AppTextStyles.caption,
                        ),
                        value: _paymentReceived,
                        onChanged: (v) =>
                            setState(() => _paymentReceived = v),
                      ),
                      if (_paymentReceived) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _paymentMethod,
                          decoration: const InputDecoration(
                              labelText: 'Payment method'),
                          items: const [
                            DropdownMenuItem(
                                value: 'upi', child: Text('UPI')),
                            DropdownMenuItem(
                                value: 'razorpay',
                                child: Text('Razorpay')),
                            DropdownMenuItem(
                                value: 'bank_transfer',
                                child: Text('Bank transfer')),
                            DropdownMenuItem(
                                value: 'cash', child: Text('Cash')),
                          ],
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v!),
                        ),
                        const SizedBox(height: 8),
                        _field(
                          'Payment reference (UTR / transaction ID / receipt no.)',
                          _paymentRef,
                          required: true,
                          hint:
                              'e.g. 4567 8901 2345 or UPI/20261109/123456',
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Serving ──
              const SizedBox(height: 16),
              _section('Serving'),
              Row(children: [
                Expanded(
                  child: _field(
                    'Priority',
                    _priority,
                    keyboard: TextInputType.number,
                    hint: 'e.g. 0 (higher shows first)',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'Weight',
                    _weight,
                    keyboard: TextInputType.number,
                    hint: 'e.g. 100',
                  ),
                ),
              ]),

              const SizedBox(height: 24),
              _actionRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planStatusChip(AdModel ad) {
    final color = switch (ad.planStatus) {
      AdPlanStatus.active => AppColors.success,
      AdPlanStatus.expired => AppColors.error,
      AdPlanStatus.pendingPayment => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Plan: ${ad.planStatus.label}',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label, style: AppTextStyles.h3),
      );

  Widget _field(
    String label,
    TextEditingController controller, {
    bool required = false,
    int? maxLength,
    int minLines = 1,
    TextInputType? keyboard,
    String? hint,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          maxLength: maxLength,
          minLines: minLines,
          maxLines: minLines == 1 ? 1 : 4,
          keyboardType: keyboard,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            counterText: '',
          ),
          validator: (v) {
            if (required && (v == null || v.trim().isEmpty)) {
              return '$label is required';
            }
            return validator?.call(v);
          },
        ),
      );

  Widget _dateTile(String label, DateTime? value, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                const SizedBox(height: 4),
                Text(
                  value == null
                      ? 'Not set'
                      : '${value.day}/${value.month}/${value.year} '
                          '${value.hour.toString().padLeft(2, '0')}:'
                          '${value.minute.toString().padLeft(2, '0')}',
                  style: AppTextStyles.body,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _imagePreview() {
    if (_pendingBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(_pendingBytes!,
            height: 160, width: double.infinity, fit: BoxFit.cover),
      );
    }
    if (_imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(_imageUrl,
            height: 160, width: double.infinity, fit: BoxFit.cover),
      );
    }
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.textMuted.withOpacity(.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Text('No image uploaded',
            style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }

  Widget _actionRow() {
    final ad = widget.existing;
    final isDraft = ad == null ||
        ad.status == AdStatus.draft ||
        ad.status == AdStatus.rejected;
    final isApproved = ad?.status == AdStatus.approved;
    final isPending = ad?.status == AdStatus.pendingReview;

    return Column(
      children: [
        if (_saving)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                _resolvingCode
                    ? 'Looking up lab clinic…'
                    : 'Saving ad…',
                style: AppTextStyles.caption,
              ),
            ]),
          ),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed:
                  _saving ? null : () => _save(status: AdStatus.draft),
              child: const Text('Save draft'),
            ),
          ),
          const SizedBox(width: 10),
          if (isDraft)
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                onPressed: _saving
                    ? null
                    : () => _save(status: AdStatus.pendingReview),
                child: const Text('Submit for review',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          if (isPending) ...[
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success),
                onPressed: _saving ? null : _approve,
                child: const Text('Approve',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error),
                onPressed: _saving ? null : _reject,
                child: const Text('Reject',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
          if (isApproved)
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : _pause,
                child: const Text('Pause'),
              ),
            ),
        ]),
      ],
    );
  }

  Future<void> _approve() async {
    final id = widget.existing!.adId;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    setState(() => _saving = true);
    try {
      await ref.read(adsServiceProvider).approve(id, uid);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Reject ad'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
    if (reason == null || reason.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    setState(() => _saving = true);
    try {
      await ref.read(adsServiceProvider).reject(
            widget.existing!.adId,
            uid,
            reason,
          );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pause() async {
    setState(() => _saving = true);
    try {
      await ref.read(adsServiceProvider).pause(widget.existing!.adId);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}