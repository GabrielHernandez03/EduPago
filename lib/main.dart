import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_colors.dart';
import 'features/auth/presentation/screens/reset_password_screen.dart';
import 'features/landing/presentation/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización de Supabase con tus credenciales reales
  await Supabase.initialize(
    url: 'https://biuwojmjudzfvstgklrj.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpdXdvam1qdWR6ZnZzdGdrbHJqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyNDI5MzUsImV4cCI6MjEwNjgxODkzNX0.Ll7gcvZ3lw-vf6dVbJZlMPucMFiwJ7wxaUStymp5glk',
  );

  runApp(const MyApp());
}

// Instancia global de Supabase
final supabase = Supabase.instance.client;

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();

    // 1. Escuchar eventos futuros de autenticación
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        _navigateToResetPassword();
      }
    });

    // 2. Comprobar si la app cargó Web con la URL del enlace de recuperación
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfRecoveryUrl();
    });
  }

  void _checkIfRecoveryUrl() {
    if (kIsWeb) {
      final uri = Uri.base;
      // Verifica si la URL en el navegador incluye los parámetros de recuperación de Supabase
      final isRecovery =
          uri.fragment.contains('type=recovery') ||
          uri.toString().contains('type=recovery') ||
          uri.queryParameters['type'] == 'recovery';

      if (isRecovery) {
        _navigateToResetPassword();
      }
    }
  }

  void _navigateToResetPassword() {
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const ResetPasswordScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'EduPago',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryBlue),
        textTheme: GoogleFonts.lexendTextTheme(ThemeData.light().textTheme),
      ),
      home: const HomeScreen(),
    );
  }
}
