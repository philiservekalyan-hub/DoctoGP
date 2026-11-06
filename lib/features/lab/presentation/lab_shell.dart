// lib/features/lab/presentation/lab_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/user_model.dart';
import 'lab_dashboard.dart';
import 'lab_owner_dashboard.dart';
import 'lab_test_catalog_screen.dart';

class LabShell extends ConsumerStatefulWidget {
  const LabShell({super.key});

  @override
  ConsumerState<LabShell> createState() => _LabShellState();
}

class _LabShellState extends ConsumerState<LabShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    // Don't build tabs until the user resolves. This avoids a
    // one-frame flash of the wrong dashboard (LabDashboard) that
    // IndexedStack would otherwise preserve.
    if (userAsync.isLoading && !userAsync.hasValue) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.labAccent),
        ),
      );
    }

    final user = userAsync.valueOrNull;
    final isOwner = user?.role == UserRole.owner ||
        user?.role == UserRole.admin ||
        user?.isLabOwner == true;

    // ⚠️ `const` on each branch, NOT on the ternary itself — the
    // widget type is chosen at runtime (isOwner), so the whole
    // expression can't be `const`.
    final screens = <Widget>[
      isOwner
          ? const LabOwnerDashboard()
          : const LabDashboard(),
      const LabTestCatalogScreen(),
    ];

    final safeIndex = _index.clamp(0, screens.length - 1);

    return Scaffold(
      body: IndexedStack(index: safeIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: BottomNavigationBar(
          currentIndex: safeIndex,
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