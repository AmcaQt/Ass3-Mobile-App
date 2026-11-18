import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const LabSafetyApp());
}

class LabSafetyApp extends StatelessWidget {
  const LabSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lab Safety Monitor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      // the gate decides between login and the tabs, so there is no
      // '/home' route to land on while signed out
      home: const AuthGate(),
      routes: {
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}

/// Shows [LoginScreen] while signed out and [AppShell] once signed in.
///
/// Nothing below this widget is built until a user exists, which is what keeps
/// the database listeners from firing without a token.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.auth});

  /// Injectable for tests; defaults to a service on FirebaseAuth.instance.
  final AuthService? auth;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth = widget.auth ?? AuthService();

  // Held in a field so a rebuild does not resubscribe the auth listener.
  late final Stream<User?> _authState = _auth.authStateChanges;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authState,
      builder: (context, snapshot) {
        // first frame: the plugin is still restoring any saved session
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) {
          return LoginScreen(auth: _auth);
        }
        return AppShell(auth: _auth);
      },
    );
  }
}
