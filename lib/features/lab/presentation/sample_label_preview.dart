// lib/features/lab/presentation/sample_label_preview.dart
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_order_model.dart';

const _labelWidth = 50 * PdfPageFormat.mm;
const _labelHeight = 20 * PdfPageFormat.mm;

class SampleLabelsPreviewSheet extends StatelessWidget {
  final LabOrderModel order;
  final List<SampleGroup> groups;
  final DateTime collectedAt;

  const SampleLabelsPreviewSheet({
    super.key,
    required this.order,
    required this.groups,
    required this.collectedAt,
  });

  @override
  Widget build(BuildContext context) {
    final allLabels = groups
        .expand((g) =>
            g.sampleIds.map((id) => _LabelData(group: g, sampleId: id)))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sample labels', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            Text(
              '${allLabels.length} label${allLabels.length == 1 ? '' : 's'} — one per tube',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 16),
            ...allLabels.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LabelPreview(data: l),
                )),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.skip_next_rounded, size: 18),
                  label: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _printAll(context, allLabels),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: Text(allLabels.length == 1
                      ? 'Print'
                      : 'Print all ${allLabels.length}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _printAll(
      BuildContext context, List<_LabelData> labels) async {
    try {
      for (final label in labels) {
        final doc = await _buildPdf(label);
        await Printing.layoutPdf(
          onLayout: (_) async => doc.save(),
          name: 'label_${label.sampleId}',
          format: PdfPageFormat(_labelWidth, _labelHeight),
        );
      }
      if (!context.mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Print failed: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<pw.Document> _buildPdf(_LabelData label) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(_labelWidth, _labelHeight),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Padding(
          padding: const pw.EdgeInsets.all(1.5 * PdfPageFormat.mm),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    label.sampleId,
                    style: pw.TextStyle(
                        fontSize: 7, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Flexible(
                    child: pw.Text(
                      label.group.sampleType.toUpperCase(),
                      style: const pw.TextStyle(fontSize: 6),
                    ),
                  ),
                ],
              ),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: label.sampleId,
                  width: 45 * PdfPageFormat.mm,
                  height: 8 * PdfPageFormat.mm,
                  drawText: false,
                ),
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      order.patientName,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: const pw.TextStyle(fontSize: 5),
                    ),
                  ),
                  pw.Text(
                    DateFormat('dd MMM HH:mm').format(collectedAt),
                    style: const pw.TextStyle(fontSize: 5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return doc;
  }
}

class _LabelPreview extends StatelessWidget {
  final _LabelData data;
  const _LabelPreview({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(data.sampleId,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  data.group.sampleType.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.info),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BarcodeWidget(
            barcode: Barcode.code128(),
            data: data.sampleId,
            width: 260,
            height: 55,
            drawText: false,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(data.group.testsSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              Text(DateFormat('dd MMM HH:mm').format(DateTime.now()),
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabelData {
  final SampleGroup group;
  final String sampleId;
  _LabelData({required this.group, required this.sampleId});
}