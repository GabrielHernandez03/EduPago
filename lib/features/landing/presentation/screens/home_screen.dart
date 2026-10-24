import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_navbar.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../auth/presentation/screens/register_screen.dart';
import '../widgets/hero_section.dart';
import '../widgets/stats_bar_section.dart';
import '../widgets/features_section.dart';
import '../widgets/security_section.dart';
import '../widgets/cta_and_footer_section.dart';
import '../widgets/contact_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewKey = GlobalKey();

  final GlobalKey _inicioKey = GlobalKey();
  final GlobalKey _solucionesKey = GlobalKey();
  final GlobalKey _seguridadKey = GlobalKey();
  final GlobalKey _contactoKey = GlobalKey();

  // Estado de scroll: notifiers separados para reconstruir solo lo necesario
  // (navbar y botón "volver arriba"), no toda la landing.
  final ValueNotifier<String> _activeLink = ValueNotifier<String>('Inicio');
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  final ValueNotifier<bool> _showTop = ValueNotifier<bool>(false);

  late final List<MapEntry<String, GlobalKey>> _sections = [
    MapEntry('Inicio', _inicioKey),
    MapEntry('Soluciones', _solucionesKey),
    MapEntry('Seguridad', _seguridadKey),
    MapEntry('Contacto', _contactoKey),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _activeLink.dispose();
    _scrolled.dispose();
    _progress.dispose();
    _showTop.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final double offset = position.pixels;

    _scrolled.value = offset > 8;
    _showTop.value = offset > 500;
    _progress.value = position.maxScrollExtent > 0
        ? (offset / position.maxScrollExtent).clamp(0.0, 1.0).toDouble()
        : 0.0;

    _updateActiveSection(position);
  }

  /// Scroll spy: la sección activa es la última cuyo borde superior ya pasó
  /// por la parte alta del área visible.
  void _updateActiveSection(ScrollPosition position) {
    final scrollBox = _scrollViewKey.currentContext?.findRenderObject();
    if (scrollBox is! RenderBox || !scrollBox.attached) return;
    final double viewportTop = scrollBox.localToGlobal(Offset.zero).dy;

    String active = _sections.first.key;
    for (final section in _sections) {
      final box = section.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final double top = box.localToGlobal(Offset.zero).dy - viewportTop;
      if (top <= 140) active = section.key;
    }

    // Al llegar al final de la página, "Contacto" es lo más cercano.
    if (position.pixels >= position.maxScrollExtent - 4 &&
        position.maxScrollExtent > 0) {
      active = 'Contacto';
    }

    _activeLink.value = active;
  }

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Transición de pantalla: fade + leve deslizamiento hacia arriba.
  Route<T> _route<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _navigateToLogin() {
    Navigator.push(context, _route(const LoginScreen()));
  }

  void _navigateToRegister() {
    Navigator.push(context, _route(const RegisterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _showTop,
        builder: (context, show, _) {
          return AnimatedSlide(
            offset: show ? Offset.zero : const Offset(0, 2),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !show,
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: 'Volver arriba',
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  onPressed: _scrollToTop,
                  child: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ),
            ),
          );
        },
      ),
      body: Column(
        children: [
          // Header fijo: link activo (scroll spy), sombra y barra de progreso
          AnimatedBuilder(
            animation: Listenable.merge([_activeLink, _scrolled, _progress]),
            builder: (context, _) {
              return CustomNavbar(
                activeLink: _activeLink.value,
                isScrolled: _scrolled.value,
                scrollProgress: _progress.value,
                onInicioPressed: () => _scrollToSection(_inicioKey),
                onSolucionesPressed: () => _scrollToSection(_solucionesKey),
                onSeguridadPressed: () => _scrollToSection(_seguridadKey),
                onContactoPressed: () => _scrollToSection(_contactoKey),
                onLoginPressed: _navigateToLogin,
                onRegisterPressed: _navigateToRegister,
              );
            },
          ),

          Expanded(
            child: SingleChildScrollView(
              key: _scrollViewKey,
              controller: _scrollController,
              child: Column(
                children: [
                  HeroSection(
                    key: _inicioKey,
                    onStartPressed: _navigateToRegister,
                    onLoginPressed: _navigateToLogin,
                  ),
                  const StatsBarSection(),
                  FeaturesSection(key: _solucionesKey),
                  SecuritySection(key: _seguridadKey),
                  ContactSection(key: _contactoKey),
                  CtaAndFooterSection(
                    onRegisterPressed: _navigateToRegister,
                    onContactPressed: () => _scrollToSection(_contactoKey),
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
