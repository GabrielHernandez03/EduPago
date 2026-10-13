import 'package:flutter/material.dart';
import '../../../../core/widgets/custom_navbar.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../auth/presentation/screens/register_screen.dart';
import '../widgets/hero_section.dart';
import '../widgets/stats_bar_section.dart'; // <--- Importación corregida en la misma carpeta de widgets
import '../widgets/features_section.dart';
import '../widgets/security_section.dart';
import '../widgets/cta_and_footer_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey _inicioKey = GlobalKey();
  final GlobalKey _solucionesKey = GlobalKey();
  final GlobalKey _seguridadKey = GlobalKey();
  final GlobalKey _contactoKey = GlobalKey();

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  void _navigateToLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Header Fijo Superior
          CustomNavbar(
            onInicioPressed: () => _scrollToSection(_inicioKey),
            onSolucionesPressed: () => _scrollToSection(_solucionesKey),
            onSeguridadPressed: () => _scrollToSection(_seguridadKey),
            onContactoPressed: () => _scrollToSection(_contactoKey),
            onLoginPressed: _navigateToLogin,
            onRegisterPressed: _navigateToRegister,
          ),

          // Cuerpo
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  HeroSection(
                    key: _inicioKey,
                    onStartPressed: _navigateToRegister,
                    onLoginPressed: _navigateToLogin,
                  ),
                  const StatsBarSection(), // <--- ¡Aquí va exactamente debajo del HeroSection!
                  FeaturesSection(key: _solucionesKey),
                  SecuritySection(key: _seguridadKey),
                  CtaAndFooterSection(
                    key: _contactoKey,
                    onRegisterPressed: _navigateToRegister,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
