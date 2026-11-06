// lib/features/lab/presentation/local_test_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_test_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';

class LocalTestEditorScreen extends ConsumerStatefulWidget {
  final String labClinicId;
  const LocalTestEditorScreen({super.key, required this.labClinicId});

  @override
  ConsumerState<LocalTestEditorScreen> createState() =>
      _LocalTestEditorScreenState();
}

class _LocalTestEditorScreenState
    extends ConsumerState<LocalTestEditorScreen> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _mrpCtrl = TextEditingController();
  final _offerCtrl = TextEditingController();
  final _tatCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  LabTestCategory _category = LabTestCategory.biochemistry;
  LabSampleType _sampleType = LabSampleType.blood;
  bool _fastingRequired = false;
  bool _saving = false;
  String? _codeError;
  String? _nameError;
  String? _mrpError;
  String? _offerError;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _mrpCtrl.dispose();
    _offerCtrl.dispose();
    _tatCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool _validCode(String s) =>
      RegExp(r'^[A-Z0-9_]{2,12}$').hasMatch(s);

  Future<void> _save() async {
    setState(() {
      _codeError = null;
      _nameError = null;
      _mrpError = null;
      _offerError = null;
    });

    final code = _codeCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    final mrp = double.tryParse(_mrpCtrl.text.trim());
    final offerRaw = _offerCtrl.text.trim();
    final offer =
        offerRaw.isEmpty ? null : double.tryParse(offerRaw);

    var hasError = false;
    if (!_validCode(code)) {
      setState(() => _codeError =
          'Code must be 2–12 characters: A–Z, 0–9, underscore.');
      hasError = true;
    }
    if (name.length < 3) {
      setState(() => _nameError = 'Name must be at least 3 characters.');
      hasError = true;
    }
    if (mrp == null || mrp <= 0) {
      setState(() => _mrpError = 'Enter MRP greater than 0.');
      hasError = true;
    }
    if (offerRaw.isNotEmpty && (offer == null || offer <= 0)) {
      setState(() =>
          _offerError = 'Enter a valid offer price or leave blank.');
      hasError = true;
    }
    if (offer != null && mrp != null && offer > mrp) {
      setState(() => _offerError = 'Offer price cannot exceed MRP.');
      hasError = true;
    }
    if (hasError) return;

    setState(() => _saving = true);
    try {
      await ref.read(labServiceProvider).createLocalTest(
            labClinicId: widget.labClinicId,
            code: code,
            name: name,
            category: _category.name,
            sampleType: _sampleType.name,
            fastingRequired: _fastingRequired,
            turnaroundHours: int.tryParse(_tatCtrl.text.trim()),
            mrp: mrp!,
            offerPrice: offer,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Local test created.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mrp = double.tryParse(_mrpCtrl.text.trim());
    final offer = double.tryParse(_offerCtrl.text.trim());
    final effectiveOffer = offer ?? mrp;
    final hasDiscount = mrp != null &&
        effectiveOffer != null &&
        mrp > 0 &&
        effectiveOffer < mrp;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Create local test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GlassCard(
              borderColor: AppColors.warning.withOpacity(.35),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Local tests are visible only to your linked '
                    'clinics. They appear in the master catalogue '
                    'tagged with your lab name.',
                    style: AppTextStyles.caption,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            _label('Code'),
            _input(
              controller: _codeCtrl,
              hint: 'e.g. AMYLASE_INH',
              errorText: _codeError,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[A-Za-z0-9_]')),
                LengthLimitingTextInputFormatter(12),
                _UpperCaseFormatter(),
              ],
            ),

            _label('Name'),
            _input(
              controller: _nameCtrl,
              hint: 'e.g. Pancreatic Amylase (in-house)',
              errorText: _nameError,
            ),

            _label('Category'),
            _dropdown<LabTestCategory>(
              value: _category,
              items: LabTestCategory.values,
              itemLabel: (c) => c.label,
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),

            _label('Sample type'),
            _dropdown<LabSampleType>(
              value: _sampleType,
              items: LabSampleType.values,
              itemLabel: (s) => s.label,
              onChanged: (v) {
                if (v != null) setState(() => _sampleType = v);
              },
            ),

            _label('MRP (₹)'),
            _input(
              controller: _mrpCtrl,
              hint: 'e.g. 500',
              errorText: _mrpError,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
            ),

            _label('Offer price (₹, optional)'),
            _input(
              controller: _offerCtrl,
              hint: 'Leave blank for no discount',
              errorText: _offerError,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
            ),

            if (hasDiscount)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.local_offer_rounded,
                        color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '₹${mrp.toStringAsFixed(0)} → ₹${effectiveOffer!.toStringAsFixed(0)}'
                      '  •  ${((mrp - effectiveOffer) / mrp * 100).round()}% off',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              ),

            _label('Turnaround hours (optional)'),
            _input(
              controller: _tatCtrl,
              hint: 'e.g. 24',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),

            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Fasting required',
                  style: AppTextStyles.body),
              value: _fastingRequired,
              onChanged: (v) =>
                  setState(() => _fastingRequired = v),
              activeColor: AppColors.primary,
            ),

            _label('Notes for clinic (optional)'),
            _input(
              controller: _notesCtrl,
              hint: 'e.g. Only run on weekdays',
              maxLines: 3,
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create local test'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(s, style: AppTextStyles.caption),
      );

  Widget _input({
    required TextEditingController controller,
    required String hint,
    String? errorText,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    return GlassCard(
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        style: AppTextStyles.body,
        decoration: InputDecoration(
          hintText: hint,
          errorText: errorText,
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return GlassCard(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          style: AppTextStyles.body,
          items: items
              .map((t) => DropdownMenuItem<T>(
                    value: t,
                    child: Text(itemLabel(t)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}