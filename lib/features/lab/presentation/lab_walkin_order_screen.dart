// lib/features/lab/presentation/lab_walkin_order_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_customer_model.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/models/lab_test_model.dart';
import '../../../core/models/patient_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/lab_customer_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/labeled_field.dart';

class LabWalkinOrderScreen extends ConsumerStatefulWidget {
  const LabWalkinOrderScreen({super.key});

  @override
  ConsumerState<LabWalkinOrderScreen> createState() =>
      _LabWalkinOrderScreenState();
}

class _LabWalkinOrderScreenState extends ConsumerState<LabWalkinOrderScreen> {
  final _customerSvc = LabCustomerService();

  LabCustomerModel? _customer; // the confirmed customer
  final List<LabTestModel> _selectedTests = [];
  final _extraDiscountCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  bool _saving = false;

  // ── Derived pricing getters ──

  double get _totalMrp => _selectedTests.fold<double>(
        0,
        (s, t) => s + (t.mrp?.toDouble() ?? 0),
      );

  double get _totalCatalogDiscount => _selectedTests.fold<double>(
        0,
        (s, t) {
          final mrp = t.mrp?.toDouble() ?? 0;
          final offer = t.offerPrice?.toDouble() ?? mrp;
          return s + (mrp - offer);
        },
      );

  double get _totalTestOffer => _totalMrp - _totalCatalogDiscount;

  double get _extraDiscount {
    final raw = double.tryParse(_extraDiscountCtrl.text.trim()) ?? 0;
    if (raw < 0) return 0;
    return raw;
  }

  double get _billableAmount {
    final net = _totalTestOffer - _extraDiscount;
    return net < 0 ? 0 : net;
  }

  @override
  void initState() {
    super.initState();
    _extraDiscountCtrl.addListener(_onDiscountChanged);
  }

  void _onDiscountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _extraDiscountCtrl.removeListener(_onDiscountChanged);
    _extraDiscountCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final user = await ref.read(currentUserProvider.future);
    if (user?.clinicId == null) return;
    final result = await Navigator.of(context).push<LabCustomerModel>(
      MaterialPageRoute(
        builder: (_) => _CustomerPickerScreen(
          labClinicId: user!.clinicId!,
          labName: user.clinicName ?? 'Lab',
          customerSvc: _customerSvc,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _customer = result);
  }

  Future<void> _pickTests(String labClinicId) async {
    final allTests = await ref
        .read(labServiceProvider)
        .watchLabTests(labClinicId: labClinicId)
        .first;
    if (!mounted) return;
    final result = await showModalBottomSheet<List<LabTestModel>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LabCatalogPickerSheet(
        allTests: allTests,
        preselected: _selectedTests,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _selectedTests
        ..clear()
        ..addAll(result);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_customer == null) {
      _snack('Pick or create a customer.', AppColors.error);
      return;
    }
    if (_selectedTests.isEmpty) {
      _snack('Select at least one test.', AppColors.error);
      return;
    }
    if (_extraDiscount > _totalTestOffer) {
      _snack(
        'Off-counter discount (₹${_extraDiscount.toStringAsFixed(0)}) '
        'exceeds test total (₹${_totalTestOffer.toStringAsFixed(0)}).',
        AppColors.error,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null || user.clinicId == null) {
        _snack('No lab linked to your account.', AppColors.error);
        return;
      }

      await ref.read(labServiceProvider).createOrder(
            referringClinicId: null,
            labClinicId: user.clinicId!,
            labName: user.clinicName ?? 'Lab',
            patientDocId:
                _customer!.sourcePatientDocId ?? _customer!.docId,
            patientId: _customer!.displayPatientId,
            patientName: _customer!.fullName,
            patientPhone: _customer!.phone,
            patientEmail: _customer!.email,
            patientGender: _customer!.gender,
            patientDob: _customer!.dob,
            patientBloodGroup: _customer!.bloodGroup,
            doctorDocId: null,
            doctorName: null,
            tests: _selectedTests
                .map((t) => LabTestItem(
                      code: t.code.isEmpty ? null : t.code,
                      name: t.name,
                      unitPrice:
                          (t.offerPrice ?? t.mrp)?.toDouble(),
                    ))
                .toList(),
            instructions: _instructionsCtrl.text.trim().isEmpty
                ? null
                : _instructionsCtrl.text.trim(),
            billableAmount: _billableAmount,
            existingCustomer: _customer,
            catalogAmount: _totalTestOffer,
            extraDiscount: _extraDiscount,
          );

      if (!mounted) return;
      _snack('Walk-in order created.', AppColors.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('New walk-in order')),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('$e')),
        data: (user) {
          final labClinicId = user?.clinicId ?? '';
          if (labClinicId.isEmpty) {
            return const Center(
                child: Text('No lab linked to this account.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Walk-in customer', style: AppTextStyles.h3),
              const SizedBox(height: 4),
              Text(
                'Search linked-clinic patients by phone, or create a new lab customer.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Customer',
                required: true,
                child: _customerPicker(),
              ),
              LabeledField(
                label: 'Tests',
                required: true,
                child: _testsPicker(labClinicId),
              ),
              const SizedBox(height: 16),
              _billableSummaryCard(),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Instructions (optional)',
                child: DarkTextField(
                  controller: _instructionsCtrl,
                  hint: 'e.g. Fasting sample, 8–10 hrs',
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                      _saving ? 'Creating...' : 'Create walk-in order'),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _billableSummaryCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Billable summary', style: AppTextStyles.label),
          const SizedBox(height: 12),
          _summaryRow('MRP', _totalMrp),
          const SizedBox(height: 6),
          _summaryRow(
            'Catalog discount',
            -_totalCatalogDiscount,
            color: AppColors.success,
          ),
          const Divider(height: 20, color: AppColors.cardBorder),
          _summaryRow('Test total (offer)', _totalTestOffer),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Off-counter discount (optional)',
            child: DarkTextField(
              controller: _extraDiscountCtrl,
              hint: '0',
            ),
          ),
          if (_extraDiscount > _totalTestOffer)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Discount exceeds test total',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.error),
              ),
            ),
          const Divider(height: 20, color: AppColors.cardBorder),
          Row(children: [
            Expanded(
              child: Text(
                'Amount to collect',
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '₹${_billableAmount.toStringAsFixed(0)}',
              style:
                  AppTextStyles.h3.copyWith(color: AppColors.primary),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {Color? color}) {
    final isNegative = value < 0;
    final display =
        '${isNegative ? "−" : ""}₹${value.abs().toStringAsFixed(0)}';
    return Row(children: [
      Expanded(
        child: Text(label, style: AppTextStyles.caption),
      ),
      Text(
        display,
        style: AppTextStyles.caption.copyWith(
          color: color ?? AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ]);
  }

  Widget _customerPicker() => GestureDetector(
        onTap: _pickCustomer,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(children: [
            const Icon(Icons.person_search_outlined,
                color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: _customer == null
                  ? const Text('Tap to find or create customer',
                      style: TextStyle(color: AppColors.textMuted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_customer!.fullName,
                            style: AppTextStyles.body),
                        Text(
                          '${_customer!.displayPatientId} • ${_customer!.phone}'
                          '${_customer!.isClinicLinked ? " • from ${_customer!.sourceClinicName}" : ""}',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      );

  Widget _testsPicker(String labClinicId) {
    if (_selectedTests.isEmpty) {
      return GestureDetector(
        onTap: () => _pickTests(labClinicId),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: const Row(children: [
            Icon(Icons.science_outlined, color: AppColors.info),
            SizedBox(width: 12),
            Expanded(
              child: Text('Tap to select tests from your catalog',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _selectedTests.map((t) {
            return Chip(
              label: Text(
                  t.code.isEmpty ? t.name : '${t.code} — ${t.name}'),
              backgroundColor: AppColors.info.withOpacity(.12),
              labelStyle: const TextStyle(
                  color: AppColors.info, fontSize: 12),
              side: BorderSide(color: AppColors.info.withOpacity(.4)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () =>
                  setState(() => _selectedTests.remove(t)),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _pickTests(labClinicId),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add more tests'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.info,
            textStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// CUSTOMER PICKER — three-mode: lookup linked / direct / link direct
// =====================================================================
class _CustomerPickerScreen extends ConsumerStatefulWidget {
  final String labClinicId;
  final String labName;
  final LabCustomerService customerSvc;

  const _CustomerPickerScreen({
    required this.labClinicId,
    required this.labName,
    required this.customerSvc,
  });

  @override
  ConsumerState<_CustomerPickerScreen> createState() =>
      _CustomerPickerScreenState();
}

class _CustomerPickerScreenState
    extends ConsumerState<_CustomerPickerScreen> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String? _query;
  List<PatientModel> _clinicMatches = const [];
  List<LabCustomerModel> _labMatches = const [];
  bool _searched = false;

  Map<String, String> _clinicNames = {};

  @override
  void initState() {
    super.initState();
    _loadClinicNames();
  }

  Future<void> _loadClinicNames() async {
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user?.clinicId == null) return;
      final linked = await ref
          .read(labServiceProvider)
          .watchLinkedClinics(user!.clinicId!)
          .first;
      final map = <String, String>{};
      for (final l in linked) {
        final cid = (l['clinicId'] ?? '').toString();
        final cname =
            (l['clinicName'] ?? l['labName'] ?? '').toString();
        if (cid.isNotEmpty && cname.isNotEmpty) map[cid] = cname;
      }
      if (mounted) setState(() => _clinicNames = map);
    } catch (_) {
      // Silent — fall back to raw ID if this fails.
    }
  }

  String _clinicLabel(String? clinicId) {
    if (clinicId == null || clinicId.isEmpty) return '';
    return _clinicNames[clinicId] ?? clinicId;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _searching = true;
      _query = q;
    });
    try {
      final clinicResults = await widget.customerSvc
          .findLinkedPatients(labClinicId: widget.labClinicId, query: q);
      final labResults = await widget.customerSvc
          .findLabCustomersByPhone(
              labClinicId: widget.labClinicId, phone: q);
      if (mounted) {
        setState(() {
          _clinicMatches = clinicResults;
          _labMatches = labResults;
          _searched = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Search failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickClinicPatient(PatientModel p) async {
    final clinicName = _clinicLabel(p.clinicId);

    try {
      final customer = await widget.customerSvc.upsertClinicLinked(
        labClinicId: widget.labClinicId,
        sourceClinicId: p.clinicId ?? '',
        sourceClinicName: clinicName,
        sourcePatientDocId: p.docId,
        sourcePatientId: p.patientId,
        fullName: p.fullName,
        phone: p.phone,
        gender: p.gender,
        email: p.email,
        dob: p.dob,
        bloodGroup: p.bloodGroup,
      );
      if (mounted) Navigator.of(context).pop(customer);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickLabCustomer(LabCustomerModel c) async {
    if (mounted) Navigator.of(context).pop(c);
  }

  Future<void> _createDirect() async {
    final created = await showModalBottomSheet<LabCustomerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewDirectCustomerSheet(
        labClinicId: widget.labClinicId,
        customerSvc: widget.customerSvc,
        initialPhone: _query ?? '',
      ),
    );
    if (created != null && mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Find or create customer'),
        actions: [
          IconButton(
            tooltip: 'New walk-in',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: _createDirect,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _search(),
              keyboardType: TextInputType.text,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by phone or email',
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textMuted),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _searching
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary))
                  : !_searched
                      ? const Center(
                          child: Text(
                            'Type a phone or email to search linked-clinic patients.\nNo match? Tap the + above to create a direct customer.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_clinicMatches.isEmpty && _labMatches.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_rounded,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('No match for "$_query"',
                style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _createDirect,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Create direct customer'),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        if (_clinicMatches.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Found in linked clinics',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          ..._clinicMatches.map((p) => Card(
                color: AppColors.surface,
                child: ListTile(
                  leading: const Icon(Icons.local_hospital_outlined,
                      color: AppColors.info),
                  title: Text(p.fullName, style: AppTextStyles.body),
                  subtitle: Text(
                    '${p.patientId} • ${p.phone}'
                    '${p.clinicId != null && p.clinicId!.isNotEmpty ? " • ${_clinicLabel(p.clinicId)}" : ""}',
                    style: AppTextStyles.caption,
                  ),
                  onTap: () => _pickClinicPatient(p),
                ),
              )),
        ],
        if (_labMatches.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Already in this lab',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          ..._labMatches.map((c) => Card(
                color: AppColors.surface,
                child: ListTile(
                  leading: const Icon(Icons.science_outlined,
                      color: AppColors.labAccent),
                  title: Text(c.fullName, style: AppTextStyles.body),
                  subtitle: Text(
                    '${c.displayPatientId} • ${c.phone}'
                    '${c.isClinicLinked ? " • from ${c.sourceClinicName}" : " • direct"}',
                    style: AppTextStyles.caption,
                  ),
                  onTap: () => _pickLabCustomer(c),
                ),
              )),
        ],
      ],
    );
  }
}

// =====================================================================
// NEW DIRECT CUSTOMER FORM — email is required (needed for patient
// signup to match this record)
// =====================================================================
class _NewDirectCustomerSheet extends StatefulWidget {
  final String labClinicId;
  final LabCustomerService customerSvc;
  final String initialPhone;

  const _NewDirectCustomerSheet({
    required this.labClinicId,
    required this.customerSvc,
    required this.initialPhone,
  });

  @override
  State<_NewDirectCustomerSheet> createState() =>
      _NewDirectCustomerSheetState();
}

class _NewDirectCustomerSheetState
    extends State<_NewDirectCustomerSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _referredDoctorCtrl = TextEditingController();
  final _referredClinicCtrl = TextEditingController();
  String _gender = 'male';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.initialPhone;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _referredDoctorCtrl.dispose();
    _referredClinicCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.length < 3) {
      _snack('Enter a full name (min 3 characters).');
      return;
    }
    if (phone.length < 6) {
      _snack('Enter a valid phone.');
      return;
    }
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _snack('Enter a valid email. The patient needs this to sign up '
          'and view their reports.');
      return;
    }

    setState(() => _saving = true);
    try {
      final c = await widget.customerSvc.createDirect(
        labClinicId: widget.labClinicId,
        fullName: name,
        phone: phone,
        gender: _gender,
        email: email,
        referredByName: _referredDoctorCtrl.text.trim().isEmpty
            ? null
            : _referredDoctorCtrl.text.trim(),
        referredByClinicName: _referredClinicCtrl.text.trim().isEmpty
            ? null
            : _referredClinicCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(c);
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text('New direct customer', style: AppTextStyles.h3),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                children: [
                  LabeledField(
                    label: 'Full name',
                    required: true,
                    child: DarkTextField(
                      controller: _nameCtrl,
                      hint: 'e.g. Rahul Mehta',
                    ),
                  ),
                  LabeledField(
                    label: 'Phone',
                    required: true,
                    child: DarkTextField(
                      controller: _phoneCtrl,
                      hint: 'e.g. 9545831585',
                    ),
                  ),
                  LabeledField(
                    label: 'Email',
                    required: true,
                    child: DarkTextField(
                      controller: _emailCtrl,
                      hint: 'e.g. rahul@gmail.com',
                    ),
                  ),
                  LabeledField(
                    label: 'Gender',
                    required: true,
                    child: DropdownButtonFormField<String>(
                      value: _gender,
                      dropdownColor: AppColors.surfaceElevated,
                      items: const [
                        DropdownMenuItem(
                            value: 'male', child: Text('Male')),
                        DropdownMenuItem(
                            value: 'female', child: Text('Female')),
                        DropdownMenuItem(
                            value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) =>
                          setState(() => _gender = v ?? 'male'),
                    ),
                  ),
                  LabeledField(
                    label: 'Referred by doctor (optional, free text)',
                    child: DarkTextField(
                      controller: _referredDoctorCtrl,
                      hint: 'e.g. Dr. Anil Shah',
                    ),
                  ),
                  LabeledField(
                    label: 'Referred by clinic (optional, free text)',
                    child: DarkTextField(
                      controller: _referredClinicCtrl,
                      hint: 'e.g. Sunrise Hospital',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// CATALOG PICKER — selects LabTestModel objects directly.
// =====================================================================
class _LabCatalogPickerSheet extends StatefulWidget {
  final List<LabTestModel> allTests;
  final List<LabTestModel> preselected;

  const _LabCatalogPickerSheet({
    required this.allTests,
    required this.preselected,
  });

  @override
  State<_LabCatalogPickerSheet> createState() =>
      _LabCatalogPickerSheetState();
}

class _LabCatalogPickerSheetState extends State<_LabCatalogPickerSheet> {
  late final List<LabTestModel> _selected;
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _selected = [...widget.preselected];
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isSelected(LabTestModel t) => _selected.contains(t);

  void _toggle(LabTestModel t) {
    setState(() {
      if (_selected.contains(t)) {
        _selected.remove(t);
      } else {
        _selected.add(t);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.allTests
        : widget.allTests.where((t) {
            final s = _q.toLowerCase();
            return t.code.toLowerCase().contains(s) ||
                t.name.toLowerCase().contains(s);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text('Select tests', style: AppTextStyles.h3),
                const Spacer(),
                Text('${_selected.length} selected',
                    style: AppTextStyles.caption),
              ]),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search by code or name',
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No tests match',
                          style: TextStyle(
                              color: AppColors.textMuted)))
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final t = filtered[i];
                        return CheckboxListTile(
                          value: _isSelected(t),
                          onChanged: (_) => _toggle(t),
                          title: Text(
                              t.code.isEmpty
                                  ? t.name
                                  : '${t.code} — ${t.name}',
                              style: AppTextStyles.body),
                          subtitle: t.sampleType.isNotEmpty
                              ? Text(t.sampleType,
                                  style: AppTextStyles.caption)
                              : null,
                          activeColor: AppColors.info,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selected),
                  child: Text(
                      'Add ${_selected.length} test${_selected.length == 1 ? '' : 's'}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}