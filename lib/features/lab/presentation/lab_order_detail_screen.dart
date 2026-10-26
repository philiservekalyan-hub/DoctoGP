// lib/features/lab/presentation/lab_order_detail_screen.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';

class LabOrderDetailScreen extends ConsumerStatefulWidget {
  final LabOrderModel order;
  const LabOrderDetailScreen({super.key, required this.order});

  @override
  ConsumerState<LabOrderDetailScreen> createState() =>
      _LabOrderDetailScreenState();
}

class _LabOrderDetailScreenState
    extends ConsumerState<LabOrderDetailScreen> {
  late LabOrderModel _order;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _uploadReport() async {
    setState(() => _uploading = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (file == null) return;

      final Uint8List bytes = await file.readAsBytes();
      final safeName =
          file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path =
          'labReports/${_order.docId}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await FirebaseStorage.instance.ref(path).putData(
        bytes,
        SettableMetadata(
          contentType: _contentType(file.name),
          customMetadata: {
            'labOrderId': _order.docId,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      final url =
          await FirebaseStorage.instance.ref(path).getDownloadURL();

      // attachReport sets status to 'ready' and records all report fields
      // in one update — no separate updateStatus call needed.
      await ref.read(labServiceProvider).attachReport(
            orderId: _order.docId,
            reportUrl: url,
            reportStoragePath: path,
            reportFileName: file.name,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Report uploaded and marked ready.'),
          backgroundColor: AppColors.success,
        ));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _contentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = _order.status == LabOrderStatus.processing;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Lab order')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(_order.testsSummary,
                          style: AppTextStyles.h3),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(.13),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_order.statusLabel,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.info)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text('Patient: ${_order.patientName}',
                      style: AppTextStyles.body),
                  Text('Patient ID: ${_order.patientId}',
                      style: AppTextStyles.bodyMuted),
                  if (_order.patientPhone != null)
                    Text('Phone: ${_order.patientPhone}',
                        style: AppTextStyles.bodyMuted),
                  const SizedBox(height: 10),
                  Text('Ordered by: ${_order.doctorName}',
                      style: AppTextStyles.bodyMuted),
                  if (_order.orderedAt != null)
                    Text(
                      'On: ${DateFormat('EEE, dd MMM • hh:mm a').format(_order.orderedAt!)}',
                      style: AppTextStyles.caption,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const SectionHeader(title: 'Tests'),
            const SizedBox(height: 8),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _order.tests.map((t) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.science_outlined,
                          color: AppColors.labAccent, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(t.label,
                              style: AppTextStyles.body)),
                    ]),
                  );
                }).toList(),
              ),
            ),

            if (_order.instructions != null &&
                _order.instructions!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Instructions'),
              const SizedBox(height: 8),
              GlassCard(
                child: Text(_order.instructions!,
                    style: AppTextStyles.bodyMuted),
              ),
            ],

            if (_order.referralNotes != null &&
                _order.referralNotes!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Clinical notes'),
              const SizedBox(height: 8),
              GlassCard(
                child: Text(_order.referralNotes!,
                    style: AppTextStyles.bodyMuted),
              ),
            ],

            if (_order.reportUrl != null &&
                _order.reportUrl!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Report'),
              const SizedBox(height: 8),
              GlassCard(
                child: Row(children: [
                  const Icon(Icons.description_rounded,
                      color: AppColors.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _order.reportFileName ?? 'Uploaded report',
                      style: AppTextStyles.body,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final url = Uri.tryParse(_order.reportUrl!);
                      if (url != null) {
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    child: const Text('Open'),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 24),

            if (canUpload)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _uploading ? null : _uploadReport,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  label: Text(_uploading
                      ? 'Uploading...'
                      : 'Upload report & mark ready'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.labAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}