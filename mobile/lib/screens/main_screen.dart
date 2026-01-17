import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../repositories/accounting_repository.dart';
import 'home_screen.dart';
import 'investments_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // We manage the "Current User" state here at the top level so it can be shared
  // between tabs, or we can fetch it in each tab.
  // Ideally, the user selects a profile in the Dashboard, and that profile is used in Investments.
  // To keep it simple, let's fetch profiles here or allow HomeScreen to manage it and we just pass it?
  // HomeScreen currently manages its own state.
  // Let's lift the User state up, or simpler: Let the first tab be the "Controller" for User?
  // Actually, standard pattern: A UserProvider.
  // For MVP: I will fetch the default user here and pass it down.
  // If HomeScreen changes user, it might be tricky.
  // BETTER: Just let HomeScreen be index 0. User uses standard Home.
  // But Investments needs the user.
  // Let's implement a simple user fetch here for the initial "Main" user, and maybe add a user selector in the AppBar of MainScreen?

  final _repository = AccountingRepository();
  UserProfile? _currentUser;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final profiles = await _repository.getProfiles();
      if (profiles.isNotEmpty) {
        setState(() {
          _currentUser = profiles.first;
          _loadingUser = false;
        });
      } else {
        setState(() => _loadingUser = false);
      }
    } catch (e) {
      print("Error loading user: $e");
      setState(() => _loadingUser = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // We pass _currentUser to tabs.
    // Note: HomeScreen currently manages its own user internally for fetching dashboard,
    // but the API calls in HomeScreen use the "user_id" param?
    // Wait, HomeScreen calls getDashboard which takes user_id but it seems to default or the user selects it?
    // Looking at HomeScreen code:
    // It doesn't seem to have a User Selector visible in the code I read previously?
    // It calls `_backendService.getDashboard` with just month/year.
    // Ah, `getDashboard` takes optional user_id. If null, backend returns ALL or handled.
    // In `app.py`: `user_id = request.args.get('user_id')`. If None, it fetches all?
    // `query = client.from_("expenses")... if user_id: query = query.eq(...)`
    // So if no user_id, it returns everything.
    // For Investments, we DEFINITELY need user_id because we filter by it.

    // Let's assume for now we use the first found user, or pass null (which might fail for investments).
    // The `InvestmentsScreen` I wrote expects `required this.currentUser`.

    final List<Widget> _screens = [
      const HomeScreen(),
      InvestmentsScreen(currentUser: _currentUser),
    ];

    return Scaffold(
      body: _loadingUser
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.trending_up), label: 'Investments'),
        ],
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
      ),
    );
  }
}
