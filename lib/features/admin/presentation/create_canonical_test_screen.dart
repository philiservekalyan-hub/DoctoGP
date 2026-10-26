// lib/features/admin/presentation/create_canonical_test_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_test_model.dart';
import '../../../core/services/canonical_test_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class CreateCanonicalTestScreen extends ConsumerStatefulWidget {
  final CanonicalTestModel? existing;
  const CreateCanonicalTestScreen({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  ConsumerState<CreateCanonicalTestScreen> createState() =>
      _CreateCanonicalTestScreenState();
}

class _CreateCanonicalTestScreenState
    extends ConsumerState<CreateCanonicalTestScreen> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _turnaroundCtrl = TextEditingController();
  final _loincCtrl = TextEditingController();

  LabTestCategory _category = LabTestCategory.biochemistry;
  LabSampleType _sampleType = LabSampleType.blood;
  bool _fastingRequired = false;
  bool _active = true;

  bool _saving = false;
  String? _codeError;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _codeCtrl.text = e.code;
      _nameCtrl.text = e.name;
      _descCtrl.text = e.description ?? '';
      _turnaroundCtrl.text = e.turnaroundHint ?? '';
      _loincCtrl.text = e.loincCode ?? '';
      _category = e.category;
      _sampleType = e.sampleType;
      _fastingRequired = e.fastingRequired;
      _active = e.active;
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _turnaroundCtrl.dispose();
    _loincCtrl.dispose();
    super.dispose();
  }

  bool _validCode(String s) =>
      RegExp(r'^[A-Z0-9_]{2,12}$').hasMatch(s);

  Future<void> _save() async {
    setState(() {
      _codeError = null;
      _nameError = null;
    });

    final code = _codeCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();

    if (!_validCode(code)) {
      setState(() => _codeError =
          'Code must be 2–12 characters: A–Z, 0–9, underscore.');
      return;
    }
    if (name.length < 3) {
      setState(() => _nameError = 'Name must be at least 3 characters.');
      return;
    }

    setState(() => _saving = true);
    try {
      final svc = ref.read(canonicalTestServiceProvider);

      if (widget.isEdit) {
        await svc.update(
          testId: widget.existing!.testId,
          name: name,
          category: _category,
          sampleType: _sampleType,
          fastingRequired: _fastingRequired,
          active: _active,
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          turnaroundHint: _turnaroundCtrl.text.trim().isEmpty
              ? null
              : _turnaroundCtrl.text.trim(),
          loincCode: _loincCtrl.text.trim().isEmpty
              ? null
              : _loincCtrl.text.trim(),
        );
        if (!mounted) return;
        _snack('Test updated.', AppColors.success);
        Navigator.of(context).pop();
        return;
      }

      final res = await svc.create(
        code: code,
        name: name,
        category: _category,
        sampleType: _sampleType,
        fastingRequired: _fastingRequired,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        turnaroundHint: _turnaroundCtrl.text.trim().isEmpty
            ? null
            : _turnaroundCtrl.text.trim(),
        loincCode: _loincCtrl.text.trim().isEmpty
            ? null
            : _loincCtrl.text.trim(),
      );

      if (!mounted) return;
      switch (res.result) {
        case CanonicalTestWriteResult.success:
          _snack('Test created.', AppColors.success);
          Navigator.of(context).pop();
          break;
        case CanonicalTestWriteResult.duplicateCode:
          setState(() => _codeError =
              'Code already exists: "${res.existingName ?? ''}".');
          break;
        case CanonicalTestWriteResult.invalidCodeFormat:
          setState(() => _codeError = 'Invalid code format.');
          break;
        case CanonicalTestWriteResult.invalidNameLength:
          setState(() => _nameError = 'Invalid name length.');
          break;
      }
    } catch (e) {
      if (mounted) _snack('Save failed: $e', AppColors.error);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(
        title: widget.isEdit ? 'Edit test' : 'New test',
        showBackButton: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _label('Code'),
            _input(
              controller: _codeCtrl,
              hint: 'e.g. CBC',
              enabled: !widget.isEdit,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[A-Za-z0-9_]')),
                LengthLimitingTextInputFormatter(12),
                _UpperCaseFormatter(),
              ],
              errorText: _codeError,
            ),
            if (widget.isEdit)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Code is immutable. Create a new test if you need a '
                  'different code.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ),

            _label('Name'),
            _input(
              controller: _nameCtrl,
              hint: 'e.g. Complete Blood Count',
              errorText: _nameError,
            ),

            _label('Category'),
            _dropdown<LabTestCategory>(
              value: _category,
              items: LabTestCategory.values,
              itemLabel: (c) => c.label,
              onChanged: (v) => setState(() => _category = v!),
            ),

            _label('Sample type'),
            _dropdown<LabSampleType>(
              value: _sampleType,
              items: LabSampleType.values,
              itemLabel: (s) => s.label,
              onChanged: (v) => setState(() => _sampleType = v!),
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

            if (widget.isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Active', style: AppTextStyles.body),
                subtitle: Text(
                  'Inactive tests are hidden from the doctor picker '
                  'and lab offerings.',
                  style: AppTextStyles.caption,
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                activeColor: AppColors.primary,
              ),

            _label('Description (optional)'),
            _input(
              controller: _descCtrl,
              hint: 'Clinical description, if helpful',
              maxLines: 3,
            ),

            _label('Turnaround hint (optional)'),
            _input(
              controller: _turnaroundCtrl,
              hint: 'e.g. 4h, 24h',
            ),

            _label('LOINC code (optional)'),
            _input(
              controller: _loincCtrl,
              hint: 'e.g. 58410-2',
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(widget.isEdit ? 'Save changes' : 'Create test'),
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
    bool enabled = true,
    int maxLines = 1,
    String? errorText,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return GlassCard(
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
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

/// Forces input to uppercase as the admin types the code.
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