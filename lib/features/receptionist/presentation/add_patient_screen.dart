import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/patient_model.dart';
import '../../../core/services/patient_service.dart';
import '../../../core/widgets/dynamic_row_list.dart';
import '../../../core/widgets/form_section.dart';
import '../../../core/widgets/labeled_field.dart';
import '../../../core/widgets/tag_input.dart';
import '../../../core/providers/service_providers.dart';

class AddPatientScreen extends ConsumerStatefulWidget {
  const AddPatientScreen({super.key});

  @override
  ConsumerState<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends ConsumerState<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();

  // Personal
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  final _occupation = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _referredBy = TextEditingController();
  String _gender = 'male';
  String? _maritalStatus;
  String? _bloodGroup;
  DateTime? _dob;

  // Medical
  final List<String> _allergies = [];
  final List<String> _chronicConditions = [];
  final _medicationNotes = TextEditingController();

  // Present medications
  final List<Map<String, dynamic>> _currentMedications = [];

  // Past history
  final List<Map<String, dynamic>> _pastMedicalHistory = [];
  final List<Map<String, dynamic>> _pastSurgeries = [];
  final List<Map<String, dynamic>> _pastTreatments = [];

  // Lifestyle
  String? _smoking;
  String? _alcohol;
  String? _diet;
  String? _activity;

  // Notes
  final _doctorNotes = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _phone,
      _email,
      _address,
      _city,
      _pincode,
      _occupation,
      _emergencyName,
      _emergencyPhone,
      _referredBy,
      _medicationNotes,
      _doctorNotes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.background,
            surface: AppColors.surfaceElevated,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Widget _dropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String hint = 'Select',
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Text(hint,
              style: const TextStyle(color: AppColors.textMuted)),
          dropdownColor: AppColors.surfaceElevated,
          style: const TextStyle(color: AppColors.textPrimary),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
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

    // Fetch the current user to attach their clinic to the patient
    final currentUser = await ref.read(currentUserProvider.future);
    if (currentUser == null || currentUser.clinicId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No clinic linked to your account'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);

    final patient = PatientModel(
      docId: '',
      patientId: '',
      fullName: _fullName.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      gender: _gender,
      dob: _dob,
      bloodGroup: _bloodGroup,
      maritalStatus: _maritalStatus,
      occupation:
          _occupation.text.trim().isEmpty ? null : _occupation.text.trim(),
      address:
          _address.text.trim().isEmpty ? null : _address.text.trim(),
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      pincode:
          _pincode.text.trim().isEmpty ? null : _pincode.text.trim(),
      emergencyContactName: _emergencyName.text.trim().isEmpty
          ? null
          : _emergencyName.text.trim(),
      emergencyContactPhone: _emergencyPhone.text.trim().isEmpty
          ? null
          : _emergencyPhone.text.trim(),
      referredBy: _referredBy.text.trim().isEmpty
          ? null
          : _referredBy.text.trim(),
      allergies: _allergies,
      chronicConditions: _chronicConditions,
      currentMedicationNotes: _medicationNotes.text.trim().isEmpty
          ? null
          : _medicationNotes.text.trim(),
      currentMedications: _currentMedications,
      pastMedicalHistory: _pastMedicalHistory,
      pastSurgeries: _pastSurgeries,
      pastTreatments: _pastTreatments,
      smoking: _smoking,
      alcohol: _alcohol,
      diet: _diet,
      activityLevel: _activity,
      doctorNotes: _doctorNotes.text.trim().isEmpty
          ? null
          : _doctorNotes.text.trim(),

      // NEW: clinic scoping
      clinicId: currentUser.clinicId,
      createdByUserId: currentUser.uid,
      active: true,
    );

    try {
      final saved =
          await ref.read(patientServiceProvider).addPatient(patient);
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Patient Added',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Patient ID',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                saved.patientId,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text('${saved.fullName} • ${saved.phone}',
                  style: const TextStyle(
                      color: AppColors.textSecondary)),
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
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add Patient'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  )
                : const Icon(Icons.check_rounded,
                    color: AppColors.primary),
            label: const Text('Save',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionPersonal(),
            _sectionMedical(),
            _sectionCurrentMedication(),
            _sectionPastHistory(),
            _sectionPastTreatment(),
            _sectionLifestyle(),
            _sectionNotes(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save Patient'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // SECTIONS
  // -----------------------------------------------------------------

  Widget _sectionPersonal() {
    return FormSection(
      title: 'Personal Details',
      icon: Icons.person_outline_rounded,
      accent: AppColors.receptionAccent,
      children: [
        LabeledField(
          label: 'Full Name',
          required: true,
          child: DarkTextField(
            controller: _fullName,
            hint: 'e.g. Rahul Mehta',
            icon: Icons.person_outline,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ),
        LabeledField(
          label: 'Phone Number',
          required: true,
          child: DarkTextField(
            controller: _phone,
            hint: '+91 98xxxxxxxx',
            keyboardType: TextInputType.phone,
            icon: Icons.phone_outlined,
            validator: (v) =>
                (v == null || v.trim().length < 10) ? 'Required' : null,
          ),
        ),
        LabeledField(
          label: 'Email',
          child: DarkTextField(
            controller: _email,
            hint: 'patient@email.com',
            keyboardType: TextInputType.emailAddress,
            icon: Icons.alternate_email_rounded,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Gender',
                child: _dropdown(
                  value: _gender,
                  items: const ['male', 'female', 'other'],
                  onChanged: (v) => setState(() => _gender = v!),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Date of Birth',
                child: GestureDetector(
                  onTap: _pickDob,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            color: AppColors.textMuted, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _dob == null
                                ? 'Select date'
                                : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(
                              color: _dob == null
                                  ? AppColors.textMuted
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Blood Group',
                child: _dropdown(
                  value: _bloodGroup,
                  items: const [
                    'A+', 'A-', 'B+', 'B-',
                    'AB+', 'AB-', 'O+', 'O-'
                  ],
                  onChanged: (v) => setState(() => _bloodGroup = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Marital Status',
                child: _dropdown(
                  value: _maritalStatus,
                  items: const [
                    'Single', 'Married', 'Divorced', 'Widowed'
                  ],
                  onChanged: (v) => setState(() => _maritalStatus = v),
                ),
              ),
            ),
          ],
        ),
        LabeledField(
          label: 'Occupation',
          child: DarkTextField(
            controller: _occupation,
            hint: 'e.g. Software Engineer',
            icon: Icons.work_outline_rounded,
          ),
        ),
        LabeledField(
          label: 'Address',
          child: DarkTextField(
            controller: _address,
            hint: 'Street, area',
            maxLines: 2,
            icon: Icons.home_outlined,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'City',
                child: DarkTextField(
                  controller: _city,
                  hint: 'City',
                  icon: Icons.location_city_outlined,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Pincode',
                child: DarkTextField(
                  controller: _pincode,
                  hint: '560001',
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
          ],
        ),
        LabeledField(
          label: 'Emergency Contact Name',
          child: DarkTextField(
            controller: _emergencyName,
            hint: 'Full name',
            icon: Icons.emergency_outlined,
          ),
        ),
        LabeledField(
          label: 'Emergency Contact Phone',
          child: DarkTextField(
            controller: _emergencyPhone,
            hint: '+91 98xxxxxxxx',
            keyboardType: TextInputType.phone,
            icon: Icons.phone_in_talk_outlined,
          ),
        ),
        LabeledField(
          label: 'Referred By (optional)',
          child: DarkTextField(
            controller: _referredBy,
            hint: 'Doctor or clinic name',
            icon: Icons.share_outlined,
          ),
        ),
      ],
    );
  }

  Widget _sectionMedical() {
    return FormSection(
      title: 'Medical Details',
      icon: Icons.monitor_heart_outlined,
      accent: AppColors.error,
      children: [
        LabeledField(
          label: 'Known Allergies',
          child: TagInput(
            tags: _allergies,
            hint: 'e.g. Penicillin',
            accent: AppColors.error,
            onChanged: (v) => setState(() {
              _allergies
                ..clear()
                ..addAll(v);
            }),
          ),
        ),
        LabeledField(
          label: 'Chronic Conditions',
          child: TagInput(
            tags: _chronicConditions,
            hint: 'e.g. Diabetes, Hypertension',
            accent: AppColors.warning,
            onChanged: (v) => setState(() {
              _chronicConditions
                ..clear()
                ..addAll(v);
            }),
          ),
        ),
        LabeledField(
          label: 'Additional Medical Notes',
          child: DarkTextField(
            controller: _medicationNotes,
            hint: 'Any notes the doctor should know',
            maxLines: 3,
          ),
        ),
      ],
    );
  }

  Widget _sectionCurrentMedication() {
    return FormSection(
      title: 'Present Medication',
      icon: Icons.medication_outlined,
      accent: AppColors.success,
      initiallyExpanded: false,
      children: [
        DynamicRowList(
          items: _currentMedications,
          accent: AppColors.success,
          addLabel: 'Add Medication',
          fields: const [
            FieldSpec(
                key: 'name', label: 'Medicine', hint: 'e.g. Metformin'),
            FieldSpec(key: 'dose', label: 'Dose', hint: 'e.g. 500mg'),
            FieldSpec(key: 'frequency', label: 'Frequency',
                hint: 'e.g. Twice daily'),
            FieldSpec(
                key: 'since', label: 'Since', hint: 'e.g. 6 months'),
          ],
          onChanged: (v) => setState(() {
            _currentMedications
              ..clear()
              ..addAll(v);
          }),
        ),
      ],
    );
  }

  Widget _sectionPastHistory() {
    return FormSection(
      title: 'Past Medical History',
      icon: Icons.history_rounded,
      accent: AppColors.info,
      initiallyExpanded: false,
      children: [
        LabeledField(
          label: 'Significant Illnesses',
          child: DynamicRowList(
            items: _pastMedicalHistory,
            accent: AppColors.info,
            addLabel: 'Add Illness',
            fields: const [
              FieldSpec(
                  key: 'condition', label: 'Condition',
                  hint: 'e.g. Typhoid'),
              FieldSpec(key: 'year', label: 'Year', hint: 'e.g. 2018'),
              FieldSpec(
                  key: 'notes', label: 'Notes', hint: 'Optional'),
            ],
            onChanged: (v) => setState(() {
              _pastMedicalHistory
                ..clear()
                ..addAll(v);
            }),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Past Surgeries',
          child: DynamicRowList(
            items: _pastSurgeries,
            accent: AppColors.info,
            addLabel: 'Add Surgery',
            fields: const [
              FieldSpec(
                  key: 'procedure', label: 'Procedure',
                  hint: 'e.g. Appendectomy'),
              FieldSpec(
                  key: 'hospital', label: 'Hospital',
                  hint: 'Hospital name'),
              FieldSpec(key: 'year', label: 'Year', hint: 'e.g. 2021'),
            ],
            onChanged: (v) => setState(() {
              _pastSurgeries
                ..clear()
                ..addAll(v);
            }),
          ),
        ),
      ],
    );
  }

  Widget _sectionPastTreatment() {
    return FormSection(
      title: 'Past Treatment',
      icon: Icons.medical_information_outlined,
      accent: AppColors.secondary,
      initiallyExpanded: false,
      children: [
        DynamicRowList(
          items: _pastTreatments,
          accent: AppColors.secondary,
          addLabel: 'Add Treatment',
          fields: const [
            FieldSpec(
                key: 'condition', label: 'Condition',
                hint: 'e.g. Pneumonia'),
            FieldSpec(
                key: 'treatment', label: 'Treatment Given',
                hint: 'e.g. IV antibiotics, 5 days'),
            FieldSpec(
                key: 'doctor', label: 'Doctor / Hospital',
                hint: 'Name'),
            FieldSpec(key: 'year', label: 'Year', hint: 'e.g. 2023'),
          ],
          onChanged: (v) => setState(() {
            _pastTreatments
              ..clear()
              ..addAll(v);
          }),
        ),
      ],
    );
  }

  Widget _sectionLifestyle() {
    return FormSection(
      title: 'Lifestyle',
      icon: Icons.self_improvement_rounded,
      accent: AppColors.accent,
      initiallyExpanded: false,
      children: [
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Smoking',
                child: _dropdown(
                  value: _smoking,
                  items: const ['Never', 'Occasional', 'Regular'],
                  onChanged: (v) => setState(() => _smoking = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Alcohol',
                child: _dropdown(
                  value: _alcohol,
                  items: const ['Never', 'Occasional', 'Regular'],
                  onChanged: (v) => setState(() => _alcohol = v),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: LabeledField(
                label: 'Diet',
                child: _dropdown(
                  value: _diet,
                  items: const [
                    'Vegetarian', 'Non-vegetarian', 'Vegan', 'Mixed'
                  ],
                  onChanged: (v) => setState(() => _diet = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                label: 'Activity',
                child: _dropdown(
                  value: _activity,
                  items: const ['Sedentary', 'Light', 'Moderate', 'Active'],
                  onChanged: (v) => setState(() => _activity = v),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionNotes() {
    return FormSection(
      title: 'Doctor Notes',
      icon: Icons.notes_rounded,
      accent: AppColors.textSecondary,
      initiallyExpanded: false,
      children: [
        LabeledField(
          label: 'Additional Notes',
          child: DarkTextField(
            controller: _doctorNotes,
            hint: 'Any other observations',
            maxLines: 4,
          ),
        ),
      ],
    );
  }
}