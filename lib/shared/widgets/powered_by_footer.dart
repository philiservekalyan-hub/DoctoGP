import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';

class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({super.key});

  static const String _appName = 'DoctoGP';
  static const String _supportEmail = 'support@doctogp.com';
  static const String _supportPhone = '+919876543210';
  static const String _supportUrl = 'https://doctogp.com';

  Future<void> _launch(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $uri')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $uri')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        color: AppColors.background,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_rounded,
                size: 14,
                color: AppColors.primary.withOpacity(0.8),
              ),
              const SizedBox(width: 6),
              Text(
                'Powered by $_appName',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              _contactChip(
                icon: Icons.email_outlined,
                label: _supportEmail,
                onTap: () => _launch(
                  context,
                  Uri(scheme: 'mailto', path: _supportEmail),
                ),
              ),
              _contactChip(
                icon: Icons.phone_outlined,
                label: _supportPhone,
                onTap: () => _launch(
                  context,
                  Uri(scheme: 'tel', path: _supportPhone),
                ),
              ),
              _contactChip(
                icon: Icons.language_outlined,
                label: _supportUrl.replaceFirst('https://', ''),
                onTap: () => _launch(context, Uri.parse(_supportUrl)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}