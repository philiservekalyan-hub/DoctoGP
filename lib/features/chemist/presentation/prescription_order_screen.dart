// lib/features/chemist/presentation/prescription_order_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/chemist_model.dart';
import '../../../core/models/consultation_model.dart';
import '../../../core/models/prescription_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import 'patient_order_tracking_screen.dart';
import '../../../core/utils/contact_utils.dart';
import '../../patient/presentation/patient_dashboard.dart'
    show currentPatientProvider;

/// Fetch pharmacies that can deliver to the supplied pincode.
/// Declared outside the widget so Riverpod can keep a stable provider identity.
final nearbyChemistsProvider =
    FutureProvider.autoDispose.family<List<ChemistModel>, String>(
  (ref, pincode) async {
    final normalizedPincode = pincode.trim();
    if (normalizedPincode.isEmpty) return <ChemistModel>[];

    return ref
        .read(chemistServiceProvider)
        .fetchChemistsForPincode(normalizedPincode);
  },
);

/// Watch pharmacies saved by this patient.
final patientChemistsProvider =
    StreamProvider.autoDispose.family<List<ChemistModel>, String>(
  (ref, patientDocId) {
    if (patientDocId.trim().isEmpty) {
      return Stream<List<ChemistModel>>.value(<ChemistModel>[]);
    }

    return ref
        .read(chemistServiceProvider)
        .watchPatientChemists(patientDocId);
  },
);

class _DraftItem {
  final Medication med;
  int quantity;
  _DraftItem(this.med) : quantity = 1;
}

class PrescriptionOrderScreen extends ConsumerStatefulWidget {
  // Both nullable to support the refill flow (no appointment).
  final AppointmentModel? appointment;
  final ConsultationModel? consultation;
  const PrescriptionOrderScreen({
    super.key,
    this.appointment,
    this.consultation,
  });

  @override
  ConsumerState<PrescriptionOrderScreen> createState() =>
      _PrescriptionOrderScreenState();
}

class _PrescriptionOrderScreenState
    extends ConsumerState<PrescriptionOrderScreen> {
  late List<_DraftItem> _items;
  ChemistModel? _selectedChemist;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _pincodeCtrl;
  final _deliveryNotesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();

    // If a consultation is provided, use its medications.
    // Otherwise, fall back to the patient's current medications
    // (which may be empty — the patient can still add items).
    if (widget.consultation != null) {
      _items = widget.consultation!.medications
          .map((m) => _DraftItem(m))
          .toList();
    } else {
      final patient = ref.read(currentPatientProvider).valueOrNull ?? {};
      final rawMeds = patient['currentMedications'];
      final meds = <_DraftItem>[];
      if (rawMeds is List) {
        for (final entry in rawMeds) {
          if (entry is Map) {
            final name = (entry['name'] ?? '').toString().trim();
            if (name.isEmpty) continue;
            meds.add(_DraftItem(Medication(
              name: name,
              dose: (entry['dose'] ?? '').toString(),
              frequency: (entry['frequency'] ?? '').toString(),
              duration: (entry['duration'] ?? '').toString(),
            )));
          }
        }
      }
      _items = meds;
    }

    final patient = ref.read(currentPatientProvider).valueOrNull ?? {};
    final addr = [
      (patient['address'] ?? '').toString(),
      (patient['city'] ?? '').toString(),
    ].where((s) => s.trim().isNotEmpty).join(', ');
    _addressCtrl = TextEditingController(text: addr);
    _pincodeCtrl =
        TextEditingController(text: (patient['pincode'] ?? '').toString());
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _pincodeCtrl.dispose();
    _deliveryNotesCtrl.dispose();
    super.dispose();
  }

  void _showContactSheet(ChemistModel c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contact ${c.name}', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            if (c.fullAddress.isNotEmpty)
              Text(c.fullAddress, style: AppTextStyles.caption),
            const SizedBox(height: 12),
            if (c.phone.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_rounded,
                    color: AppColors.info),
                title: Text(c.phone, style: AppTextStyles.body),
                subtitle:
                    Text('Tap to call', style: AppTextStyles.caption),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await callNumber(c.phone);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open dialer.'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                },
              ),
            if (c.phone.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.chat_rounded,
                    color: AppColors.success),
                title: const Text('WhatsApp'),
                subtitle: Text('Message ${c.name}',
                    style: AppTextStyles.caption),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await whatsappNumber(
                    c.phone,
                    message:
                        'Hi, I have a question about my prescription on STAT.',
                  );
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open WhatsApp.'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMedicine() async {
  final nameCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');

  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add an item', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            Text(
              'Add any product to this order — a medicine, supplement, '
              'or health product.',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Product name',
                hintText: 'e.g. Paracetamol 500 mg, Vitamin D3, toothbrush',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
                    if (qty < 1) return;
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text('Add to order'),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );

  if (added == true) {
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
    final newItem = _DraftItem(
      Medication(
        name: nameCtrl.text.trim(),
        dose: '',
        frequency: '',
        duration: notesCtrl.text.trim(),
      ),
    );
    newItem.quantity = qty < 1 ? 1 : qty;
    setState(() => _items.add(newItem));
  }

  // Defer disposal until after the sheet's close animation finishes.
  // Disposing while the sheet is still animating out triggers
  // "TextEditingController was used after being disposed".
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 500), () {
      nameCtrl.dispose();
      notesCtrl.dispose();
      qtyCtrl.dispose();
    });
  });
}

  Future<void> _submit() async {
    if (_selectedChemist == null) {
      _toast('Select a chemist to place the order.', AppColors.error);
      return;
    }
    final patient = ref.read(currentPatientProvider).valueOrNull;
    if (patient == null) {
      _toast('Patient profile not found.', AppColors.error);
      return;
    }
    final included = _items.where((i) => i.quantity > 0).toList();
    if (included.isEmpty) {
      _toast('Add at least one medicine.', AppColors.error);
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      _toast('Please enter a delivery address.', AppColors.error);
      return;
    }
    setState(() => _submitting = true);
    try {
      final patientDobRaw = (patient['dob'] ?? '').toString();
      final dob = DateTime.tryParse(patientDobRaw);
      final ageYears = dob == null
          ? null
          : (DateTime.now().difference(dob).inDays / 365.25).floor();

      // Null-safe clinic lookup.
      final clinicId = widget.appointment?.clinicId ??
          (patient['clinicId'] ?? '').toString();
      String? clinicName;
      if (clinicId.isNotEmpty) {
        try {
          final clinicDoc = await FirebaseFirestore.instance
              .collection('clinics')
              .doc(clinicId)
              .get();
          clinicName =
              (clinicDoc.data()?['name'] ?? '').toString().isEmpty
                  ? null
                  : clinicDoc.data()!['name'].toString();
        } catch (_) {}
      }

      final orderId = await ref.read(chemistServiceProvider).placeOrder(
            patientDocId: patient['patientDocId'] as String,
            patientId: (patient['patientId'] ?? '').toString(),
            patientName: (patient['fullName'] ?? 'Patient').toString(),
            patientPhone: (patient['phone'] ?? '').toString(),
            patientAgeYears: ageYears,
            patientGender: (patient['gender'] ?? '').toString().isEmpty
                ? null
                : patient['gender'].toString(),
            deliveryAddress: _addressCtrl.text.trim(),
            deliveryNotes: _deliveryNotesCtrl.text.trim().isEmpty
                ? null
                : _deliveryNotesCtrl.text.trim(),
            consultationDocId: widget.consultation?.docId ?? 'refill',
            appointmentDocId: widget.appointment?.docId ?? '',
            doctorDocId: widget.appointment?.doctorDocId ?? '',
            doctorName: widget.appointment?.doctorName ?? '',
            doctorRegistrationNumber: null,
            doctorQualification: null,
            clinicId: clinicId,
            clinicName: clinicName,
            diagnosis: widget.consultation?.diagnosisText
                        ?.trim()
                        .isNotEmpty ==
                    true
                ? widget.consultation!.diagnosisText!.trim()
                : (widget.consultation?.diagnosis?.trim().isNotEmpty == true
                    ? widget.consultation!.diagnosis!.trim()
                    : null),
            rxFreeText:
                widget.consultation?.rx?.trim().isEmpty ?? true
                    ? null
                    : widget.consultation!.rx!.trim(),
            prescriptionDate: widget.consultation?.endedAt ??
                widget.appointment?.slot ??
                DateTime.now(),
            chemist: _selectedChemist!,
            items: included
                .map((i) => PrescriptionOrderItem(
                      name: i.med.name,
                      dose: i.med.dose,
                      frequency: i.med.frequency,
                      duration: i.med.duration,
                      quantity: i.quantity,
                    ))
                .toList(),
          );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PatientOrderTrackingScreen(orderId: orderId),
        ),
      );
    } catch (e) {
      if (mounted) _toast('Could not place order: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String m, Color c) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  @override
  Widget build(BuildContext context) {
    final patient = ref.watch(currentPatientProvider).valueOrNull;
    final patientDocId = (patient?['patientDocId'] ?? '').toString();
    final patientPincode = (patient?['pincode'] ?? '').toString().trim();

    final typedPincode = _pincodeCtrl.text.trim();
    final effectivePincode =
        typedPincode.isNotEmpty ? typedPincode : patientPincode;

    final myPharmaciesAsync =
        ref.watch(patientChemistsProvider(patientDocId));

    final nearbyAsync =
        ref.watch(nearbyChemistsProvider(effectivePincode));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Order prescription', style: AppTextStyles.h3),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            _section(
              title: widget.consultation != null
                  ? 'Prescription & Items'
                  : 'Items',
              icon: Icons.shopping_bag_rounded,
              color: AppColors.patientAccent,
              child: Column(
                children: [
                  ..._items.map((i) => _itemRow(i)).toList(),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addMedicine,
                      icon: const Icon(Icons.add_shopping_cart_rounded,
                          size: 16),
                      label: const Text('Add another item'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.patientAccent,
                        side: const BorderSide(
                            color: AppColors.patientAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _section(
              title: 'Delivery',
              icon: Icons.location_on_rounded,
              color: AppColors.info,
              child: Column(
                children: [
                  TextField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      hintText: 'House, street, landmark',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pincodeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Delivery pincode',
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _deliveryNotesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Delivery notes (optional)',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _section(
              title: 'Your pharmacies',
              icon: Icons.bookmark_rounded,
              color: AppColors.success,
              child: myPharmaciesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Unable to load: $e',
                    style: const TextStyle(color: AppColors.error)),
                data: (list) {
                  if (list.isEmpty) {
                    return Text(
                      'You haven\'t saved any pharmacies yet. '
                      'Pick one from "Available near you" below.',
                      style: AppTextStyles.bodyMuted,
                    );
                  }
                  return Column(
                    children: list
                        .map((c) => _chemistTile(c, effectivePincode))
                        .toList(),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            _section(
              title: 'Available near you',
              icon: Icons.near_me_rounded,
              color: AppColors.info,
              child: nearbyAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Unable to load: $e',
                    style: const TextStyle(color: AppColors.error)),
                data: (list) {
                  if (list.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          effectivePincode.isEmpty
                              ? 'Enter your delivery pincode to see '
                                  'pharmacies that can deliver to you.'
                              : 'No pharmacies deliver to $effectivePincode yet.',
                          style: AppTextStyles.bodyMuted,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openSearchSheet(),
                            icon: const Icon(Icons.search_rounded,
                                size: 16),
                            label: const Text(
                                'Search by another pincode'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.info,
                              side: const BorderSide(
                                  color: AppColors.info),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      ...list.map(
                          (c) => _chemistTile(c, effectivePincode)),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => _openSearchSheet(),
                          icon: const Icon(Icons.search_rounded,
                              size: 16),
                          label:
                              const Text('Search by another pincode'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_submitting ? 'Placing order…' : 'Place order'),
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) =>
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 9),
              Text(title, style: AppTextStyles.h3),
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _itemRow(_DraftItem item) {
    final excluded = item.quantity == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.med.name,
                    style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: excluded
                            ? AppColors.textMuted
                            : AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  [item.med.dose, item.med.frequency, item.med.duration]
                      .where((s) => s.trim().isNotEmpty)
                      .join(' • '),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: excluded
                ? null
                : () => setState(() => item.quantity = item.quantity - 1),
            icon: const Icon(Icons.remove_circle_outline_rounded),
            color: AppColors.textMuted,
          ),
          SizedBox(
            width: 28,
            child: Text('${item.quantity}',
                textAlign: TextAlign.center, style: AppTextStyles.h3),
          ),
          IconButton(
            onPressed: () => setState(() => item.quantity = item.quantity + 1),
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _chemistTile(ChemistModel c, String patientPincode) {
    final selected = c.docId == _selectedChemist?.docId;
    final match = c.matchDelivery(patientPincode);

    final (statusText, statusColor, statusIcon) = switch (match) {
      DeliveryMatch.delivers => (
          'Delivers to your pincode',
          AppColors.success,
          Icons.check_circle_rounded
        ),
      DeliveryMatch.outside => (
          'Outside delivery area — pickup only',
          AppColors.warning,
          Icons.info_rounded
        ),
      DeliveryMatch.pickupOnly => (
          'Pickup only — ${c.pincode}',
          AppColors.info,
          Icons.store_rounded
        ),
      DeliveryMatch.unknown => (
          'Enter pincode to check',
          AppColors.textMuted,
          Icons.help_outline_rounded
        ),
    };

    final feeLabel = c.deliveryAvailable
        ? (c.deliveryFee > 0
            ? 'Delivery ₹${c.deliveryFee.toStringAsFixed(0)}'
            : 'Free delivery')
        : 'No delivery';
    final radiusLabel = c.deliveryAvailable && c.deliveryRadiusKm > 0
        ? ' · ${c.deliveryRadiusKm.toStringAsFixed(0)} km'
        : '';
    final discountLabel =
        c.discountPercent != null && c.discountPercent! > 0
            ? ' · ${c.discountPercent!.toStringAsFixed(0)}% off'
            : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedChemist = c),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color:
                        selected ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name,
                            style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.w600)),
                        if (c.fullAddress.isNotEmpty)
                          Text(c.fullAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  if (c.phone.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'Contact chemist',
                      icon: const Icon(Icons.phone_rounded,
                          color: AppColors.info, size: 20),
                      onPressed: () => _showContactSheet(c),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      statusText,
                      style: AppTextStyles.caption
                          .copyWith(color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text('$feeLabel$radiusLabel$discountLabel',
                  style: AppTextStyles.caption),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSearchSheet() async {
    final result = await showModalBottomSheet<ChemistModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) =>
          _ChemistSearchSheet(initialPincode: _pincodeCtrl.text.trim()),
    );
    if (result == null) return;
    setState(() => _selectedChemist = result);
    final patient = ref.read(currentPatientProvider).valueOrNull;
    final patientDocId = patient?['patientDocId'] as String?;
    if (patientDocId != null) {
      try {
        await ref.read(chemistServiceProvider).addChemistToPatient(
              patientDocId: patientDocId,
              chemistDocId: result.docId,
            );
      } catch (_) {}
    }
  }
}

class _ChemistSearchSheet extends ConsumerStatefulWidget {
  final String initialPincode;
  const _ChemistSearchSheet({this.initialPincode = ''});

  @override
  ConsumerState<_ChemistSearchSheet> createState() =>
      _ChemistSearchSheetState();
}

class _ChemistSearchSheetState extends ConsumerState<_ChemistSearchSheet> {
  late final TextEditingController _ctrl;
  List<ChemistModel> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialPincode);
    if (widget.initialPincode.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final pincode = _ctrl.text.trim();
    if (pincode.length != 6) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final results = await ref
          .read(chemistServiceProvider)
          .searchChemists(pincode: pincode);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search by pincode', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Pincode',
              counterText: '',
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _search,
              icon: const Icon(Icons.search_rounded),
              label: Text(_loading ? 'Searching…' : 'Search'),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_searched && _results.isEmpty)
            Text('No pharmacies deliver to that pincode.',
                style: AppTextStyles.bodyMuted)
          else
            ..._results.map(
              (c) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_pharmacy_rounded,
                    color: AppColors.success),
                title: Text(c.name, style: AppTextStyles.body),
                subtitle: Text(
                  '${c.fullAddress} · '
                  '${c.deliveryAvailable ? 'Delivery' : 'Pickup only'}'
                  '${c.deliveryFee > 0 ? ' · ₹${c.deliveryFee.toStringAsFixed(0)}' : ''}',
                  style: AppTextStyles.caption,
                ),
                onTap: () => Navigator.pop(context, c),
              ),
            ),
        ],
      ),
    );
  }
}