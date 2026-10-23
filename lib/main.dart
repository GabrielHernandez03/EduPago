import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_colors.dart';
import 'features/auth/presentation/screens/email_confirmed_screen.dart';
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

  // Enlaces de los correos de Supabase: la app abre en
  //   /?token_hash=XXXX&type=recovery  -> restablecer contraseña
  //   /?token_hash=XXXX&type=email     -> correo confirmado
  // Se leen una sola vez al arrancar y deciden la pantalla inicial.
  final String? _recoveryToken = ResetPasswordScreen.tokenHashFromUrl();
  final String? _confirmToken = EmailConfirmedScreen.tokenHashFromUrl();

  @override
  void initState() {
    super.initState();

    // 1. Escuchar eventos futuros de autenticación
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      // Con enlace token_hash la pantalla de reset ya es la inicial y valida
      // el token por su cuenta; este evento solo cubre enlaces antiguos
      // (los que usaban {{ .ConfirmationURL }}).
      if (event == AuthChangeEvent.passwordRecovery && _recoveryToken == null) {
        _navigateToResetPassword();
      }
    });

    // 2. Comprobar si la app cargó Web con la URL del enlace de recuperación
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfRecoveryUrl();
    });
  }

  void _checkIfRecoveryUrl() {
    // Si ya se abrió con un enlace token_hash no hay nada más que comprobar.
    if (_recoveryToken != null || _confirmToken != null) return;

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
      home: _recoveryToken != null
          ? ResetPasswordScreen(tokenHash: _recoveryToken)
          : _confirmToken != null
          ? EmailConfirmedScreen(tokenHash: _confirmToken)
          : const HomeScreen(),
    );
  }
}
