import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/models/ad_model.dart';
import '../../../../core/widgets/glass_card.dart';
import 'ad_status_chip.dart';

class AdTile extends StatelessWidget {
  final AdModel ad;
  final VoidCallback onTap;
  const AdTile({super.key, required this.ad, required this.onTap});

  String _fmt(DateTime? d) =>
      d == null ? '—' : '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ad.imageUrl.isEmpty
                      ? Container(
                          width: 72,
                          height: 48,
                          color: AppColors.textMuted.withOpacity(.1),
                          child: const Icon(Icons.image_not_supported_rounded,
                              color: AppColors.textMuted, size: 20),
                        )
                      : Image.network(ad.imageUrl,
                          width: 72, height: 48, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ad.name, style: AppTextStyles.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        '${ad.advertiserName} · ${_fmt(ad.startAt)} → ${_fmt(ad.endAt)}',
                        style: AppTextStyles.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AdStatusChip(status: ad.status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}