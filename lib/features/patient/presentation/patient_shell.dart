import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import 'patient_dashboard.dart';
import 'pill_reminder_screen.dart';       
import 'my_reports_screen.dart';

class PatientShell extends ConsumerStatefulWidget {
  const PatientShell({super.key});
  @override
  ConsumerState<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends ConsumerState<PatientShell> {
  int _index = 0;

  final _screens = const [
    PatientDashboard(),
    PillReminderScreen(),                 
    MyReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.medication_outlined),         
              activeIcon: Icon(Icons.medication_rounded),     
              label: 'Pill Guard',                            
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined),
              activeIcon: Icon(Icons.description_rounded),
              label: 'Reports',
            ),
          ],
        ),
      ),
    );
  }
}