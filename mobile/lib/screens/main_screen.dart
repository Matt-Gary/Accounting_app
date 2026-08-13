import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../services/backend_service.dart';
import 'home_screen.dart';
import 'investments_screen.dart';
import 'super_admin_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<InvestmentsScreenState> _investmentsKey =
      GlobalKey<InvestmentsScreenState>();
  bool? _isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _checkSuperAdmin();
  }

  Future<void> _checkSuperAdmin() async {
    try {
      final me = await BackendService().getMe();
      if (!mounted) return;
      setState(() => _isSuperAdmin = me['is_super_admin'] == true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSuperAdmin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    final isAdmin = _isSuperAdmin == true;

    // Screens that live in the IndexedStack. The "Add" nav button (index 2)
    // does not map to a screen — it triggers the add-options sheet.
    final screens = <Widget>[
      HomeScreen(key: _homeKey),
      InvestmentsScreen(key: _investmentsKey),
      if (isAdmin) const SuperAdminScreen(),
    ];

    // Map nav index -> screen index. 0,1 are direct; 2 is "Add" (handled in
    // onTap, not via stack); 3 is admin and maps to screen slot 2.
    final stackIndex = _currentIndex == 3 ? 2 : _currentIndex;

    return Scaffold(
      body: IndexedStack(
        index: stackIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 2) {
            // Center "+" is context-aware: add an investment while the
            // Investments tab is showing, otherwise add a spending/earning.
            if (_currentIndex == 1) {
              _investmentsKey.currentState?.openAddTransaction();
            } else {
              _homeKey.currentState?.showAddOptions();
            }
          } else {
            setState(() => _currentIndex = index);
          }
        },
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.dashboard), label: 'nav.dashboard'.tr()),
          BottomNavigationBarItem(
              icon: const Icon(Icons.trending_up),
              label: 'nav.investments'.tr()),
          BottomNavigationBarItem(
              icon: const Icon(Icons.add_circle, size: 32, color: Colors.black),
              label: 'nav.add'.tr()),
          if (isAdmin)
            BottomNavigationBarItem(
                icon: const Icon(Icons.admin_panel_settings),
                label: 'nav.admin'.tr()),
        ],
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        iconSize: 24,
      ),
    );
  }
}
