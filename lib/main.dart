import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/auth_screen.dart';
import 'screens/main_menu_screen.dart';
import 'services/background_service.dart';
import 'utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: AppConstants.supabaseAnonKey,
  );

  await initializeDateFormatting('cs_CZ', null);

  await initializeService();

  runApp(const JavornikTimerushApp());
}

class JavornikTimerushApp extends StatelessWidget {
  const JavornikTimerushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Javorník TimeRush',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        if (session != null) {
          return MainMenuScreen();
        } else {
          return AuthScreen();
        }
      },
    );
  }
}