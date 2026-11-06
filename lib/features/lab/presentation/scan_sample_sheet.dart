// lib/features/lab/presentation/scan_sample_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';

/// Result of a successful scan — the barcode value.
class ScanResult {
  final String barcode;
  final bool fromCamera;
  const ScanResult(this.barcode, {required this.fromCamera});
}

class ScanSampleSheet extends StatefulWidget {
  const ScanSampleSheet({super.key});

  @override
  State<ScanSampleSheet> createState() => _ScanSampleSheetState();
}

class _ScanSampleSheetState extends State<ScanSampleSheet> {
  int _tab = 0; // 0 = camera, 1 = hardware

  final _hardwareCtrl = TextEditingController();
  final _hardwareFocus = FocusNode();
  bool _scanHandled = false;

  @override
  void initState() {
    super.initState();
    // Autofocus the hidden text field so hardware scans land here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hardwareFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _hardwareCtrl.dispose();
    _hardwareFocus.dispose();
    super.dispose();
  }

  void _submit(String raw, {required bool fromCamera}) {
    if (_scanHandled) return;
    final value = raw.trim();
    if (value.isEmpty) return;
    _scanHandled = true;
    HapticFeedback.mediumImpact();
    if (mounted) {
      Navigator.of(context).pop(ScanResult(value, fromCamera: fromCamera));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              Text('Scan sample', style: AppTextStyles.h3),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          // Tab switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(
                child: _tabButton(
                  index: 0,
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Camera',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tabButton(
                  index: 1,
                  icon: Icons.usb_rounded,
                  label: 'Hardware scanner',
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _tab == 0 ? _cameraTab() : _hardwareTab(),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() {
        _tab = index;
        if (index == 1) {
          _hardwareFocus.requestFocus();
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.labAccent.withOpacity(.13)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.labAccent : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? AppColors.labAccent
                    : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(label,
                style: AppTextStyles.caption.copyWith(
                  color: selected
                      ? AppColors.labAccent
                      : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }

  Widget _cameraTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MobileScanner(
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                for (final b in barcodes) {
                  final value = b.rawValue;
                  if (value != null && value.isNotEmpty) {
                    _submit(value, fromCamera: true);
                    break;
                  }
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Point the camera at the sample label barcode',
          style: AppTextStyles.bodyMuted,
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  Widget _hardwareTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: const Icon(Icons.usb_rounded,
                      size: 56, color: AppColors.labAccent),
                ),
                const SizedBox(height: 16),
                Text('Ready for scanner',
                    style: AppTextStyles.h3, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Scan the sample label with your USB or Bluetooth '
                  'barcode scanner. The barcode value will appear below.',
                  style: AppTextStyles.bodyMuted,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        // Hidden focus target — hardware scanners type here.
        Opacity(
          opacity: 0.0,
          child: SizedBox(
            height: 1,
            child: TextField(
              controller: _hardwareCtrl,
              focusNode: _hardwareFocus,
              autofocus: true,
              onSubmitted: (v) => _submit(v, fromCamera: false),
              onChanged: (v) {
                // Some scanners send Enter, some don't. If the value
                // looks complete (typical Code128 is 10–20 chars), wait
                // a moment, then submit.
                if (v.length >= 8) {
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted && !_scanHandled && _hardwareCtrl.text == v) {
                      _submit(v, fromCamera: false);
                    }
                  });
                }
              },
            ),
          ),
        ),
      ]),
    );
  }
}