import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state.dart';

class MyAppointmentsScreen extends StatelessWidget {
  const MyAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Appointments')),
      body: const EmptyState(
        icon: Icons.event_note_rounded,
        title: 'No appointments yet',
        subtitle: 'Book your first appointment with a doctor.',
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        onPressed: () {},
        icon: const Icon(Icons.add_rounded),
        label: const Text('Book'),
      ),
    );
  }
}