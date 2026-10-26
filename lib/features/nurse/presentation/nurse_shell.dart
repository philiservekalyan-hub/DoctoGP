import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/powered_by_footer.dart';
import 'nurse_dashboard.dart';
import 'nurse_patient_queue.dart';
import 'nurse_vitals_screen.dart';

class NurseShell extends ConsumerStatefulWidget {
  const NurseShell({super.key});
  @override
  ConsumerState<NurseShell> createState() => _NurseShellState();
}

class _NurseShellState extends ConsumerState<NurseShell> {
  int _index = 0;

  final _screens = const [
    NurseDashboard(),
    NursePatientQueue(),
    NurseVitalsScreen(),
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
          selectedItemColor: AppColors.nurseAccent,
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
                icon: Icon(Icons.monitor_heart_outlined),
                activeIcon: Icon(Icons.monitor_heart_rounded),
                label: 'Vitals'),
          ],
        ),
      ),
    );
  }
}