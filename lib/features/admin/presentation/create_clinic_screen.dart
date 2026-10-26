// lib/features/admin/presentation/create_clinic_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/admin_service.dart';
import '../../../core/widgets/form_section.dart';
import '../../../core/widgets/labeled_field.dart';
import '../../../core/widgets/tag_input.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class CreateClinicScreen extends ConsumerStatefulWidget {
  /// When true, this screen is displayed inside AdminShell (with its own AppBar).
  /// When false, it's pushed as a full-screen page from the dashboard.
  final bool embedded;

  const CreateClinicScreen({super.key, this.embedded = false});

  @override
  ConsumerState<CreateClinicScreen> createState() =>
      _CreateClinicScreenState();
}

class _CreateClinicScreenState extends ConsumerState<CreateClinicScreen> {
  final _formKey = GlobalKey<FormState>();

  // Type — "clinic" or "lab"
  String _type = 'clinic';

  // Identity
  final _clinicCode = TextEditingController();
  final _name = TextEditingController();
  final _displayName = TextEditingController();
  final _tagline = TextEditingController();

  // Contact
  final _primaryPhone = TextEditingController();
  final _secondaryPhone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _whatsappNumber = TextEditingController();

  // Address
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();

  // Registration
  final _clinicRegNumber = TextEditingController();
  final _gstNumber = TextEditingController();
  final _panNumber = TextEditingController();
  final _dltEntityId = TextEditingController();

  // Financial
  final _consultationFee = TextEditingController(text: '500');
  final _followUpFee = TextEditingController(text: '250');
  final _teleconsultFee = TextEditingController(text: '400');
  final _upiId = TextEditingController();
  final List<String> _paymentMethods = ['cash', 'upi'];

  // Appointment defaults
  final _slotDuration = TextEditingController(text: '15');
  final _maxAdvanceDays = TextEditingController(text: '30');
  final _confirmationWindow = TextEditingController(text: '24');
  final _tokenPrefix = TextEditingController(text: 'A');

  // Owner
  final _ownerEmail = TextEditingController();
  final _ownerName = TextEditingController();
  final _ownerPhone = TextEditingController();

  // Advanced
  String _subscriptionPlan = 'starter';
  bool _whatsappEnabled = true;
  bool _acceptsInsurance = false;

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name, _displayName, _tagline,
      _primaryPhone, _secondaryPhone, _email, _website, _whatsappNumber,
      _line1, _line2, _area, _city, _state, _pincode,
      _clinicRegNumber, _gstNumber, _panNumber, _dltEntityId,
      _consultationFee, _followUpFee, _teleconsultFee, _upiId,
      _slotDuration, _maxAdvanceDays, _confirmationWindow, _tokenPrefix,
      _ownerEmail, _ownerName, _ownerPhone,
      _clinicCode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _generateCode() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final suffix = (now % 100000).toString().padLeft(5, '0');
    return _type == 'lab' ? 'DGP-LAB-$suffix' : 'DGP-CLN-$suffix';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill required fields'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final data = <String, dynamic>{
        // Type — distinguishes clinic from lab
        'type': _type,

        // Identity
        'name': _name.text.trim(),
        'displayName': _displayName.text.trim().isEmpty
            ? _name.text.trim()
            : _displayName.text.trim(),
        'tagline': _tagline.text.trim().isEmpty
            ? null
            : _tagline.text.trim(),
        'clinicCode': _clinicCode.text.trim().isEmpty
            ? _generateCode()
            : _clinicCode.text.trim().toUpperCase(),

        // Contact
        'primaryPhone': _primaryPhone.text.trim(),
        'secondaryPhone': _secondaryPhone.text.trim().isEmpty
            ? null
            : _secondaryPhone.text.trim(),
        'email': _email.text.trim().isEmpty
            ? null
            : _email.text.trim().toLowerCase(),
        'website': _website.text.trim().isEmpty
            ? null
            : _website.text.trim(),
        'whatsappNumber': _whatsappNumber.text.trim().isEmpty
            ? null
            : _whatsappNumber.text.trim(),

        'clinicOwnerName': _ownerName.text.trim(),
        'ownerEmail': _ownerEmail.text.trim().toLowerCase(),

        // Address
        'practiceAddress': {
          'line1': _line1.text.trim(),
          'line2': _line2.text.trim().isEmpty
              ? null
              : _line2.text.trim(),
          'area': _area.text.trim(),
          'city': _city.text.trim(),
          'state': _state.text.trim(),
          'pincode': _pincode.text.trim(),
          'country': 'India',
        },

        // Registration
        'clinicRegistrationNumber': _clinicRegNumber.text.trim().isEmpty
            ? null
            : _clinicRegNumber.text.trim(),
        'gstNumber': _gstNumber.text.trim().isEmpty
            ? null
            : _gstNumber.text.trim(),
        'panNumber': _panNumber.text.trim().isEmpty
            ? null
            : _panNumber.text.trim(),
        'dltEntityId': _dltEntityId.text.trim().isEmpty
            ? null
            : _dltEntityId.text.trim(),

        // Shared operational defaults
        'timezone': 'Asia/Kolkata',
        'whatsappEnabled': _whatsappEnabled,
        'pushNotificationsEnabled': true,
        'emailEnabled': true,

        // Clinic-only fields
        if (_type == 'clinic') ...{
          'currency': 'INR',
          'taxPercent': 18,
          'consultationFee':
              int.tryParse(_consultationFee.text.trim()) ?? 500,
          'followUpFee': int.tryParse(_followUpFee.text.trim()) ?? 250,
          'teleconsultFee':
              int.tryParse(_teleconsultFee.text.trim()) ?? 400,
          'acceptsInsurance': _acceptsInsurance,
          'paymentMethods': _paymentMethods,
          'upiId': _upiId.text.trim().isEmpty
              ? null
              : _upiId.text.trim(),
          'slotDurationMinutes':
              int.tryParse(_slotDuration.text.trim()) ?? 15,
          'maxAdvanceBookingDays':
              int.tryParse(_maxAdvanceDays.text.trim()) ?? 30,
          'confirmationWindowHours':
              int.tryParse(_confirmationWindow.text.trim()) ?? 24,
          'tokenPrefix': _tokenPrefix.text.trim().isEmpty
              ? 'A'
              : _tokenPrefix.text.trim().toUpperCase(),
          'subscriptionPlan': _subscriptionPlan,
          'featureFlags': {
            'teleconsult': true,
            'abdm': false,
          },
        },
      };

      final clinicId =
          await ref.read(adminServiceProvider).createClinic(data);

      String? ownerAttachMessage;
      if (_ownerEmail.text.trim().isNotEmpty) {
        final uid = await ref
            .read(adminServiceProvider)
            .findUserIdByEmail(_ownerEmail.text.trim());
        if (uid != null) {
          await ref.read(adminServiceProvider).attachClinicToUser(
                userId: uid,
                clinicId: clinicId,
                role: _type == 'lab' ? 'lab' : 'receptionist',
              );
          ownerAttachMessage = 'Owner account linked.';
        } else {
          ownerAttachMessage =
              '${_type == 'lab' ? 'Lab' : 'Clinic'} created. Owner email not found in users — they must sign up first, then you can link them.';
        }
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
              _type == 'lab' ? 'Lab Created' : 'Clinic Created',
              style: const TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_type == 'lab' ? 'Lab ID' : 'Clinic ID',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(
                clinicId,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text('${_name.text.trim()}',
                  style:
                      const TextStyle(color: AppColors.textSecondary)),
              if (ownerAttachMessage != null) ...[
                const SizedBox(height: 10),
                Text(ownerAttachMessage,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );

      if (!mounted) return;

      _formKey.currentState?.reset();
      for (final c in [
        _name, _displayName, _tagline,
        _primaryPhone, _secondaryPhone, _email, _website, _whatsappNumber,
        _line1, _line2, _area, _city, _state, _pincode,
        _clinicRegNumber, _gstNumber, _panNumber, _dltEntityId,
        _upiId, _ownerEmail, _ownerName, _ownerPhone, _clinicCode,
      ]) {
        c.clear();
      }

      if (!widget.embedded) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _type == 'lab' ? 'Create Lab' : 'Create Clinic';

    final body = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionType(),
          const SizedBox(height: 8),
          _sectionIdentity(),
          _sectionContact(),
          _sectionAddress(),
          _sectionRegistration(),
          if (_type == 'clinic') ...[
            _sectionFinancial(),
            _sectionAppointments(),
            _sectionPlan(),
          ],
          _sectionOwner(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_saving
                  ? 'Creating...'
                  : (_type == 'lab' ? 'Create Lab' : 'Create Clinic')),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );

    if (widget.embedded) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: ClinicAppBar(title: title),
        body: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(title: title, showBackButton: true),
      body: body,
    );
  }

  // -----------------------------------------------------------------
  // Type selector
  // -----------------------------------------------------------------
  Widget _sectionType() {
    return FormSection(
      title: 'Entity Type',
      icon: Icons.category_outlined,
      accent: AppColors.secondary,
      children: [
        Row(children: [
          Expanded(
            child: _typeTile(
              value: 'clinic',
              icon: Icons.local_hospital_outlined,
              label: 'Clinic',
              subtitle: 'GP doctors, patients, appointments',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _typeTile(
              value: 'lab',
              icon: Icons.science_outlined,
              label: 'Lab',
              subtitle: 'Diagnostic tests and reports',
            ),
          ),
        ]),
      ],
    );
  }

  Widget _typeTile({
    required String value,
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(.12)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: selected
                    ? AppColors.primary
                    : AppColors.textMuted,
                size: 22),
            const SizedBox(height: 8),
            Text(label,
                style: AppTextStyles.body.copyWith(
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textPrimary,
                )),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // Identity (labels switch by type)
  // -----------------------------------------------------------------
  Widget _sectionIdentity() {
    final isLab = _type == 'lab';
    return FormSection(
      title: isLab ? 'Lab Identity' : 'Clinic Identity',
      icon: isLab ? Icons.science_outlined : Icons.business_rounded,
      accent: AppColors.secondary,
      children: [
        LabeledField(
          label: isLab ? 'Lab Name' : 'Clinic Name',
          required: true,
          child: DarkTextField(
            controller: _name,
            hint: isLab
                ? 'e.g. Bhaskar Path Lab'
                : 'e.g. Sharma Family Clinic',
            icon: isLab
                ? Icons.science_outlined
                : Icons.local_hospital_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
        LabeledField(
          label: 'Display Name (short form)',
          child: DarkTextField(
            controller: _displayName,
            hint: isLab ? 'e.g. Bhaskar Lab' : 'e.g. Sharma Clinic',
            icon: Icons.short_text_rounded,
          ),
        ),
        LabeledField(
          label: 'Tagline',
          child: DarkTextField(
            controller: _tagline,
            hint: isLab
                ? 'e.g. Accurate reports, on time'
                : 'e.g. Caring for families since 2005',
            icon: Icons.format_quote_rounded,
          ),
        ),
        LabeledField(
          label: isLab ? 'Lab Owner Name' : 'Clinic Owner Name',
          required: true,
          child: DarkTextField(
            controller: _ownerName,
            hint: 'e.g. Dr. Ananya Sharma',
            icon: Icons.person_outline_rounded,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
        LabeledField(
          label: isLab
              ? 'Owner Email (used to claim this lab)'
              : 'Owner Email (used to claim this clinic)',
          required: true,
          child: DarkTextField(
            controller: _ownerEmail,
            hint: 'owner@example.in',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
        LabeledField(
          label: isLab
              ? 'Lab Code (staff use this to join)'
              : 'Clinic Code (staff use this to join)',
          child: DarkTextField(
            controller: _clinicCode,
            hint: 'Leave blank to auto-generate',
            icon: Icons.qr_code_rounded,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Contact
  // -----------------------------------------------------------------
  Widget _sectionContact() {
    return FormSection(
      title: 'Contact',
      icon: Icons.contact_phone_outlined,
      accent: AppColors.info,
      initiallyExpanded: false,
      children: [
        LabeledField(
          label: 'Primary Phone',
          required: true,
          child: DarkTextField(
            controller: _primaryPhone,
            hint: '+91 80 4567 8900',
            keyboardType: TextInputType.phone,
            icon: Icons.phone_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
        LabeledField(
          label: 'Secondary Phone',
          child: DarkTextField(
            controller: _secondaryPhone,
            hint: '+91 80 4567 8901',
            keyboardType: TextInputType.phone,
            icon: Icons.phone_iphone_outlined,
          ),
        ),
        LabeledField(
          label: 'Email',
          child: DarkTextField(
            controller: _email,
            hint: 'hello@example.in',
            keyboardType: TextInputType.emailAddress,
            icon: Icons.alternate_email_rounded,
          ),
        ),
        LabeledField(
          label: 'WhatsApp Number',
          child: DarkTextField(
            controller: _whatsappNumber,
            hint: '+91 98765 43210',
            keyboardType: TextInputType.phone,
            icon: Icons.chat_rounded,
          ),
        ),
        LabeledField(
          label: 'Website',
          child: DarkTextField(
            controller: _website,
            hint: 'https://example.in',
            keyboardType: TextInputType.url,
            icon: Icons.language_rounded,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Address
  // -----------------------------------------------------------------
  Widget _sectionAddress() {
    return FormSection(
      title: 'Address',
      icon: Icons.location_on_outlined,
      accent: AppColors.labAccent,
      initiallyExpanded: false,
      children: [
        LabeledField(
          label: 'Address Line 1',
          required: true,
          child: DarkTextField(
            controller: _line1,
            hint: 'Building / street',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
        LabeledField(
          label: 'Address Line 2',
          child: DarkTextField(
            controller: _line2,
            hint: 'Landmark (optional)',
          ),
        ),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Area',
                child: DarkTextField(
                  controller: _area,
                  hint: 'Indiranagar',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Pincode',
                required: true,
                child: DarkTextField(
                  controller: _pincode,
                  hint: '560001',
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : null,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'City',
                required: true,
                child: DarkTextField(
                  controller: _city,
                  hint: 'Bengaluru',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'State',
                required: true,
                child: DarkTextField(
                  controller: _state,
                  hint: 'Karnataka',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Registration
  // -----------------------------------------------------------------
  Widget _sectionRegistration() {
    return FormSection(
      title: 'Registration & Compliance',
      icon: Icons.verified_outlined,
      accent: AppColors.success,
      initiallyExpanded: false,
      children: [
        LabeledField(
          label: 'Registration Number',
          child: DarkTextField(
            controller: _clinicRegNumber,
            hint: 'MH/LAB/2026/1234',
            icon: Icons.badge_outlined,
          ),
        ),
        LabeledField(
          label: 'GST Number',
          child: DarkTextField(
            controller: _gstNumber,
            hint: '29ABCDE1234F1Z5',
            icon: Icons.receipt_outlined,
          ),
        ),
        LabeledField(
          label: 'PAN',
          child: DarkTextField(
            controller: _panNumber,
            hint: 'ABCDE1234F',
            icon: Icons.credit_card_outlined,
          ),
        ),
        LabeledField(
          label: 'DLT Entity ID (for SMS/WhatsApp)',
          child: DarkTextField(
            controller: _dltEntityId,
            hint: '1101234567890123456',
            icon: Icons.sim_card_outlined,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Financial (clinic only)
  // -----------------------------------------------------------------
  Widget _sectionFinancial() {
    return FormSection(
      title: 'Fees & Payment',
      icon: Icons.payments_outlined,
      accent: AppColors.accent,
      initiallyExpanded: false,
      children: [
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Consultation Fee (₹)',
                child: DarkTextField(
                  controller: _consultationFee,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Follow-up Fee (₹)',
                child: DarkTextField(
                  controller: _followUpFee,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Teleconsult Fee (₹)',
                child: DarkTextField(
                  controller: _teleconsultFee,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'UPI ID',
                child: DarkTextField(
                  controller: _upiId,
                  hint: 'clinic@okhdfc',
                ),
              ),
            ),
          ],
        ),
        LabeledField(
          label: 'Payment Methods',
          child: TagInput(
            tags: _paymentMethods,
            hint: 'cash, upi, card',
            accent: AppColors.accent,
            onChanged: (v) => setState(() {
              _paymentMethods
                ..clear()
                ..addAll(v);
            }),
          ),
        ),
        SwitchListTile(
          value: _acceptsInsurance,
          onChanged: (v) => setState(() => _acceptsInsurance = v),
          activeThumbColor: AppColors.primary,
          title: const Text('Accepts Insurance',
              style: TextStyle(color: AppColors.textPrimary)),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Appointment defaults (clinic only)
  // -----------------------------------------------------------------
  Widget _sectionAppointments() {
    return FormSection(
      title: 'Appointment Defaults',
      icon: Icons.schedule_rounded,
      accent: AppColors.receptionAccent,
      initiallyExpanded: false,
      children: [
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Slot Duration (min)',
                child: DarkTextField(
                  controller: _slotDuration,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Max Advance (days)',
                child: DarkTextField(
                  controller: _maxAdvanceDays,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Confirm Window (hrs)',
                child: DarkTextField(
                  controller: _confirmationWindow,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Token Prefix',
                child: DarkTextField(
                  controller: _tokenPrefix,
                  hint: 'A',
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          value: _whatsappEnabled,
          onChanged: (v) => setState(() => _whatsappEnabled = v),
          activeThumbColor: AppColors.primary,
          title: const Text('Enable WhatsApp reminders',
              style: TextStyle(color: AppColors.textPrimary)),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Owner (optional linking)
  // -----------------------------------------------------------------
  Widget _sectionOwner() {
    return FormSection(
      title: 'Owner / Staff (optional)',
      icon: Icons.person_add_alt_1_outlined,
      accent: AppColors.doctorAccent,
      initiallyExpanded: false,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'The owner must have already signed up. Enter their email to link them to this ${_type == 'lab' ? 'lab' : 'clinic'}.',
            style:
                const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
        LabeledField(
          label: 'Owner Email',
          child: DarkTextField(
            controller: _ownerEmail,
            hint: 'owner@example.in',
            keyboardType: TextInputType.emailAddress,
            icon: Icons.alternate_email_rounded,
          ),
        ),
        LabeledField(
          label: 'Owner Name (for record)',
          child: DarkTextField(
            controller: _ownerName,
            hint: 'Dr. Ananya Sharma',
            icon: Icons.person_outline,
          ),
        ),
        LabeledField(
          label: 'Owner Phone',
          child: DarkTextField(
            controller: _ownerPhone,
            hint: '+91 98765 43210',
            keyboardType: TextInputType.phone,
            icon: Icons.phone_outlined,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Subscription (clinic only)
  // -----------------------------------------------------------------
  Widget _sectionPlan() {
    return FormSection(
      title: 'Subscription',
      icon: Icons.workspace_premium_outlined,
      accent: AppColors.warning,
      initiallyExpanded: false,
      children: [
        LabeledField(
          label: 'Plan',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _subscriptionPlan,
                isExpanded: true,
                dropdownColor: AppColors.surfaceElevated,
                style: const TextStyle(color: AppColors.textPrimary),
                items: const [
                  DropdownMenuItem(
                      value: 'starter', child: Text('Starter')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro')),
                  DropdownMenuItem(
                      value: 'enterprise',
                      child: Text('Enterprise')),
                ],
                onChanged: (v) =>
                    setState(() => _subscriptionPlan = v ?? 'starter'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}