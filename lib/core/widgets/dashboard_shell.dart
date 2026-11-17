import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import 'notification_bell.dart';
import '../../features/landing/presentation/widgets/landing_section_background.dart';

//
// Ubicación sugerida: lib/core/widgets/dashboard_shell.dart
//
// Layout único para todos los dashboards (administrador, representante, ...).
// Centraliza: barra lateral colapsable, drawer en pantallas pequeñas,
// encabezado superior, menú de cuenta, confirmación de cierre de sesión,
// breakpoints y los widgets de hover reutilizables.
//

/// Breakpoints compartidos por todas las pantallas del dashboard.
class Breakpoints {
  Breakpoints._();

  /// Por debajo: teléfono.
  static const double compact = 640;

  /// Por encima: la barra lateral es fija. Por debajo: drawer con botón menú.
  static const double desktop = 900;

  /// Por encima: la barra lateral arranca expandida (el usuario puede alternarla).
  static const double wide = 1200;

  static bool isCompact(double w) => w < compact;
  static bool isDesktop(double w) => w > desktop;

  /// Márgenes laterales del dashboard compartidos entre todos los roles.
  /// Más espacio en escritorio sin restar demasiado ancho en móviles.
  static double pagePadding(double w) =>
      w < compact ? 18 : (w <= desktop ? 28 : (w < wide ? 36 : 48));

  /// El saludo se mantiene cerca del encabezado; aumentamos principalmente
  /// los márgenes laterales y el espacio inferior para una interfaz aireada.
  static EdgeInsets pageInsets(double w) => EdgeInsets.fromLTRB(
    pagePadding(w),
    w < compact ? 16 : 20,
    pagePadding(w),
    w < compact ? 24 : 36,
  );
}

/// Ítem de navegación de la barra lateral.
class DashboardNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  const DashboardNavItem(this.icon, this.activeIcon, this.title);
}

const Color _navy = AppColors.sidebarBottom;
const Color _navActive = AppColors.primaryBlue;
const Color _danger = AppColors.errorRed;
const Duration _hoverDuration = Duration(milliseconds: 150);

// Barra lateral: tamaños y animación de contraer / expandir.
const double _sidebarExpandedW = 260.0;
const double _sidebarCollapsedW = 76.0;
// Relleno horizontal interno: con 76 px queda un carril de 44 px, justo el
// tamaño del indicador activo cuando el menú está plegado.
const double _sidebarPadX = 16.0;
const double _railInnerExpanded = _sidebarExpandedW - 2 * _sidebarPadX; // 228

// Margen visual del menú flotante. El ancho expandido compensa los
// 16 px adicionales de separación izquierda para conservar el área principal.
const double _sidebarInsetLeft = 32.0;
const double _sidebarInsetRight = 8.0;
const double _sidebarInsetVertical = 16.0;

// Ondas originales de la landing con una intensidad del 20 %.
// 0.0 = invisibles; 1.0 = intensidad completa de la landing.
const double _dashboardBackdropOpacity = 0.50;

// Si es true, la animación se desactiva cuando el sistema pide "reducir
// movimiento" (en Windows: Accesibilidad > Efectos visuales > Efectos de
// animación apagado). Déjalo en false para que SIEMPRE se vea la animación.
const bool _respectReduceMotion = false;

// Movimiento del menú: curva tipo "spring suave" (sin rebote) y una sola
// duración para expandir y contraer. Al contraer se usa la curva invertida
// (`flipped`), de modo que el arranque sea igual de ágil en ambos sentidos.
const double _navMs = 300;
const Duration _navDuration = Duration(milliseconds: 300);
const Cubic _navCurve = Cubic(0.22, 1.0, 0.36, 1.0);

// Coreografía de las etiquetas (se miden en tiempo, no en la curva de ancho):
//   contraer → desaparecen en los primeros 150 ms
//   expandir → esperan 100 ms y aparecen durante 200 ms
const double _labelOutMs = 120;
const double _labelInDelayMs = 65;
const double _labelInMs = 170;
const double _labelShift = 8; // px de desplazamiento horizontal

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Fondo vectorial animado del menú lateral.
///
/// Las dos ondas avanzan de izquierda a derecha a la misma velocidad.
/// La onda inferior sigue a la superior con un desfase del 6 % del ciclo.
/// Además, la altura del relleno crece y disminuye lentamente: la onda
/// superior asciende más que la inferior, creando un efecto de marea.
/// El ciclo es periódico tanto en X como en Y, por lo que no hay saltos.
/// Solo se vuelve a pintar el fondo, no el contenido de la barra.
class _SidebarWavePainter extends CustomPainter {
  final Animation<double> progress;

  _SidebarWavePainter({required this.progress}) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final bounds = Offset.zero & size;
    final h = size.height;
    final w = size.width;

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF152E58), Color(0xFF0E2144), Color(0xFF0B1A37)],
          stops: [0.0, 0.54, 1.0],
        ).createShader(bounds),
    );

    canvas.save();
    canvas.clipRect(bounds);

    // Las ondas comparten reloj, longitud, velocidad y dirección.
    final wavelength = math.max(w * 2.0, 180.0);
    const phase = -math.pi / 2;
    const lagFraction = 0.06; // ~1,7 s en un ciclo de 28 s.
    const phaseLag = 2 * math.pi * lagFraction;

    // El factor va de 0 a 1 y vuelve a 0 sin cambios bruscos de velocidad.
    // La onda posterior sube más alto y se ensancha más que la inferior.
    final upperExpansion = _tidalExpansion(progress.value);
    final lowerExpansion = _tidalExpansion(progress.value - lagFraction);

    // Movimiento vertical más contenido: las olas permanecen en la mitad
    // inferior, incluso cuando llegan a su altura máxima.
    final upperRise = math.min(36.0, h * 0.055) * upperExpansion;
    final lowerRise = math.min(20.0, h * 0.035) * lowerExpansion;

    // Capa posterior (más alta): se desplaza en X y crece desde abajo.
    _paintMovingWave(
      canvas,
      size,
      baseY: math.max(h * 0.41, h - 295.0) + 60 - upperRise,
      amplitude: 40 + 7 * upperExpansion,
      wavelength: wavelength,
      phaseOffset: phase,
      paint: Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF294975).withValues(alpha: 0.44),
            const Color(0xFF17355F).withValues(alpha: 0.36),
          ],
        ).createShader(bounds),
    );

    // Capa delantera: se mueve en el mismo sentido, un poco retrasada.
    // Su expansión vertical es deliberadamente menor que la superior.
    _paintMovingWave(
      canvas,
      size,
      baseY: math.max(h * 0.49, h - 200.0) + 30 - lowerRise,
      amplitude: 33 + 5 * lowerExpansion,
      wavelength: wavelength,
      phaseOffset: phase + phaseLag,
      paint: Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF31578A).withValues(alpha: 0.36),
            const Color(0xFF1D3E6F).withValues(alpha: 0.25),
          ],
        ).createShader(bounds),
    );

    canvas.restore();
  }

  /// Expansión de tipo marea: 0 → 1 → 0 en un solo ciclo suave.
  double _tidalExpansion(double t) => (1 - math.cos(2 * math.pi * t)) / 2;

  void _paintMovingWave(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double amplitude,
    required double wavelength,
    required double phaseOffset,
    required Paint paint,
  }) {
    // Una longitud de onda exacta por ciclo, sin corte al reiniciarse.
    // Ambas capas comparten el mismo desplazamiento hacia la derecha.
    final shiftX = progress.value * wavelength;
    final firstTile = ((-shiftX) / wavelength).floor() - 1;
    final lastTile = ((size.width - shiftX) / wavelength).ceil() + 1;
    // Menos vértices: mantiene las ondas sin sobrecargar Canvas en Flutter Web.
    const segments = 48;

    for (var tile = firstTile; tile <= lastTile; tile++) {
      final originX = tile * wavelength + shiftX;
      final curve = Path();
      for (var i = 0; i <= segments; i++) {
        final relativeX = wavelength * i / segments;
        final angle = 2 * math.pi * i / segments + phaseOffset;
        final y = baseY + amplitude * math.sin(angle);
        final x = originX + relativeX;
        if (i == 0) {
          curve.moveTo(x, y);
        } else {
          curve.lineTo(x, y);
        }
      }
      curve
        ..lineTo(originX + wavelength, size.height)
        ..lineTo(originX, size.height)
        ..close();
      canvas.drawPath(curve, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SidebarWavePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class DashboardShell extends StatefulWidget {
  final List<DashboardNavItem> navItems;
  final int selectedIndex;
  final ValueChanged<int> onNavSelected;

  /// Nombre de la institución (tarjeta superior de la barra lateral).
  final String schoolName;

  /// Datos del usuario (pie de la barra lateral, encabezado y menú de cuenta).
  final String userName;
  final String userInitials;
  final String userRole;

  /// Se ejecuta SOLO después de que el usuario confirma en el diálogo.
  final VoidCallback onLogout;

  /// Texto de la caja de búsqueda del encabezado.
  final String searchHint;

  /// Widgets extra del encabezado (ej. tasa BCV, período). Se ocultan en
  /// pantallas angostas (<= 760 px) para no desbordar.
  final List<Widget> headerActions;

  /// Se ejecuta al tocar una notificación de la campana (p. ej. para
  /// cambiar de pestaña). Si es null, solo se marca como leída.
  final ValueChanged<AppNotification>? onNotificationTap;

  /// Acción del ítem "Soporte y seguridad". Si es null muestra un aviso.
  final VoidCallback? onSupportTap;

  /// Si se indica, el menú de cuenta muestra la opción "Editar perfil" y
  /// ejecuta esta acción al elegirla. Si es null, la opción no aparece.
  final VoidCallback? onEditProfile;

  /// Contenido de la página.
  final Widget body;

  const DashboardShell({
    super.key,
    required this.navItems,
    required this.selectedIndex,
    required this.onNavSelected,
    required this.schoolName,
    required this.userName,
    required this.userInitials,
    required this.userRole,
    required this.onLogout,
    required this.body,
    this.searchHint = 'Buscar...',
    this.headerActions = const [],
    this.onNotificationTap,
    this.onSupportTap,
    this.onEditProfile,
  });

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell>
    with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Un único reloj para las dos capas del menú: sus ondas quedan sincronizadas
  // también durante la animación de expandir/contraer.
  late final AnimationController _waveController;
  bool _drawerOpen = false;

  // 0 = menú plegado, 1 = desplegado. Lineal: las curvas se aplican abajo.
  late final AnimationController _navController = AnimationController(
    vsync: this,
    duration: _navDuration,
  );
  // Ancho y giro del chevron (sin rebote, simétrico al abrir y cerrar).
  late final CurvedAnimation _navWidth = CurvedAnimation(
    parent: _navController,
    curve: _navCurve,
    reverseCurve: _navCurve.flipped,
  );
  // Opacidad de etiquetas: ventanas de tiempo distintas según el sentido.
  late final CurvedAnimation _navLabels = CurvedAnimation(
    parent: _navController,
    curve: const Interval(
      _labelInDelayMs / _navMs,
      (_labelInDelayMs + _labelInMs) / _navMs,
      curve: Curves.easeOut,
    ),
    reverseCurve: const Interval(
      1 - _labelOutMs / _navMs,
      1.0,
      curve: Curves.easeIn,
    ),
  );
  bool? _navTarget;

  // Reducir carga gráfica mientras el menú cambia de tamaño.
  // El layout principal continúa usando el ancho REAL en cada fotograma;
  // no se conserva un viewport ficticio que termine cortando las tarjetas.
  void _onNavAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.reverse) {
      _waveController.stop();
    } else if (mounted) {
      _syncWaveAnimation();
    }
  }

  /// Lleva el controlador al estado pedido. La primera vez salta sin animar;
  /// después anima (también cuando el cambio viene de redimensionar la ventana).
  void _syncSidebar(bool expanded, bool reduceMotion) {
    if (_navTarget == expanded) return;
    final first = _navTarget == null;
    _navTarget = expanded;
    if (first) {
      _navController.value = expanded ? 1.0 : 0.0;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _navTarget ?? expanded;
      _navController.duration = reduceMotion ? Duration.zero : _navDuration;
      if (target) {
        _navController.forward();
      } else {
        _navController.reverse();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );
    _navController.addStatusListener(_onNavAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWaveAnimation();
  }

  void _syncWaveAnimation() {
    // Evita trabajo en móviles cuando el cajón está cerrado y respeta
    // «Reducir movimiento» y TickerMode (por ejemplo, rutas inactivas).
    final enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        !_navController.isAnimating &&
        (Breakpoints.isDesktop(MediaQuery.sizeOf(context).width) ||
            _drawerOpen);
    if (enabled) {
      if (!_waveController.isAnimating) _waveController.repeat();
    } else {
      _waveController.stop();
      if (_waveController.value != 0) _waveController.value = 0;
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _navController.removeStatusListener(_onNavAnimationStatus);
    _navWidth.dispose();
    _navLabels.dispose();
    _navController.dispose();
    super.dispose();
  }

  /// null = automático según el ancho; true/false = el usuario lo alternó.
  bool? _expandedOverride;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isDesktop = Breakpoints.isDesktop(w);
    final expanded = _expandedOverride ?? (w >= Breakpoints.wide);
    final reduceMotion =
        _respectReduceMotion && MediaQuery.disableAnimationsOf(context);
    _syncSidebar(expanded, reduceMotion);

    // La geometría del dashboard responde al ancho real del Row. Se reutiliza
    // el árbol en AnimatedBuilder para evitar reconstruirlo innecesariamente,
    // pero el layout se recalcula cuando cambian las restricciones. Esto evita
    // que 4 tarjetas queden fuera de la ventana al expandir el menú.
    final main = Expanded(
      child: Column(
        children: [
          _buildTopHeader(isDesktop),
          // Desvanece el contenido al llegar a la cabecera para evitar
          // el corte horizontal brusco durante el desplazamiento.
          // El fondo compartido queda fuera de la máscara y sigue continuo.
          Expanded(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                final fadeStop = bounds.height > 0
                    ? (32.0 / bounds.height).clamp(0.0, 1.0).toDouble()
                    : 1.0;
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Progresión suave: la opacidad acelera y desacelera
                  // gradualmente, sin un final de degradado marcado.
                  colors: const [
                    Colors.transparent,
                    Color(0xFF1BFFFFFF),
                    Color(0xFF5AFFFFFF),
                    Color(0xFFA5FFFFFF),
                    Color(0xFFE4FFFFFF),
                    Colors.white,
                    Colors.white,
                  ],
                  stops: [
                    0.0,
                    fadeStop * 0.2,
                    fadeStop * 0.4,
                    fadeStop * 0.6,
                    fadeStop * 0.8,
                    fadeStop,
                    1.0,
                  ],
                ).createShader(bounds);
              },
              // Ajusta los breakpoints del contenido al ancho realmente
              // disponible, no al ancho total que incluye el menú.
              // Al cerrar el menú, el dashboard aprovecha el espacio extra.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final original = MediaQuery.of(context);
                  final contentWidth = constraints.maxWidth;
                  return MediaQuery(
                    data: original.copyWith(
                      size: Size(contentWidth, original.size.height),
                    ),
                    child: RepaintBoundary(child: widget.body),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );

    // Misma tipografía Lexend configurada en main.dart. Se aplica también
    // a menú, botones, campos y el contenido de ambos dashboards.
    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        textTheme: GoogleFonts.lexendTextTheme(baseTheme.textTheme),
        primaryTextTheme: GoogleFonts.lexendTextTheme(
          baseTheme.primaryTextTheme,
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.backgroundLight,
        onDrawerChanged: (opened) {
          _drawerOpen = opened;
          _syncWaveAnimation();
        },
        drawer: isDesktop
            ? null
            : Drawer(
                width: 280,
                backgroundColor: _navy,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(26),
                  ),
                ),
                child: SafeArea(
                  child: _buildSidebar(t: 1, labels: 1, inDrawer: true),
                ),
              ),
        // Las ondas de la landing se reutilizan, sin imágenes ni assets.
        // Quedan DETRÁS del contenido y no interceptan clics/scroll.
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _dashboardBackdropOpacity,
                    child: LandingBackdrop(style: LandingWaveStyle.hero),
                  ),
                ),
              ),
            ),
            // t: 0 = barra contraída, 1 = expandida (curva ya aplicada).
            AnimatedBuilder(
              animation: _navController,
              child: main,
              builder: (context, mainChild) {
                final t = _navWidth.value;
                final labels = _navLabels.value;
                final sidebarW = _lerp(
                  _sidebarCollapsedW,
                  _sidebarExpandedW,
                  t,
                );
                return Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isDesktop)
                          _buildAnimatedSidebar(
                            t: t,
                            labels: labels,
                            width: sidebarW,
                            tooltips: !expanded,
                          ),
                        mainChild!,
                      ],
                    ),
                    if (isDesktop)
                      Positioned(
                        left: _sidebarInsetLeft + sidebarW - 12,
                        top: 104,
                        child: _buildCollapseButton(expanded, t),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  //
  // Cierre de sesión con confirmación
  //
  // Mantiene el botón «Cerrar sesión» activo mientras el diálogo está abierto,
  // aunque el mouse se haya movido fuera de la barra lateral.
  bool _logoutDialogOpen = false;

  Future<void> _confirmLogout() async {
    if (_logoutDialogOpen) return;
    setState(() => _logoutDialogOpen = true);

    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (_) => const _LogoutConfirmDialog(),
      );
    } finally {
      // También se desactiva al pulsar Cancelar, Escape o fuera del diálogo.
      if (mounted) setState(() => _logoutDialogOpen = false);
    }

    if (!mounted) return;
    if (confirmed == true) widget.onLogout();
  }

  //
  // Botón para colapsar / expandir
  //
  Widget _buildCollapseButton(bool expanded, double t) {
    return Semantics(
      button: true,
      label: expanded ? 'Contraer menú' : 'Expandir menú',
      child: HoverBuilder(
        builder: (context, hovered) => AnimatedScale(
          scale: hovered ? 1.15 : 1.0,
          duration: _hoverDuration,
          child: InkWell(
            onTap: () => setState(() => _expandedOverride = !expanded),
            customBorder: const CircleBorder(),
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: AnimatedContainer(
              duration: _hoverDuration,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: hovered ? AppColors.primaryBlue : _navy,
                shape: BoxShape.circle,
                border: Border.all(
                  color: hovered ? AppColors.primaryBlue : Colors.white24,
                ),
              ),
              child: Transform.rotate(
                // Misma curva que el ancho: gira 180° sincronizado con el menú.
                angle: (1 - t) * math.pi,
                child: const Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  //
  // Barra lateral
  //
  /// Barra lateral de escritorio animada.
  ///
  /// UNA sola capa: el ancho sigue a [t] (0 = plegada, 1 = desplegada) y cada
  /// elemento se adapta a ese ancho. El indicador activo es el propio carril
  /// del ítem (228 px → 44 px), así que "se contrae" de verdad en vez de
  /// fundirse con otro. Los iconos mantienen su eje (x = 38 px) en ambos
  /// estados; solo las etiquetas se desvanecen ([labels]) y se desplazan.
  /// Todo se recorta al radio del contenedor.
  Widget _buildAnimatedSidebar({
    required double t,
    required double labels,
    required double width,
    required bool tooltips,
  }) {
    return RepaintBoundary(
      child: SizedBox(
        width: width + _sidebarInsetLeft + _sidebarInsetRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _sidebarInsetLeft,
            _sidebarInsetVertical,
            _sidebarInsetRight,
            _sidebarInsetVertical,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.88),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkNavy.withValues(alpha: 0.20),
                  blurRadius: 28,
                  spreadRadius: 1,
                  offset: const Offset(6, 10),
                ),
                BoxShadow(
                  color: AppColors.darkNavy.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(2, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: _buildSidebar(t: t, labels: labels, tooltips: tooltips),
            ),
          ),
        ),
      ),
    );
  }

  /// Contenido del menú. [t] y [labels] son 1 en el cajón móvil.
  Widget _buildSidebar({
    required double t,
    required double labels,
    bool tooltips = false,
    bool inDrawer = false,
  }) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Las ondas viajan hacia la derecha y expanden su altura
          // suavemente; la posterior llega más arriba que la delantera.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _SidebarWavePainter(progress: _waveController),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _sidebarPadX,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sidebarInstitution(
                  t: t,
                  labels: labels,
                  tooltips: tooltips,
                  inDrawer: inDrawer,
                ),
                SizedBox(height: _lerp(28, 34, t)),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    // Sin recorte: la sombra del indicador activo no se corta.
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < widget.navItems.length; i++)
                        _navItem(
                          i,
                          labels: labels,
                          tooltips: tooltips,
                          inDrawer: inDrawer,
                        ),
                    ],
                  ),
                ),
                _supportItem(
                  t: t,
                  labels: labels,
                  tooltips: tooltips,
                  inDrawer: inDrawer,
                ),
                const SizedBox(height: 16),
                _sidebarLogout(
                  labels: labels,
                  tooltips: tooltips,
                  inDrawer: inDrawer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Contenedor rígido: el contenido mantiene SIEMPRE su ancho desplegado y
  /// el carril solo lo "revela" (equivale a un `min-width` interno con
  /// `overflow: hidden`). Así el texto no se re-ajusta mientras se encoge.
  Widget _rigid(bool inDrawer, Widget child) => inDrawer
      ? child
      : ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: _railInnerExpanded,
            maxWidth: _railInnerExpanded,
            child: child,
          ),
        );

  /// Etiqueta: fundido + desplazamiento horizontal de 8 px, sin saltos de línea.
  Widget _fadeLabel(double labels, Widget child) => Opacity(
    opacity: labels,
    child: Transform.translate(
      offset: Offset(-_labelShift * (1 - labels), 0),
      child: child,
    ),
  );

  /// Logotipo HD (1024 x 1024) reconstruido en formato vectorial.
  /// Se representa sin ClipRRect para no cortar detalles en los bordes.
  /// El asset usa la misma ruta que el anterior: no requiere cambiar imports.
  Widget _brandMark() {
    return SizedBox(
      width: 70,
      height: 70,
      child: Image.asset(
        'assets/images/logo_edupago.png',
        width: 70,
        height: 70,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        semanticLabel: 'Logo de EduPago',
        errorBuilder: (context, error, stackTrace) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 70,
          ),
        ),
      ),
    );
  }

  /// Cabecera de marca: hover sutil sobre toda la tarjeta. Al pulsarla se
  /// regresa al primer apartado del menú. Altura y logo crecen con [t].
  Widget _sidebarInstitution({
    required double t,
    required double labels,
    required bool tooltips,
    required bool inDrawer,
  }) {
    final logo = _lerp(36, 46, t);
    return _SideTooltip(
      message: 'EduPago · Inicio',
      enabled: tooltips,
      child: HoverBuilder(
        cursor: widget.navItems.isEmpty
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        builder: (context, hovered) => Semantics(
          button: widget.navItems.isNotEmpty,
          label: 'EduPago, ir al inicio',
          child: _SidebarPressSurface(
            onTap: widget.navItems.isEmpty ? null : () => _select(0, inDrawer),
            radius: 20,
            pressedColor: Colors.white.withValues(alpha: 0.13),
            child: SizedBox(
              height: _lerp(54, 68, t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hovered
                        ? const [Color(0xFF2F568B), Color(0xFF224777)]
                        : const [Color(0xFF254B7F), Color(0xFF1B3868)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: hovered ? 0.34 : 0.12,
                    ),
                  ),
                  boxShadow: hovered
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF60A5FA,
                            ).withValues(alpha: 0.13),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: _rigid(
                  inDrawer,
                  Row(
                    children: [
                      SizedBox(width: _lerp(3, 10, t)),
                      SizedBox(
                        width: logo,
                        height: logo,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: _brandMark(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _fadeLabel(
                          labels,
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'EduPago',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.schoolName.isEmpty
                                    ? 'Tu colegio, más cerca'
                                    : widget.schoolName,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.onDarkMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(int index, bool inDrawer) {
    widget.onNavSelected(index);
    if (inDrawer) _scaffoldKey.currentState?.closeDrawer();
  }

  /// Ítem de navegación. El carril mide 228 px (desplegado) o 44 px (plegado)
  /// y es a la vez el indicador activo; el icono queda fijo a 12 px del borde
  /// (centro en x = 22 del carril de 44), por eso no se desplaza al plegar.
  ///
  /// Hover: fondo y borde sutiles, el icono crece un 12 % y la etiqueta se
  /// adelanta 3 px. Plegado: tooltip lateral con 150 ms de retraso.
  Widget _navItem(
    int index, {
    required double labels,
    required bool tooltips,
    required bool inDrawer,
  }) {
    final item = widget.navItems[index];
    final selected = widget.selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _SideTooltip(
        message: item.title,
        enabled: tooltips,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) {
            final lit = selected || hovered;
            return Semantics(
              button: true,
              selected: selected,
              label: item.title,
              excludeSemantics: true,
              // La selección se anima sobre todo el botón; la pulsación no genera ondas.
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? _navActive
                      : (hovered
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (!selected && hovered)
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.transparent,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: _navActive.withValues(alpha: 0.40),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : const [],
                ),
                child: _SidebarPressSurface(
                  onTap: () => _select(index, inDrawer),
                  radius: 14,
                  pressedColor: selected
                      ? Colors.white.withValues(alpha: 0.16)
                      : _navActive.withValues(alpha: 0.34),
                  child: _rigid(
                    inDrawer,
                    Row(
                      children: [
                        const SizedBox(width: 12),
                        AnimatedScale(
                          scale: (hovered && !selected) ? 1.12 : 1.0,
                          duration: _hoverDuration,
                          curve: Curves.easeOut,
                          child: Icon(
                            selected ? item.activeIcon : item.icon,
                            color: lit ? Colors.white : AppColors.onDarkMuted,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _fadeLabel(
                            labels,
                            AnimatedSlide(
                              offset: (hovered && !selected)
                                  ? const Offset(0.03, 0)
                                  : Offset.zero,
                              duration: _hoverDuration,
                              curve: Curves.easeOut,
                              child: Text(
                                item.title,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: lit
                                      ? Colors.white
                                      : AppColors.onDarkMuted,
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Tarjeta de ayuda con resaltado azul en hover. Plegada, queda como un
  /// botón de 44 px con el icono centrado (los dos iconos se funden).
  Widget _supportItem({
    required double t,
    required double labels,
    required bool tooltips,
    required bool inDrawer,
  }) {
    void onTap() {
      if (widget.onSupportTap != null) {
        widget.onSupportTap!();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El canal de soporte todavía no está habilitado.'),
          ),
        );
      }
    }

    return _SideTooltip(
      message: '¿Necesitas ayuda?',
      enabled: tooltips,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => Semantics(
          button: true,
          label: '¿Necesitas ayuda? Abrir soporte',
          excludeSemantics: true,
          child: _SidebarPressSurface(
            onTap: onTap,
            radius: 14,
            pressedColor: const Color(0xFF60A5FA).withValues(alpha: 0.17),
            child: SizedBox(
              height: _lerp(AppSizes.minTarget.toDouble(), 62, t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: hovered
                      ? const Color(0xFF3564A8).withValues(alpha: 0.70)
                      : const Color(0xFF213F72).withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hovered
                        ? const Color(0xFF8DBBFF)
                        : const Color(0xFF45669D),
                  ),
                  boxShadow: hovered
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF60A5FA,
                            ).withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: _rigid(
                  inDrawer,
                  Row(
                    children: [
                      const SizedBox(width: 9),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: 1 - labels,
                              child: const Icon(
                                Icons.headset_mic_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            Opacity(
                              opacity: labels,
                              child: const Icon(
                                Icons.info_rounded,
                                color: Color(0xFF75ACFF),
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _fadeLabel(
                          labels,
                          const Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '¿Necesitas ayuda?',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Estamos para ti',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: AppColors.onDarkMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _fadeLabel(
                        labels,
                        Icon(
                          Icons.chevron_right,
                          color: hovered ? Colors.white : AppColors.onDarkMuted,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Última acción de la barra lateral: salir sin mostrar la cuenta.
  /// El avatar y el menú de perfil se conservan exclusivamente en el header.
  /// Última acción de la barra lateral: Cerrar sesión.
  /// Mismo estado de selección que el resto del menú, pero en rojo.
  Widget _sidebarLogout({
    required double labels,
    required bool tooltips,
    required bool inDrawer,
  }) {
    const hoverRed = AppColors.errorRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.17)),
        const SizedBox(height: 12),
        _SideTooltip(
          message: 'Cerrar sesión',
          enabled: tooltips,
          child: HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) {
              final active = hovered || _logoutDialogOpen;
              return Semantics(
                button: true,
                label: 'Cerrar sesión',
                selected: _logoutDialogOpen,
                excludeSemantics: true,
                // Sin AnimatedContainer en el fondo ni en la sombra.
                // Al salir del hover desaparecen al instante, sin pasar por vino.
                child: SizedBox(
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: active ? hoverRed : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: hoverRed.withValues(alpha: 0.30),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : const [],
                    ),
                    child: _SidebarPressSurface(
                      onTap: _confirmLogout,
                      radius: 14,
                      // Sin tinte residual de pulsación al retirar el cursor.
                      // El estado del diálogo mantiene el rojo al confirmar.
                      pressedColor: Colors.transparent,
                      child: _rigid(
                        inDrawer,
                        Row(
                          children: [
                            const SizedBox(width: 12),
                            AnimatedScale(
                              scale: active ? 1.12 : 1.0,
                              duration: _hoverDuration,
                              curve: Curves.easeOut,
                              child: Icon(
                                Icons.logout_rounded,
                                color: active
                                    ? Colors.white
                                    : AppColors.onDarkMuted,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _fadeLabel(
                                labels,
                                AnimatedSlide(
                                  offset: active
                                      ? const Offset(0.03, 0)
                                      : Offset.zero,
                                  duration: _hoverDuration,
                                  curve: Curves.easeOut,
                                  child: Text(
                                    'Cerrar sesión',
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: active
                                          ? Colors.white
                                          : AppColors.onDarkMuted,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  //
  // Menú de cuenta (avatar). Muestra al usuario y la acción de salir;
  // la salida siempre pasa por el diálogo de confirmación.
  //
  // Menú propio (no PopupMenuButton) para poder animarlo desde su ancla:
  //   · opensUpwards = true  → nace en el avatar y SUBE (de abajo hacia arriba)
  //   · opensUpwards = false → nace debajo del botón y BAJA
  //
  Widget _userMenu({required Widget child, bool opensUpwards = false}) {
    return Builder(
      builder: (anchorContext) => Tooltip(
        message: 'Cuenta',
        child: Semantics(
          button: true,
          label: 'Cuenta',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showAccountMenu(anchorContext, opensUpwards),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAccountMenu(
    BuildContext anchorContext,
    bool opensUpwards,
  ) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(context);
    const gap = 8.0;
    const menuW = _AccountMenuPanel.width;

    final left = rect.left
        .clamp(8.0, math.max(8.0, screen.width - menuW - 8))
        .toDouble();
    final right = (screen.width - rect.right)
        .clamp(8.0, math.max(8.0, screen.width - menuW - 8))
        .toDouble();

    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar menú de cuenta',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final panel = _AccountMenuPanel(
          userName: widget.userName,
          userInitials: widget.userInitials,
          userRole: widget.userRole,
          showEditProfile: widget.onEditProfile != null,
        );

        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned(
                left: opensUpwards ? left : null,
                right: opensUpwards ? null : right,
                top: opensUpwards ? null : rect.bottom + gap,
                bottom: opensUpwards ? screen.height - rect.top + gap : null,
                child: AnimatedBuilder(
                  animation: animation,
                  child: panel,
                  builder: (context, child) {
                    final reversing =
                        animation.status == AnimationStatus.reverse;
                    final v =
                        (reversing ? Curves.easeInCubic : Curves.easeOutCubic)
                            .transform(
                              animation.value.clamp(0.0, 1.0).toDouble(),
                            );
                    return Opacity(
                      opacity: v,
                      child: Transform.translate(
                        // Pequeño desplazamiento en el sentido de la apertura.
                        offset: Offset(0, (1 - v) * (opensUpwards ? 12 : -12)),
                        child: ClipRect(
                          clipper: _RevealClipper(v, fromBottom: opensUpwards),
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      // La animación la hace el propio pageBuilder; aquí no se añade otra.
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    );

    if (!mounted) return;
    if (choice == 'profile') widget.onEditProfile?.call();
    if (choice == 'logout') _confirmLogout();
  }

  //
  // Encabezado superior
  //
  void _searchSections(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return;
    final match = widget.navItems.indexWhere((item) {
      final title = item.title.toLowerCase();
      return title.contains(q) ||
          q.contains(title) ||
          (q.contains('mensualidad') && title.contains('pago')) ||
          (q.contains('recibo') && title.contains('documento'));
    });
    if (match >= 0) {
      widget.onNavSelected(match);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No encontramos esa sección. Prueba con el nombre de una opción del menú.',
          ),
        ),
      );
    }
  }

  Widget _buildTopHeader(bool isDesktop) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final compact = Breakpoints.isCompact(availableWidth);
        // Con el menú desplegado hay menos espacio que en la ventana.
        // Mostramos cada elemento solo si cabe en la zona principal.
        final showUserText = availableWidth >= 860;
        final showActions =
            availableWidth >= 1160 + widget.headerActions.length * 125;

        return Container(
          height: 90,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 24,
            vertical: 12,
          ),
          color: Colors.transparent,
          child: Row(
            children: [
              if (!isDesktop) ...[
                IconButton(
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: AppColors.darkNavy,
                  ),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  tooltip: 'Abrir menú',
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: availableWidth >= 1180 ? 800 : 680,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.darkNavy.withValues(alpha: 0.035),
                          blurRadius: 13,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      textInputAction: TextInputAction.search,
                      onSubmitted: _searchSections,
                      decoration: InputDecoration(
                        hintText: compact
                            ? 'Buscar sección...'
                            : 'Buscar sección del menú...',
                        hintStyle: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 23,
                          color: Color(0xFF6381B5),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(27),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5EDF9),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(27),
                          borderSide: const BorderSide(
                            color: AppColors.primaryBlue,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showActions)
                for (final action in widget.headerActions) ...[
                  const SizedBox(width: 12),
                  action,
                ],
              SizedBox(width: availableWidth < 830 ? 10 : 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: NotificationBell(
                  key: const ValueKey('notification-bell'),
                  onOpen: widget.onNotificationTap,
                ),
              ),
              SizedBox(width: availableWidth < 830 ? 10 : 16),
              if (availableWidth >= 680) ...[
                Container(width: 1, height: 34, color: AppColors.cardBorder),
                SizedBox(width: availableWidth < 830 ? 10 : 16),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white),
                ),
                child: _userMenu(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 21,
                        backgroundColor: AppColors.primaryBlue,
                        child: Text(
                          widget.userInitials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (showUserText) ...[
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 155),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.darkNavy,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.userRole,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.darkNavy,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

//
// Diálogo de confirmación de cierre de sesión
//
class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: _danger,
                  size: 26,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '¿Cerrar sesión?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tu sesión actual se cerrará y volverás a la pantalla de inicio. ¿Seguro que quieres salir?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(false),
                      style:
                          OutlinedButton.styleFrom(
                            foregroundColor: AppColors.darkNavy,
                            side: const BorderSide(color: AppColors.cardBorder),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ).copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.hovered)
                                  ? const Color(0xFFF1F5F9)
                                  : Colors.transparent,
                            ),
                          ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style:
                          ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ).copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.hovered)
                                  ? AppColors.errorRed
                                  : _danger,
                            ),
                          ),
                      child: const Text(
                        'Cerrar sesión',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//
// Utilidades de hover reutilizables (solo reaccionan a mouse/trackpad;
// en táctil no cambian nada).
//

/// Pulsación uniforme del menú: la tarjeta completa recibe un tinte suave.
/// Sin splash/ripple circular, también en móvil, teclado y menús desplegables.
/// El material se recorta al radio del botón y el contenido conserva su diseño.
class _SidebarPressSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color pressedColor;

  const _SidebarPressSurface({
    required this.child,
    required this.onTap,
    required this.radius,
    required this.pressedColor,
  });

  @override
  State<_SidebarPressSurface> createState() => _SidebarPressSurfaceState();
}

class _SidebarPressSurfaceState extends State<_SidebarPressSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(widget.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (pressed) {
          if (_pressed != pressed && mounted) {
            setState(() => _pressed = pressed);
          }
        },
        borderRadius: BorderRadius.circular(widget.radius),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: Duration(milliseconds: _pressed ? 85 : 165),
                  curve: Curves.easeOutCubic,
                  color: _pressed ? widget.pressedColor : Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expone si el puntero está encima para construir cualquier widget.
class HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = MouseCursor.defer,
  });

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  void _set(bool v) {
    if (_hovered != v) setState(() => _hovered = v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// Al pasar el mouse sube unos píxeles y proyecta una sombra suave. Se envuelve
/// alrededor de una tarjeta ya hecha. Con `lift: 0` solo aparece la sombra
/// (ideal para contenedores grandes).
class HoverLift extends StatelessWidget {
  final Widget child;
  final double radius;
  final double lift;

  const HoverLift({
    super.key,
    required this.child,
    this.radius = 16,
    this.lift = 2,
  });

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, hovered ? -lift : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: _navy.withValues(alpha: lift == 0 ? 0.06 : 0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: child,
      ),
    );
  }
}

/// Fondo que aparece al pasar el mouse (filas de tabla, listas, chips...).
class HoverTint extends StatelessWidget {
  final Widget child;
  final Color hoverColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const HoverTint({
    super.key,
    required this.child,
    this.hoverColor = const Color(0xFFF1F5F9),
    this.borderRadius = 0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => AnimatedContainer(
        duration: _hoverDuration,
        padding: padding,
        decoration: BoxDecoration(
          color: hovered ? hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: child,
      ),
    );
  }
}

/// Cuadrícula responsive: [wideCols] columnas si el ancho disponible es
/// >= [wideBreak], [mediumCols] si es >= [mediumBreak] y [narrowCols] debajo.
/// Las celdas de una misma fila se estiran a la misma altura.
/// Si [hoverLift] no es null, cada celda sube al pasar el mouse.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> items;
  final int wideCols;
  final int mediumCols;
  final int narrowCols;
  final double wideBreak;
  final double mediumBreak;
  final double gap;
  final double? hoverLift;
  final double hoverRadius;

  const ResponsiveGrid({
    super.key,
    required this.items,
    this.wideCols = 4,
    this.mediumCols = 2,
    this.narrowCols = 1,
    this.wideBreak = 800,
    this.mediumBreak = 520,
    this.gap = 16,
    this.hoverLift,
    this.hoverRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= wideBreak
            ? wideCols
            : (c.maxWidth >= mediumBreak ? mediumCols : narrowCols);
        final rows = <Widget>[];

        for (var i = 0; i < items.length; i += cols) {
          final slice = items.sublist(i, math.min(i + cols, items.length));
          final cells = <Widget>[];

          for (var j = 0; j < cols; j++) {
            if (j > 0) cells.add(SizedBox(width: gap));
            Widget cell = j < slice.length ? slice[j] : const SizedBox();
            if (hoverLift != null && j < slice.length) {
              cell = HoverLift(
                radius: hoverRadius,
                lift: hoverLift!,
                child: cell,
              );
            }
            cells.add(Expanded(child: cell));
          }

          if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          );
        }

        return Column(children: rows);
      },
    );
  }
}

//
// Menú de cuenta: panel, acciones y recorte de la animación de apertura
//

/// Revela el panel desde un borde: desde ABAJO hacia arriba si [fromBottom],
/// o desde ARRIBA hacia abajo si no. Deja un margen para que la sombra no se
/// recorte cuando la animación termina.
class _RevealClipper extends CustomClipper<Rect> {
  final double progress;
  final bool fromBottom;
  const _RevealClipper(this.progress, {required this.fromBottom});

  @override
  Rect getClip(Size size) {
    const m = 40.0;
    final done = progress >= 1.0;
    if (fromBottom) {
      return Rect.fromLTRB(
        -m,
        done ? -m : size.height * (1 - progress),
        size.width + m,
        size.height + m,
      );
    }
    return Rect.fromLTRB(
      -m,
      -m,
      size.width + m,
      done ? size.height + m : size.height * progress,
    );
  }

  @override
  bool shouldReclip(_RevealClipper old) =>
      old.progress != progress || old.fromBottom != fromBottom;
}

class _AccountMenuPanel extends StatelessWidget {
  static const double width = 250;

  final String userName;
  final String userInitials;
  final String userRole;
  final bool showEditProfile;

  const _AccountMenuPanel({
    required this.userName,
    required this.userInitials,
    required this.userRole,
    required this.showEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    // Mismo diseño que el panel de notificaciones: borde marcado, sombra
    // difusa y encabezado con fondo propio.
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF94A3B8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: const Color(0xFFF1F5F9),
                child: SizedBox(
                  height: 68,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.primaryBlue,
                          child: Text(
                            userInitials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.darkNavy,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                userRole,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.cardBorder,
              ),
              if (showEditProfile)
                _AccountMenuAction(
                  icon: Icons.person_outline_rounded,
                  label: 'Editar perfil',
                  color: AppColors.darkNavy,
                  hoverColor: const Color(0xFFF1F5F9),
                  onTap: () => Navigator.of(context).pop('profile'),
                ),
              _AccountMenuAction(
                icon: Icons.logout_rounded,
                label: 'Cerrar sesión',
                color: _danger,
                hoverColor: const Color(0xFFFEF2F2),
                onTap: () => Navigator.of(context).pop('logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountMenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color hoverColor;
  final VoidCallback onTap;

  const _AccountMenuAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SidebarPressSurface(
      onTap: onTap,
      radius: 10,
      pressedColor: hoverColor.withValues(alpha: 0.55),
      child: SizedBox(
        height: 52,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => AnimatedContainer(
            duration: _hoverDuration,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: hovered ? hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tooltip lateral para el menú plegado: aparece a la derecha del elemento
/// tras 150 ms de hover, con fundido y un leve deslizamiento. Se dibuja en el
/// Overlay, por lo que el recorte redondeado del menú no lo corta.
class _SideTooltip extends StatefulWidget {
  const _SideTooltip({
    required this.message,
    required this.enabled,
    required this.child,
  });

  final String message;
  final bool enabled;
  final Widget child;

  @override
  State<_SideTooltip> createState() => _SideTooltipState();
}

class _SideTooltipState extends State<_SideTooltip>
    with SingleTickerProviderStateMixin {
  static const _delay = Duration(milliseconds: 150);

  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeIn,
  );
  Timer? _timer;
  bool _hover = false;

  void _enter() {
    _hover = true;
    if (!widget.enabled) return;
    _timer?.cancel();
    _timer = Timer(_delay, () {
      if (!mounted || !_hover || !widget.enabled) return;
      _portal.show();
      _anim.forward();
    });
  }

  void _exit() {
    _hover = false;
    _timer?.cancel();
    if (_portal.isShowing) {
      _anim.reverse().whenComplete(() {
        if (mounted && !_hover && _portal.isShowing) _portal.hide();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _SideTooltip old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && old.enabled) {
      _timer?.cancel();
      _anim.value = 0;
      if (_portal.isShowing) _portal.hide();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.centerRight,
            followerAnchor: Alignment.centerLeft,
            offset: const Offset(14, 0),
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topLeft,
                widthFactor: 1,
                heightFactor: 1,
                child: FadeTransition(
                  opacity: _curve,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(-0.12, 0),
                      end: Offset.zero,
                    ).animate(_curve),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.darkNavy,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.message,
                        maxLines: 1,
                        softWrap: false,
                        // El Overlay queda fuera del Theme del shell: se fija Lexend.
                        style: GoogleFonts.lexend(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
