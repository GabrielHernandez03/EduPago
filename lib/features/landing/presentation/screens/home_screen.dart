import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_navbar.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../auth/presentation/screens/register_screen.dart';
import '../widgets/hero_section.dart';
import '../widgets/features_section.dart';
import '../widgets/stats_bar_section.dart';
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

  // Precargado: la landing se construye cuando las imágenes y fuentes están listas.
  bool _ready = false;
  bool _preloadStarted = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preloadStarted) return;
    _preloadStarted = true;
    _preload();
  }

  /// La landing NO se muestra hasta que logo, fotos del hero y fuentes estén
  /// decodificados en memoria (máx. 20 s por si la conexión es muy lenta).
  /// La pantalla de carga se ve al menos 700 ms para evitar parpadeos.
  ///
  /// IMPORTANTE: las fotos se precargan con la MISMA clave de caché que usa
  /// HeroSection (ResizeImage con photoCacheWidth). Si se precargan sin
  /// redimensionar, la clave es otra y el hero vuelve a decodificar la foto
  /// al aparecer (se ve la tarjeta blanca un instante).
  Future<void> _preload() async {
    final started = DateTime.now();
    try {
      final photoWidth = HeroSection.photoCacheWidth(context);
      final tasks = <Future<void>>[
        precacheImage(
          const AssetImage('assets/images/logo_edupago.png'),
          context,
        ).catchError((_) {}),
        for (final asset in HeroSection.imageAssets)
          precacheImage(
            ResizeImage.resizeIfNeeded(photoWidth, null, AssetImage(asset)),
            context,
          ).catchError((_) {}),
        GoogleFonts.pendingFonts().then<void>((_) {}).catchError((_) {}),
      ];
      await Future.wait<void>(tasks).timeout(const Duration(seconds: 20));
    } catch (_) {
      // Si algo falla o tarda demasiado, se muestra la página igualmente.
    }
    final elapsed = DateTime.now().difference(started);
    const minimum = Duration(milliseconds: 700);
    if (elapsed < minimum) await Future<void>.delayed(minimum - elapsed);
    if (!mounted) return;
    setState(() => _ready = true);
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

  // ── Medición segura ───────────────────────────────────────────────────────
  // Todas las lecturas de geometría pasan por aquí: si algo aún no tiene
  // layout (primer frame, resize) simplemente se ignora en vez de lanzar.

  RenderBox? _viewportBox() {
    final object = _scrollViewKey.currentContext?.findRenderObject();
    if (object is RenderBox && object.attached && object.hasSize) {
      return object;
    }
    return null;
  }

  /// Posición vertical del borde superior de [key] relativa al viewport.
  double? _topOf(GlobalKey key, RenderBox viewport) {
    final object = key.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    try {
      return object.localToGlobal(Offset.zero, ancestor: viewport).dy;
    } catch (_) {
      return null;
    }
  }

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions || !position.hasPixels) return;
    final double offset = position.pixels;

    _scrolled.value = offset > 8;
    _showTop.value = offset > 500;
    _progress.value = position.maxScrollExtent > 0
        ? (offset / position.maxScrollExtent).clamp(0.0, 1.0).toDouble()
        : 0.0;

    _updateActiveSection(position);
  }

  /// Scroll spy: la sección activa es la última cuyo borde superior ya pasó
  /// por la parte alta del área visible (debajo de la barra flotante).
  void _updateActiveSection(ScrollPosition position) {
    final viewport = _viewportBox();
    if (viewport == null) return;

    String active = _sections.first.key;
    for (final section in _sections) {
      final top = _topOf(section.value, viewport);
      if (top != null && top <= 140) active = section.key;
    }

    // Al llegar al final de la página, "Contacto" es lo más cercano.
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 4) {
      active = 'Contacto';
    }

    _activeLink.value = active;
  }

  /// Lleva la sección justo debajo de la barra flotante.
  void _scrollToSection(GlobalKey key) {
    if (!_scrollController.hasClients) return;
    final viewport = _viewportBox();
    if (viewport == null) return;
    final top = _topOf(key, viewport);
    if (top == null) return;

    final position = _scrollController.position;
    final double inset = key == _inicioKey ? 0.0 : 72.54;
    final double target = (position.pixels + top - inset)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
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
      backgroundColor: const Color(0xFFF2F7FD),
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
                  elevation: 2.79,
                  onPressed: _scrollToTop,
                  child: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ),
            ),
          );
        },
      ),
      body: Stack(
        children: [
          if (_ready) ...[
            // Contenido: ocupa toda la pantalla; el fondo pasa tras la barra.
            Positioned.fill(
              child: SingleChildScrollView(
                key: _scrollViewKey,
                controller: _scrollController,
                child: _LandingBackground(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RepaintBoundary(
                        child: HeroSection(
                          key: _inicioKey,
                          topInset: CustomNavbar.reservedHeight,
                          onStartPressed: _navigateToRegister,
                          onLoginPressed: _navigateToLogin,
                        ),
                      ),
                      RepaintBoundary(child: const StatsBarSection()),
                      RepaintBoundary(
                        child: FeaturesSection(key: _solucionesKey),
                      ),
                      RepaintBoundary(
                        child: SecuritySection(key: _seguridadKey),
                      ),
                      RepaintBoundary(child: ContactSection(key: _contactoKey)),
                      RepaintBoundary(
                        child: CtaAndFooterSection(
                          onRegisterPressed: _navigateToRegister,
                          onContactPressed: () =>
                              _scrollToSection(_contactoKey),
                          onSecurityPressed: () =>
                              _scrollToSection(_seguridadKey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Barra flotante: link activo (scroll spy), sombra y progreso.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _activeLink,
                    _scrolled,
                    _progress,
                  ]),
                  builder: (context, _) {
                    return CustomNavbar(
                      activeLink: _activeLink.value,
                      isScrolled: _scrolled.value,
                      scrollProgress: _progress.value,
                      onInicioPressed: () => _scrollToSection(_inicioKey),
                      onSolucionesPressed: () =>
                          _scrollToSection(_solucionesKey),
                      onSeguridadPressed: () => _scrollToSection(_seguridadKey),
                      onContactoPressed: () => _scrollToSection(_contactoKey),
                      onLoginPressed: _navigateToLogin,
                      onRegisterPressed: _navigateToRegister,
                    );
                  },
                ),
              ),
            ),
          ],
          // Pantalla de carga: se desvanece cuando todo está listo.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _ready
                  ? const SizedBox.shrink(key: ValueKey<String>('ready'))
                  : const _Preloader(key: ValueKey<String>('loading')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Color único para las secciones claras. Al no usar gradientes ni reiniciar
/// el color por sección, desaparecen las divisiones horizontales.
class _LandingBackground extends StatelessWidget {
  final Widget child;
  const _LandingBackground({required this.child});

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: const Color(0xFFF2F7FD), child: child);
}

/// Skeleton estructural de la landing: reutiliza el shimmer del proyecto.
/// No se muestra por una duración arbitraria adicional: desaparece al terminar
/// el precargado de imágenes y fuentes (ver _preload de HomeScreen).
class _Preloader extends StatelessWidget {
  const _Preloader({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 920;
    final side = size.width < 480 ? 18.6 : 39.06;

    return ColoredBox(
      color: const Color(0xFFF2F7FD),
      child: SafeArea(
        child: SkeletonScope(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: side, vertical: 16.74),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1311.3),
                child: Column(
                  children: [
                    _LandingNavbarSkeleton(compact: compact),
                    SizedBox(height: compact ? 35.34 : 68.82),
                    LayoutBuilder(
                      builder: (context, c) {
                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _LandingTextSkeleton(),
                              const SizedBox(height: 32.55),
                              _LandingImageSkeleton(compact: compact),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              flex: 46,
                              child: _LandingTextSkeleton(),
                            ),
                            const SizedBox(width: 33.48),
                            Expanded(
                              flex: 54,
                              child: _LandingImageSkeleton(compact: compact),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 51.15),
                    const _LandingValueSkeleton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandingNavbarSkeleton extends StatelessWidget {
  final bool compact;
  const _LandingNavbarSkeleton({required this.compact});

  @override
  Widget build(BuildContext context) {
    return SkeletonCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16.74 : 26.04,
        vertical: 11.16,
      ),
      child: Row(
        children: [
          const SkeletonBox(width: 39.06, height: 39.06, radius: 12.09),
          const SizedBox(width: 11.16),
          SkeletonBox(
            width: compact ? 91.14 : 125.55,
            height: 20.46,
            radius: 7.44,
          ),
          const Spacer(),
          if (!compact) ...[
            const SkeletonBox(width: 66.96, height: 13.95),
            const SizedBox(width: 26.04),
            const SkeletonBox(width: 88.35, height: 13.95),
            const SizedBox(width: 26.04),
            const SkeletonBox(width: 66.96, height: 13.95),
            const SizedBox(width: 26.04),
            const SkeletonBox(width: 88.35, height: 13.95),
            const SizedBox(width: 27.9),
          ],
          SkeletonBox(
            width: compact ? 39.06 : 124.62,
            height: 39.99,
            radius: 21.39,
          ),
        ],
      ),
    );
  }
}

class _LandingTextSkeleton extends StatelessWidget {
  const _LandingTextSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: w * 0.62, height: 33.48, radius: 20.46),
            const SizedBox(height: 26.97),
            SkeletonBox(width: w * 0.93, height: 48.36, radius: 11.16),
            const SizedBox(height: 11.16),
            SkeletonBox(width: w * 0.84, height: 48.36, radius: 11.16),
            const SizedBox(height: 11.16),
            SkeletonBox(width: w * 0.52, height: 48.36, radius: 11.16),
            const SizedBox(height: 26.04),
            SkeletonBox(width: w * 0.88, height: 15.81),
            const SizedBox(height: 11.16),
            SkeletonBox(width: w * 0.73, height: 15.81),
            const SizedBox(height: 29.76),
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 49.29, radius: 16.74)),
                const SizedBox(width: 11.16),
                Expanded(child: SkeletonBox(height: 49.29, radius: 16.74)),
              ],
            ),
            const SizedBox(height: 31.62),
            Row(
              children: [
                const SkeletonBox(width: 37.2, height: 37.2, radius: 11.16),
                const SizedBox(width: 11.16),
                SkeletonBox(width: w * 0.31, height: 13.02),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LandingImageSkeleton extends StatelessWidget {
  final bool compact;
  const _LandingImageSkeleton({required this.compact});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: compact ? 1.44 : 1.48,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned.fill(child: SkeletonBox(radius: 29.76)),
          Positioned(
            top: 16.74,
            right: 16.74,
            child: SkeletonCard(
              padding: const EdgeInsets.all(11.16),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: 27.9, height: 27.9, radius: 7.44),
                  SizedBox(width: 9.3),
                  SkeletonBox(width: 69.75, height: 12.09),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 16.74,
            left: 16.74,
            child: SkeletonCard(
              padding: const EdgeInsets.all(11.16),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: 27.9, height: 27.9, radius: 7.44),
                  SizedBox(width: 9.3),
                  SkeletonBox(width: 85.56, height: 12.09),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingValueSkeleton extends StatelessWidget {
  const _LandingValueSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth < 700 ? 1 : 3;
        final width = (c.maxWidth - (count - 1) * 16) / count;
        return Wrap(
          spacing: 14.88,
          runSpacing: 14.88,
          children: [
            for (var i = 0; i < 3; i++)
              SizedBox(
                width: width,
                child: SkeletonCard(
                  child: const Row(
                    children: [
                      SkeletonBox(width: 35.34, height: 35.34, radius: 11.16),
                      SizedBox(width: 11.16),
                      Expanded(child: SkeletonBox(height: 13.95)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
