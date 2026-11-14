// lib/features/patient/presentation/emergency_contact_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';
import 'patient_dashboard.dart';

class EmergencyContactScreen extends ConsumerStatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  ConsumerState<EmergencyContactScreen> createState() =>
      _EmergencyContactScreenState();
}

class _EmergencyContactScreenState
    extends ConsumerState<EmergencyContactScreen> {
  final _name = TextEditingController();
  final _relationship = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  bool _smsOptIn = true;
  bool _consentAttested = false;
  bool _saving = false;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Prefill once, from the currently-cached contact if present.
    if (_prefilled) return;
    final existing = ref.read(patientEmergencyContactProvider).valueOrNull;
    if (existing != null) {
      _name.text = (existing['name'] ?? '').toString();
      _relationship.text = (existing['relationship'] ?? '').toString();
      _phone.text = (existing['phone'] ?? '').toString();
      _email.text = (existing['email'] ?? '').toString();
      _smsOptIn = existing['smsOptIn'] == true;
      _consentAttested = existing['consentGivenAt'] != null;
    }
    _prefilled = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _relationship.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      return _snack('Enter the contact name', AppColors.error);
    }
    if (_phone.text.trim().length < 8) {
      return _snack('Enter a valid phone number', AppColors.error);
    }
    if (!_consentAttested) {
      return _snack(
        'Please confirm you have this person\'s permission',
        AppColors.error,
      );
    }

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw 'Not signed in';

      final patient = ref.read(currentPatientProvider).valueOrNull;
      final patientDocId = patient?['patientDocId'] as String?;
      if (patientDocId == null) throw 'Patient record not found';

      final db = FirebaseFirestore.instance;
      final existing =
          ref.read(patientEmergencyContactProvider).valueOrNull;

      final payload = <String, dynamic>{
        'patientDocId': patientDocId,
        'patientAuthUid': uid,
        'clinicId': patient?['clinicId'],
        'name': _name.text.trim(),
        'relationship': _relationship.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'smsOptIn': _smsOptIn,
        'consentGivenAt': FieldValue.serverTimestamp(),
        'consentVersion': '1.0',
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (existing != null && existing['contactDocId'] != null) {
        await db
            .collection('emergencyContacts')
            .doc(existing['contactDocId'] as String)
            .update(payload);
      } else {
        payload['createdAt'] = FieldValue.serverTimestamp();
        await db.collection('emergencyContacts').add(payload);
      }

      // Update the patient dashboard doc with the summary fields too,
      // so the dashboard can show the contact without an extra query.
      await db.collection('patients').doc(patientDocId).update({
        'emergencyContactName': _name.text.trim(),
        'emergencyContactPhone': _phone.text.trim(),
        'emergencyContactRelationship': _relationship.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ref.invalidate(patientEmergencyContactProvider);
      ref.invalidate(currentPatientProvider);

      if (!mounted) return;
      _snack('Emergency contact saved.', AppColors.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack('Could not save: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTestNotification() async {
    final patient = ref.read(currentPatientProvider).valueOrNull;
    final patientName = patient?['fullName'] ?? 'this patient';
    final phone = _phone.text.trim();
    if (phone.length < 8) {
      return _snack('Enter a valid phone number first', AppColors.error);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Send test notification', style: AppTextStyles.h3),
        content: Text(
          'We will send an SMS to $phone saying:\n\n'
          '"This is a test message from DoctoGP. $patientName has added '
          'you as their emergency contact for medication reminders. '
          'Reply STOP to opt out."\n\n'
          'Continue?',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Send test'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      // Queue the test message via a Firestore collection that a Cloud
      // Function drains and sends via MSG91 / Twilio / Exotel.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw 'Not signed in';
      final patient = ref.read(currentPatientProvider).valueOrNull;

      await FirebaseFirestore.instance
          .collection('emergencyNotifications')
          .add({
        'type': 'test',
        'patientDocId': patient?['patientDocId'],
        'patientAuthUid': uid,
        'contactName': _name.text.trim(),
        'contactPhone': phone,
        'message':
            'This is a test message from DoctoGP. '
                '${patient?['fullName'] ?? 'A patient'} has added you as '
                'their emergency contact for medication reminders. '
                'Reply STOP to opt out.',
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _snack(
        'Test SMS queued. It should arrive within a minute.',
        AppColors.success,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Could not queue test: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteContact() async {
    final existing = ref.read(patientEmergencyContactProvider).valueOrNull;
    if (existing == null || existing['contactDocId'] == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove emergency contact?', style: AppTextStyles.h3),
        content: const Text(
          'Missed-dose alerts will be disabled until you add a new contact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('emergencyContacts')
          .doc(existing['contactDocId'] as String)
          .update({'active': false, 'updatedAt': FieldValue.serverTimestamp()});

      final patient = ref.read(currentPatientProvider).valueOrNull;
      final patientDocId = patient?['patientDocId'] as String?;
      if (patientDocId != null) {
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(patientDocId)
            .update({
          'emergencyContactName': null,
          'emergencyContactPhone': null,
          'emergencyContactRelationship': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      ref.invalidate(patientEmergencyContactProvider);
      ref.invalidate(currentPatientProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack('Could not remove: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final existingAsync = ref.watch(patientEmergencyContactProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Emergency contact', style: AppTextStyles.h3),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GlassCard(
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.info_outline_rounded,
                      color: AppColors.info, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'If you miss a dose past its grace window, we will '
                    'notify this person by SMS. They must know they are your '
                    'emergency contact.',
                    style: AppTextStyles.caption,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            _field(
              'Full name',
              _name,
              hint: 'e.g. Anita Prajapati',
              icon: Icons.person_outline_rounded,
            ),
            _field(
              'Relationship',
              _relationship,
              hint: 'e.g. Spouse, Parent, Sibling',
              icon: Icons.family_restroom_rounded,
            ),
            _field(
              'Phone',
              _phone,
              hint: '+91 98xxxxxxxx',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
            ),
            _field(
              'Email (optional)',
              _email,
              hint: 'they@example.com',
              icon: Icons.alternate_email_rounded,
              keyboard: TextInputType.emailAddress,
            ),

            const SizedBox(height: 8),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.sms_outlined,
                        color: AppColors.success, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Notify by SMS',
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Switch(
                      value: _smsOptIn,
                      onChanged: (v) => setState(() => _smsOptIn = v),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'A text message will be sent when a dose is missed. '
                    'Standard SMS rates may apply.',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            GlassCard(
              borderColor:
                  _consentAttested ? AppColors.success : AppColors.warning,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () =>
                    setState(() => _consentAttested = !_consentAttested),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _consentAttested,
                        onChanged: (v) => setState(
                            () => _consentAttested = v ?? false),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'I confirm this person has agreed to '
                                'receive health-related notifications '
                                'about me.',
                                style: AppTextStyles.body
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Required under the DPDP Act — health data '
                                'cannot be shared with a third party '
                                'without their consent.',
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving…' : 'Save contact'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _sendTestNotification,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Send test SMS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.info,
                    side: const BorderSide(color: AppColors.info),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ]),

            existingAsync.maybeWhen(
              data: (contact) {
                if (contact == null || contact['contactDocId'] == null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _deleteContact,
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.error, size: 18),
                      label: const Text(
                        'Remove emergency contact',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    IconData? icon,
    TextInputType? keyboard,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, size: 20) : null,
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: AppColors.surface,
          ),
        ),
      );
}