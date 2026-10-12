import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_colors.dart';
import 'features/landing/presentation/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización de Supabase con tus credenciales reales
  await Supabase.initialize(
    url: 'https://biuwojmjudzfvstgklrj.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpdXdvam1qdWR6ZnZzdGdrbHJqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyNDI5MzUsImV4cCI6MjEwNjgxODkzNX0.Ll7gcvZ3lw-vf6dVbJZlMPucMFiwJ7wxaUStymp5glk',
  );

  runApp(const MyApp());
}

// Instancia global de Supabase
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EduPago',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryBlue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}