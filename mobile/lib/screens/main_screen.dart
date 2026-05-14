import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'investments_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(key: _homeKey),
      const InvestmentsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 2) {
            _homeKey.currentState?.showAddOptions();
          } else {
            setState(() => _currentIndex = index);
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.trending_up), label: 'Investments'),
          BottomNavigationBarItem(
              icon: Icon(Icons.add_circle, size: 32, color: Colors.black),
              label: 'Add'),
        ],
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        iconSize: 24,
      ),
    );
  }
}
