// lib/features/admin/presentation/admin_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/powered_by_footer.dart';
import 'admin_dashboard.dart';
import 'clinics_list_screen.dart';
import 'create_clinic_screen.dart';
import 'link_management_screen.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});
  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;

  final _screens = const [
    AdminDashboard(),
    ClinicsListScreen(),
    LinkManagementScreen(),
    CreateClinicScreen(embedded: true),
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
          selectedItemColor: AppColors.secondary,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard_rounded),
                label: 'Overview'),
            BottomNavigationBarItem(
                icon: Icon(Icons.local_hospital_outlined),
                activeIcon: Icon(Icons.local_hospital_rounded),
                label: 'Entities'),
            BottomNavigationBarItem(
                icon: Icon(Icons.link_outlined),
                activeIcon: Icon(Icons.link_rounded),
                label: 'Links'),
            BottomNavigationBarItem(
                icon: Icon(Icons.add_business_outlined),
                activeIcon: Icon(Icons.add_business_rounded),
                label: 'Create'),
          ],
        ),
      ),
    );
  }
}