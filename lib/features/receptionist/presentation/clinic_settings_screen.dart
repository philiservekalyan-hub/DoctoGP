import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/models/clinic_model.dart';
import '../../../core/services/clinic_service.dart';
import '../../../core/widgets/labeled_field.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class ClinicSettingsScreen extends ConsumerStatefulWidget {
  const ClinicSettingsScreen({super.key});

  @override
  ConsumerState<ClinicSettingsScreen> createState() =>
      _ClinicSettingsScreenState();
}

class _ClinicSettingsScreenState
    extends ConsumerState<ClinicSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();

  String? _logoLocalPath;
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _prefill(ClinicModel clinic) {
    if (_initialized) return;
    _name.text = clinic.name;
    _address.text = clinic.address ?? '';
    _phone.text = clinic.phone ?? '';
    _initialized = true;
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _logoLocalPath = picked.path);
    }
  }

  Future<void> _save(String clinicId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      String? logoUrl;
      if (_logoLocalPath != null) {
        logoUrl = await ref.read(clinicServiceProvider).uploadLogo(
              clinicId: clinicId,
              localPath: _logoLocalPath!,
            );
      }

      await ref.read(clinicServiceProvider).updateClinic(clinicId, {
        'name': _name.text.trim(),
        'address': _address.text.trim().isEmpty
            ? null
            : _address.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        if (logoUrl != null) 'logoUrl': logoUrl,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clinic settings updated'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
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
    final clinicAsync = ref.watch(currentClinicProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(
        title: 'Clinic Settings',
        showBackButton: true,
      ),
      body: clinicAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (clinic) {
          if (clinic == null) {
            return const Center(
              child: Text('Clinic not found',
                  style: TextStyle(color: AppColors.textMuted)),
            );
          }
          _prefill(clinic);

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickLogo,
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: AppColors.cardBorder),
                            image: _logoLocalPath != null
                                ? DecorationImage(
                                    image: FileImage(
                                        File(_logoLocalPath!)),
                                    fit: BoxFit.cover,
                                  )
                                : clinic.logoUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(
                                            clinic.logoUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                          ),
                          child: _logoLocalPath == null &&
                                  clinic.logoUrl == null
                              ? const Icon(
                                  Icons.local_hospital_rounded,
                                  color: AppColors.primary,
                                  size: 40)
                              : null,
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                                Icons.camera_alt_rounded,
                                color: AppColors.background,
                                size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                LabeledField(
                  label: 'Clinic Name',
                  required: true,
                  child: DarkTextField(
                    controller: _name,
                    hint: 'e.g. Sharma Family Clinic',
                    icon: Icons.local_hospital_outlined,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                ),
                LabeledField(
                  label: 'Address',
                  child: DarkTextField(
                    controller: _address,
                    hint: 'Street, area, city',
                    maxLines: 2,
                    icon: Icons.location_on_outlined,
                  ),
                ),
                LabeledField(
                  label: 'Phone',
                  child: DarkTextField(
                    controller: _phone,
                    hint: '+91 80 4567 8900',
                    keyboardType: TextInputType.phone,
                    icon: Icons.phone_outlined,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _save(clinic.id),
                    child:
                        Text(_saving ? 'Saving...' : 'Save Changes'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}