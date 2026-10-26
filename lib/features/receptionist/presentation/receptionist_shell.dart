import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/powered_by_footer.dart';
import 'receptionist_dashboard.dart';
import 'live_queue_screen.dart';
import 'patient_registry_screen.dart';
import 'staff_attendance_screen.dart';

class ReceptionistShell extends ConsumerStatefulWidget {
  const ReceptionistShell({super.key});
  @override
  ConsumerState<ReceptionistShell> createState() => _ReceptionistShellState();
}

class _ReceptionistShellState extends ConsumerState<ReceptionistShell> {
  int _index = 0;
  final _screens = const [
    ReceptionistDashboard(),
    LiveQueueScreen(),
    PatientRegistryScreen(),
    StaffAttendanceScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _index, children: _screens),
          ),
          const PoweredByFooter(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          selectedItemColor: AppColors.receptionAccent,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard_rounded),
                label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.queue_outlined),
                activeIcon: Icon(Icons.queue_rounded),
                label: 'Queue'),
            BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people_rounded),
                label: 'Patients'),
            BottomNavigationBarItem(
                icon: Icon(Icons.badge_outlined),
                activeIcon: Icon(Icons.badge_rounded),
                label: 'Staff'),
          ],
        ),
      ),
    );
  }
}