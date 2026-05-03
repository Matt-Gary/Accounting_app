import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://aclfelfqqbtuvowintvg.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFjbGZlbGZxcWJ0dXZvd2ludHZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg1ODU5MDYsImV4cCI6MjA4NDE2MTkwNn0.357lZVIXZLTah4NnFqr9Qj80p9-yEoi5IxhylaRmERg',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );

  // If the user did not check "Remember me", clear any persisted session
  // so they must log in again on each cold start.
  final prefs = await SharedPreferences.getInstance();
  final rememberMe = prefs.getBool('remember_me') ?? true;
  if (!rememberMe && Supabase.instance.client.auth.currentSession != null) {
    await Supabase.instance.client.auth.signOut();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accounting App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _authSub;
  Session? _session;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _session = Supabase.instance.client.auth.currentSession;

    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      if (state.event == AuthChangeEvent.signedOut) {
        final prefs = await SharedPreferences.getInstance();
        final rememberMe = prefs.getBool('remember_me') ?? true;

        if (rememberMe) {
          if (mounted) setState(() => _refreshing = true);
          try {
            final refreshed =
                await Supabase.instance.client.auth.refreshSession();
            if (mounted) {
              setState(() {
                _session = refreshed.session;
                _refreshing = false;
              });
            }
            return;
          } catch (_) {
            // Refresh token expired — fall through to login screen
          }
          if (mounted) setState(() => _refreshing = false);
        }
      }

      if (mounted) setState(() => _session = state.session);
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_refreshing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session != null) return const MainScreen();
    return const LoginScreen();
  }
}
