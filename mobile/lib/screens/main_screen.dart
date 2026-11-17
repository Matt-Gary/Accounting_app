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
  bool? _isSuperAdmin;

  /// The Investments tab is built on its first visit, not at app start. Inside
  /// the IndexedStack it used to load immediately: a Yahoo round-trip (and a
  /// "visit" snapshot written for a day nobody looked at the portfolio) on
  /// every launch, even when the user only came to log an expense.
  bool _investmentsOpened = false;

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

    // One screen per navigation item, in the same order. "Add" is no longer a
    // navigation item: a bar entry that opens a sheet instead of a screen was
    // a button dressed as a tab. Each tab now has its own floating "+".
    final screens = <Widget>[
      const HomeScreen(),
      _investmentsOpened ? const InvestmentsScreen() : const SizedBox.shrink(),
      if (isAdmin) const SuperAdminScreen(),
    ];
    final index = _currentIndex < screens.length ? _currentIndex : 0;

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        type: BottomNavigationBarType.fixed,
        onTap: (tapped) => setState(() {
          _currentIndex = tapped;
          if (tapped == 1) _investmentsOpened = true;
        }),
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.dashboard), label: 'nav.dashboard'.tr()),
          BottomNavigationBarItem(
              icon: const Icon(Icons.trending_up),
              label: 'nav.investments'.tr()),
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
