// lib/features/lab/presentation/lab_shell.dart
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import 'lab_dashboard.dart';
import 'lab_test_catalog_screen.dart';

class LabShell extends StatefulWidget {
  const LabShell({super.key});

  @override
  State<LabShell> createState() => _LabShellState();
}

class _LabShellState extends State<LabShell> {
  int _index = 0;

  static const _screens = [
    LabDashboard(),
    LabTestCatalogScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border:
              Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          selectedItemColor: AppColors.labAccent,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt_outlined),
              activeIcon: Icon(Icons.list_alt_rounded),
              label: 'Test catalog',
            ),
          ],
        ),
      ),
    );
  }
}