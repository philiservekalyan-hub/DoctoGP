import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/ad_model.dart';
import '../../../core/services/ads_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import 'ad_edit_screen.dart';
import 'widgets/ad_status_chip.dart';
import 'widgets/ad_tile.dart';

class AdsAdminScreen extends ConsumerStatefulWidget {
  const AdsAdminScreen({super.key});
  @override
  ConsumerState<AdsAdminScreen> createState() => _AdsAdminScreenState();
}

class _AdsAdminScreenState extends ConsumerState<AdsAdminScreen> {
  String? _filter; // null | 'draft' | 'pending_review' | 'approved' | ...

  @override
  Widget build(BuildContext context) {
    final adsAsync = ref.watch(allAdsProvider(_filter));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Sponsored offers'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New ad', style: TextStyle(color: Colors.white)),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdEditScreen()),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final entry in <String?, String>{
                    null: 'All',
                    'draft': 'Drafts',
                    'pending_review': 'Pending',
                    'approved': 'Approved',
                    'rejected': 'Rejected',
                    'paused': 'Paused',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.value),
                        selected: _filter == entry.key,
                        onSelected: (_) => setState(() => _filter = entry.key),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: adsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: AppColors.error)),
                ),
                data: (ads) {
                  if (ads.isEmpty) {
                    return const Center(
                      child: Text('No ads yet. Tap "New ad" to create one.',
                          style: TextStyle(color: AppColors.textMuted)),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    children: [
                      for (final ad in ads)
                        AdTile(
                          ad: ad,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AdEditScreen(existing: ad),
                            ),
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
    );
  }
}