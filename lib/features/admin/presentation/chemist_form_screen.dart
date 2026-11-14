// lib/features/admin/presentation/chemist_form_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/chemist_model.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import 'chemists_admin_screen.dart' show allChemistsProvider;

// Clinics (excluding labs) for the "linked clinics" checkboxes.
final _clinicsForPickerProvider = StreamProvider.autoDispose<
    List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) {
  return FirebaseFirestore.instance
      .collection('clinics')
      .where('type', isNotEqualTo: 'lab')
      .snapshots()
      .map((s) => s.docs);
});

class ChemistFormScreen extends ConsumerStatefulWidget {
  final ChemistModel? existing;
  const ChemistFormScreen({super.key, this.existing});

  @override
  ConsumerState<ChemistFormScreen> createState() => _ChemistFormScreenState();
}

class _ChemistFormScreenState extends ConsumerState<ChemistFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _owner;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _pincode;
  late final TextEditingController _license;
  late final TextEditingController _pincodesServiced;
  late final TextEditingController _deliveryRadius;
  late final TextEditingController _deliveryFee;
  late final TextEditingController _minOrder;
  late final TextEditingController _discount;
  late final TextEditingController _upiId;

  late Set<String> _linkedClinicIds;
  bool _deliveryAvailable = false;
  bool _isActive = true;
  bool _saving = false;
  bool _inviting = false;
  String? _savedDocId; // set after Save, so Invite can target it

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _owner = TextEditingController(text: c?.ownerName ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _city = TextEditingController(text: c?.city ?? '');
    _pincode = TextEditingController(text: c?.pincode ?? '');
    _license = TextEditingController(text: c?.licenseNumber ?? '');
    _pincodesServiced =
        TextEditingController(text: (c?.serviceablePincodes ?? []).join(', '));
    _deliveryRadius = TextEditingController(
        text: (c?.deliveryRadiusKm ?? 0) == 0
            ? ''
            : c!.deliveryRadiusKm.toStringAsFixed(0));
    _deliveryFee = TextEditingController(
        text: (c?.deliveryFee ?? 0) == 0
            ? ''
            : c!.deliveryFee.toStringAsFixed(0));
    _minOrder = TextEditingController(
        text: c?.minOrderAmount == null
            ? ''
            : c!.minOrderAmount!.toStringAsFixed(0));
    _discount = TextEditingController(
        text: c?.discountPercent == null
            ? ''
            : c!.discountPercent!.toStringAsFixed(0));
    _upiId = TextEditingController(text: c?.upiId ?? '');
    _linkedClinicIds = {...?c?.linkedClinicIds};
    _deliveryAvailable = c?.deliveryAvailable ?? false;
    _isActive = c?.isActive ?? true;
    _savedDocId = c?.docId;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _owner,
      _phone,
      _email,
      _address,
      _city,
      _pincode,
      _license,
      _pincodesServiced,
      _deliveryRadius,
      _deliveryFee,
      _minOrder,
      _discount,
      _upiId,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _saveChemist() async {
    if (_name.text.trim().isEmpty) {
      _toast('Enter chemist name', AppColors.error);
      return null;
    }
    if (_pincode.text.trim().length != 6) {
      _toast('Enter a 6-digit pincode for the pharmacy', AppColors.error);
      return null;
    }
    if (_deliveryAvailable && _pincodesServiced.text.trim().isEmpty) {
      _toast(
          'Add at least one serviceable pincode, or turn off delivery.',
          AppColors.error);
      return null;
    }

    setState(() => _saving = true);
    try {
      final col = FirebaseFirestore.instance.collection('chemists');
      final docRef =
          _savedDocId != null ? col.doc(_savedDocId) : col.doc();

      final pincodes = _pincodesServiced.text
          .split(RegExp(r'[,\s]+'))
          .map((e) => e.trim())
          .where((e) => e.length == 6)
          .toSet()
          .toList();

      double parseDouble(TextEditingController c, [double? fallback]) {
        final v = double.tryParse(c.text.trim());
        if (v == null) return fallback ?? 0;
        return v;
      }

      double? parseDoubleOrNull(TextEditingController c) {
        final s = c.text.trim();
        if (s.isEmpty) return null;
        return double.tryParse(s);
      }

      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'ownerName': _owner.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
        'pincode': _pincode.text.trim(),
        'licenseNumber': _license.text.trim(),
        'linkedClinicIds': _linkedClinicIds.toList(),
        'serviceablePincodes': _deliveryAvailable ? pincodes : <String>[],
        'deliveryAvailable': _deliveryAvailable,
        'deliveryRadiusKm':
            _deliveryAvailable ? parseDouble(_deliveryRadius, 0) : 0,
        'deliveryFee':
            _deliveryAvailable ? parseDouble(_deliveryFee, 0) : 0,
        'minOrderAmount':
            _deliveryAvailable ? parseDoubleOrNull(_minOrder) : null,
        'discountPercent': parseDoubleOrNull(_discount),
        'upiId': _upiId.text.trim(),
        'isActive': _isActive,
        'isVetted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_savedDocId != null) {
        await docRef.update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await docRef.set(data);
        setState(() => _savedDocId = docRef.id);
      }

      ref.invalidate(allChemistsProvider);
      return docRef.id;
    } catch (e) {
      if (mounted) _toast('Save failed: $e', AppColors.error);
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Invite flow (server-side via Cloud Function `createChemistUser`):
  ///  1. Function creates the Firebase Auth user with a random password.
  ///  2. Function writes users/{uid} with role:chemist + linkedChemistDocId.
  ///  3. Function marks chemists/{docId} with linkedUserUid + inviteStatus:'sent'.
  ///  4. Function returns a password-reset link the admin can forward.
  Future<void> _sendInvite() async {
    if (_email.text.trim().isEmpty || !_email.text.contains('@')) {
      _toast('Add a valid chemist email before inviting.', AppColors.error);
      return;
    }
    if (_savedDocId == null) {
      final id = await _saveChemist();
      if (id == null) return;
    }
    setState(() => _inviting = true);

    final email = _email.text.trim().toLowerCase();
    final docId = _savedDocId!;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('createChemistUser');
      final res = await callable.call<Map<String, dynamic>>({
        'email': email,
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'chemistDocId': docId,
      });

      final data = res.data;
      final resetLink = data['resetLink'] as String?;

      ref.invalidate(allChemistsProvider);

      if (!mounted) return;

      if (resetLink != null && resetLink.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Invite ready', style: AppTextStyles.h3),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send this link to $email via WhatsApp or SMS. '
                  'The chemist will set their own password and land on '
                  'the chemist dashboard.',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  resetLink,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: resetLink));
                  Navigator.pop(dctx);
                  _toast('Link copied to clipboard', AppColors.success);
                },
                child: const Text('Copy link'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      } else {
        _toast('Invite sent to $email.', AppColors.success);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast('Invite failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  void _toast(String m, Color c) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  @override
  Widget build(BuildContext context) {
    final clinicsAsync = ref.watch(_clinicsForPickerProvider);
    final canInvite =
        _email.text.trim().isNotEmpty && _email.text.contains('@');
    final alreadyInvited = widget.existing?.inviteStatus == 'sent' ||
        widget.existing?.inviteStatus == 'activated';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(
        title: _isEdit ? 'Edit chemist' : 'Add chemist',
        showBackButton: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
          children: [
            _section('Business details', [
              _field(_name, 'Pharmacy name'),
              _field(_owner, 'Owner name'),
              _field(_phone, 'Phone', keyboard: TextInputType.phone),
              _field(_email, 'Email',
                  keyboard: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {})),
              _field(_license, 'Drug licence number'),
            ]),
            const SizedBox(height: 14),
            _section('Address', [
              _field(_address, 'Street address', maxLines: 2),
              Row(children: [
                Expanded(child: _field(_city, 'City')),
                const SizedBox(width: 8),
                Expanded(
                    child: _field(_pincode, 'Pincode',
                        keyboard: TextInputType.number)),
              ]),
            ]),
            const SizedBox(height: 14),
            _sectionWith(
              title: 'Delivery',
              tail: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _deliveryAvailable,
                activeColor: AppColors.success,
                title: Text('Delivery available',
                    style: AppTextStyles.body),
                subtitle: Text(
                  _deliveryAvailable
                      ? 'Patient can place a home-delivery order.'
                      : 'Patients will see this as pickup-only.',
                  style: AppTextStyles.caption,
                ),
                onChanged: (v) => setState(() => _deliveryAvailable = v),
              ),
              children: _deliveryAvailable
                  ? [
                      _field(_deliveryRadius,
                          'Delivery service distance (km)',
                          keyboard: TextInputType.number),
                      _field(
                          _pincodesServiced,
                          'Pincodes serviced (comma-separated)',
                          hint: 'e.g. 560001, 560002, 560034'),
                      _field(_deliveryFee, 'Delivery fee (₹)',
                          keyboard: TextInputType.number),
                      _field(_minOrder,
                          'Minimum order amount (₹, optional)',
                          keyboard: TextInputType.number),
                    ]
                  : [
                      Text(
                        'Enable delivery to configure distance, pincodes, '
                        'and fee.',
                        style: AppTextStyles.bodyMuted,
                      ),
                    ],
            ),
            const SizedBox(height: 14),
            _section('Commercial', [
              _field(_discount, 'Discount % (optional)',
                  keyboard: TextInputType.number),
              _field(_upiId, 'UPI ID',
                  hint: 'e.g. pharmacy@okicici'),
            ]),
            const SizedBox(height: 14),
            _section('Linked clinics (metadata)', [
              Text(
                'Partner clinics — shown as a badge to patients. '
                'Not used to gate delivery.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 8),
              clinicsAsync.when(
                loading: () => const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                )),
                error: (e, _) => Text('Unable to load clinics: $e',
                    style: const TextStyle(color: AppColors.error)),
                data: (clinics) {
                  if (clinics.isEmpty) {
                    return Text('No clinics available.',
                        style: AppTextStyles.bodyMuted);
                  }
                  return Column(
                    children: clinics.map((doc) {
                      final name =
                          (doc.data()['name'] ?? doc.id).toString();
                      final selected = _linkedClinicIds.contains(doc.id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selected,
                        activeColor: AppColors.primary,
                        title: Text(name, style: AppTextStyles.body),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _linkedClinicIds.add(doc.id);
                            } else {
                              _linkedClinicIds.remove(doc.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  );
                },
              ),
            ]),
            const SizedBox(height: 14),
            GlassCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                activeColor: AppColors.success,
                title: Text('Active', style: AppTextStyles.body),
                subtitle: Text(
                  'Inactive chemists will not appear to patients.',
                  style: AppTextStyles.caption,
                ),
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              borderColor: AppColors.info.withOpacity(.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.person_add_alt_1_rounded,
                        size: 18, color: AppColors.info),
                    const SizedBox(width: 9),
                    Text('Login invitation',
                        style: AppTextStyles.h3),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    alreadyInvited
                        ? 'Login already sent to ${widget.existing?.email ?? _email.text.trim()}. '
                            'The chemist sets their own password via the '
                            'emailed link.'
                        : 'Send the chemist an email to set their own '
                            'password. On first login they land on the '
                            'chemist dashboard.',
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_inviting || !canInvite)
                          ? null
                          : _sendInvite,
                      icon: _inviting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.mail_outline_rounded,
                              size: 16),
                      label: Text(
                        _inviting
                            ? 'Sending invite…'
                            : alreadyInvited
                                ? 'Re-send invite'
                                : 'Send invite',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.info,
                        side: const BorderSide(color: AppColors.info),
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _saveAndClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ),
      ),
    );
  }

  Future<void> _saveAndClose() async {
    final id = await _saveChemist();
    if (id != null && mounted) Navigator.pop(context);
  }

  Widget _section(String title, List<Widget> children) =>
      _sectionWith(title: title, children: children);

  Widget _sectionWith({
    required String title,
    required List<Widget> children,
    Widget? tail,
  }) =>
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.h3),
            const SizedBox(height: 12),
            if (tail != null) tail,
            ...children,
          ],
        ),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    int maxLines = 1,
    String? hint,
    ValueChanged<String>? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );
}