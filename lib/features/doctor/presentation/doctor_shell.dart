// lib/features/doctor/presentation/doctor_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import 'consultation_screen.dart';
import 'doctor_dashboard.dart';
import 'doctor_providers.dart';
import 'lab_order_history_screen.dart';
import 'lab_orders_screen.dart';
import 'consult_tab.dart';

class DoctorShell extends ConsumerWidget {
  const DoctorShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(doctorTabProvider);
    final selected = ref.watch(selectedAppointmentProvider);

    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: const [
          DoctorDashboard(),
          _ConsultTabHost(),
          LabOrdersScreen(),
          LabOrderHistoryScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: BottomNavigationBar(
          currentIndex: tab,
          onTap: (i) => ref.read(doctorTabProvider.notifier).state = i,
          selectedItemColor: AppColors.doctorAccent,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: _ConsultIcon(
                  hasSelection: selected != null, active: false),
              activeIcon: _ConsultIcon(
                  hasSelection: selected != null, active: true),
              label: 'Consult',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.science_outlined),
              activeIcon: Icon(Icons.science_rounded),
              label: 'Lab orders',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsultIcon extends StatelessWidget {
  final bool hasSelection;
  final bool active;
  const _ConsultIcon({required this.hasSelection, required this.active});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(active
        ? Icons.medical_services_rounded
        : Icons.medical_services_outlined);
    if (!hasSelection) return icon;
    return Stack(clipBehavior: Clip.none, children: [
      icon,
      Positioned(
        right: -2,
        top: -2,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ]);
  }
}

class _ConsultTabHost extends ConsumerWidget {
  const _ConsultTabHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appt = ref.watch(selectedAppointmentProvider);
    if (appt == null) return const ConsultTab();
    return ConsultationScreen(
      key: ValueKey(appt.docId),
      appointment: appt,
    );
  }
}