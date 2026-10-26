import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';

class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Reports')),
      body: const EmptyState(
        icon: Icons.science_rounded,
        title: 'No reports available',
        subtitle:
            'Reports from your diagnostic tests will appear here once ready.',
      ),
    );
  }
}