import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import 'notification_bell.dart';

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
const Color _navySurface = AppColors.sidebarTop;
const Color _navActive = AppColors.primaryBlue;
const Color _danger = Color(0xFFDC2626);
const Duration _hoverDuration = Duration(milliseconds: 150);

// Barra lateral: tamaños y animación de contraer / expandir.
const double _sidebarExpandedW = 266.0;
const double _sidebarCollapsedW = 78.0;
// Red de seguridad: con los rebotes actuales la barra no baja de ~68 px.
const double _sidebarMinW = 62.0;

// Si es true, la animación se desactiva cuando el sistema pide "reducir
// movimiento" (en Windows: Accesibilidad > Efectos visuales > Efectos de
// animación apagado). Déjalo en false para que SIEMPRE se vea la animación.
const bool _respectReduceMotion = false;

// Al abrir: más larga y con un rebote elegante. Al cerrar: más corta y casi seca.
const Duration _expandDuration = Duration(milliseconds: 650);
const Duration _collapseDuration = Duration(milliseconds: 480);
const Curve _expandCurve = _SpringCurve(damping: 0.62);
const Curve _collapseCurve = _SpringCurve(damping: 0.72);

// Fundido cruzado entre el diseño contraído y el expandido:
// empieza cuando la barra lleva ~18 % del recorrido y termina al ~68 %.
const double _fadeStart = 0.18;
const double _fadeSpan = 0.50;

/// Resorte amortiguado normalizado a la duración de la animación.
///   [damping]  0.5 = muy elástico · 0.6 = elegante · 0.8 = casi sin rebote
///   [settle]   cuánto queda de oscilación al terminar (0.001 = invisible)
/// La frecuencia se deduce de [settle], así que la animación SIEMPRE termina
/// asentada al llegar a t = 1, sin importar el amortiguamiento que elijas.
/// Sobrepaso aprox.: 0.5 → 16 % · 0.6 → 9.5 % · 0.7 → 4.6 % · 0.8 → 1.5 %
class _SpringCurve extends Curve {
  final double damping;
  final double settle;
  const _SpringCurve({this.damping = 0.6, this.settle = 0.001})
    : assert(damping > 0 && damping < 1);

  @override
  double transformInternal(double t) {
    final wn = -math.log(settle) / damping; // frecuencia natural
    final wd = wn * math.sqrt(1 - damping * damping); // frecuencia amortiguada
    final decay = math.exp(-damping * wn * t);
    return 1 -
        decay * (math.cos(wd * t) + (damping * wn / wd) * math.sin(wd * t));
  }
}

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
    const segments = 96;

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
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Un único reloj para las dos capas del menú: sus ondas quedan sincronizadas
  // también durante la animación de expandir/contraer.
  late final AnimationController _waveController;
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );
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
        TickerMode.of(context) &&
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

    // Parte que NO depende de la animación: se construye una sola vez y se
    // reutiliza en cada fotograma (solo se vuelve a medir, no a construir).
    final main = Expanded(
      child: Column(
        children: [
          _buildTopHeader(w, isDesktop),
          // Navegación duplicada eliminada: el menú lateral ya indica la
          // sección actual. El contenido empieza justo bajo el encabezado.
          Expanded(child: widget.body),
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
                child: SafeArea(
                  child: _buildSidebar(expanded: true, inDrawer: true),
                ),
              ),
        // t: 0 = barra contraída, 1 = expandida. Se anima sola cada vez que
        // cambia `expanded` (botón de la flecha o cambio de tamaño de ventana).
        body: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: expanded ? 1.0 : 0.0),
          duration: reduceMotion
              ? Duration.zero
              : (expanded ? _expandDuration : _collapseDuration),
          curve: expanded ? _expandCurve : _collapseCurve,
          child: main,
          builder: (context, t, mainChild) {
            // t puede pasarse de [0, 1] durante el rebote: de ahí el efecto.
            final sidebarW =
                (_sidebarCollapsedW +
                        (_sidebarExpandedW - _sidebarCollapsedW) * t)
                    .clamp(_sidebarMinW, _sidebarExpandedW + 40)
                    .toDouble();
            return Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isDesktop) _buildAnimatedSidebar(t, sidebarW),
                    mainChild!,
                  ],
                ),
                if (isDesktop)
                  Positioned(
                    left: sidebarW - 12,
                    top: 64,
                    child: _buildCollapseButton(expanded, t),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  //
  // Cierre de sesión con confirmación
  //
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const _LogoutConfirmDialog(),
    );
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
            hoverColor: Colors.transparent,
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
              // La flecha gira suave y se queda en 0°–180° aunque la barra rebote.
              child: Transform.rotate(
                angle:
                    (1 -
                        Curves.easeInOutCubic.transform(
                          t.clamp(0.0, 1.0).toDouble(),
                        )) *
                    math.pi,
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
  /// El ancho sigue a [t] (con rebote). Dentro hay DOS capas a su tamaño real
  /// (contraída de 76 px y expandida de 250 px) con un fundido cruzado entre
  /// ellas. Los íconos están casi en el mismo punto en ambas, así que se ve
  /// como si se quedaran quietos mientras las etiquetas aparecen y se
  /// desvelan con el borde de la barra. No hay corte ni parpadeo.
  Widget _buildAnimatedSidebar(double t, double width) {
    // p: 0 = solo contraída, 1 = solo expandida.
    final p = Curves.easeInOut.transform(
      ((t - _fadeStart) / _fadeSpan).clamp(0.0, 1.0).toDouble(),
    );

    Widget layer({
      required bool expanded,
      required double opacity,
      required bool active,
    }) {
      final w = expanded ? _sidebarExpandedW : _sidebarCollapsedW;
      return IgnorePointer(
        ignoring: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: Opacity(
            opacity: opacity,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: w,
              maxWidth: w,
              child: _buildSidebar(expanded: expanded),
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.sidebarTop, AppColors.sidebarBottom],
            ),
          ),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                layer(expanded: false, opacity: 1 - p, active: p < 0.5),
                layer(expanded: true, opacity: p, active: p >= 0.5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar({required bool expanded, bool inDrawer = false}) {
    return SizedBox(
      width: inDrawer
          ? null
          : (expanded ? _sidebarExpandedW : _sidebarCollapsedW),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Las ondas viajan hacia la derecha y expanden su altura
            // suavemente; la posterior llega más arriba que la delantera.
            // No usa imágenes; sigue nítido en cualquier resolución.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SidebarWavePainter(progress: _waveController),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 16 : 12,
                vertical: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sidebarInstitution(expanded, inDrawer),
                  SizedBox(height: expanded ? 34 : 28),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (var i = 0; i < widget.navItems.length; i++)
                          _navItem(i, expanded, inDrawer),
                      ],
                    ),
                  ),
                  _supportItem(expanded),
                  const SizedBox(height: 16),
                  _sidebarLogout(expanded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Logotipo HD (1024 x 1024) reconstruido en formato vectorial.
  /// Se representa sin ClipRRect para no cortar detalles en los bordes.
  /// El asset usa la misma ruta que el anterior: no requiere cambiar imports.
  Widget _brandMark() {
    return SizedBox(
      width: 52,
      height: 52,
      child: Image.asset(
        'assets/images/logo_edupago.png',
        width: 52,
        height: 52,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        semanticLabel: 'Logo de EduPago',
        errorBuilder: (context, error, stackTrace) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      ),
    );
  }

  /// Cabecera de marca: hover sutil sobre toda la tarjeta (expandida o
  /// contraída). Al pulsarla se regresa al primer apartado del menú.
  Widget _sidebarInstitution(bool expanded, bool inDrawer) {
    return HoverBuilder(
      cursor: widget.navItems.isEmpty
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      builder: (context, hovered) => Semantics(
        button: widget.navItems.isNotEmpty,
        label: 'EduPago, ir al inicio',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: widget.navItems.isEmpty ? null : () => _select(0, inDrawer),
            hoverColor: Colors.transparent,
            splashColor: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 11 : 6,
                vertical: expanded ? 11 : 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: hovered
                      ? const [Color(0xFF2F568B), Color(0xFF224777)]
                      : const [Color(0xFF254B7F), Color(0xFF1B3868)],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.white.withValues(alpha: hovered ? 0.34 : 0.12),
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
              child: expanded
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 46,
                          height: 46,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: _brandMark(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'EduPago',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.onDarkMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Tooltip(
                      message: 'EduPago · Inicio',
                      child: Center(
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: _brandMark(),
                          ),
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

  Widget _navItem(int index, bool expanded, bool inDrawer) {
    final item = widget.navItems[index];
    final selected = widget.selectedIndex == index;

    return HoverBuilder(
      builder: (context, hovered) {
        final bg = selected
            ? _navActive
            : (hovered
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent);
        final fg = (selected || hovered) ? Colors.white : AppColors.onDarkMuted;

        if (!expanded) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: Tooltip(
                message: item.title,
                child: InkWell(
                  onTap: () => _select(index, inDrawer),
                  borderRadius: BorderRadius.circular(12),
                  hoverColor: Colors.transparent,
                  child: AnimatedContainer(
                    duration: _hoverDuration,
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.primaryBlue
                            : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      selected ? item.activeIcon : item.icon,
                      color: fg,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _select(index, inDrawer),
            borderRadius: BorderRadius.circular(10),
            hoverColor: Colors.transparent,
            child: AnimatedContainer(
              duration: _hoverDuration,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? item.activeIcon : item.icon,
                    color: fg,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: (selected || hovered)
                            ? Colors.white
                            : AppColors.onDarkMuted,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Tarjeta de ayuda con resaltado azul en hover. En el menú compacto
  /// el mismo efecto se aplica al botón con icono.
  Widget _supportItem(bool expanded) {
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

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => Tooltip(
        message: expanded ? 'Abrir soporte' : '¿Necesitas ayuda?',
        child: Semantics(
          button: true,
          label: '¿Necesitas ayuda? Abrir soporte',
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              hoverColor: Colors.transparent,
              splashColor: const Color(0xFF60A5FA).withValues(alpha: 0.14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(
                  minHeight: AppSizes.minTarget,
                ),
                padding: expanded
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 13)
                    : const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
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
                child: expanded
                    ? Row(
                        children: [
                          const Icon(
                            Icons.info_rounded,
                            color: Color(0xFF75ACFF),
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '¿Necesitas ayuda?',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Estamos para ti',
                                  style: TextStyle(
                                    color: AppColors.onDarkMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: hovered
                                ? Colors.white
                                : AppColors.onDarkMuted,
                            size: 19,
                          ),
                        ],
                      )
                    : const Icon(
                        Icons.headset_mic_outlined,
                        color: Colors.white,
                        size: 22,
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
  Widget _sidebarLogout(bool expanded) {
    const hoverRed = Color(0xFFEF4444);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.17)),
        const SizedBox(height: 12),
        Tooltip(
          message: 'Cerrar sesión',
          child: HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => Semantics(
              button: true,
              label: 'Cerrar sesión',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _confirmLogout,
                  borderRadius: BorderRadius.circular(12),
                  hoverColor: Colors.transparent,
                  splashColor: hoverRed.withValues(alpha: 0.14),
                  highlightColor: hoverRed.withValues(alpha: 0.10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutCubic,
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.minTarget,
                    ),
                    padding: EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: expanded ? 13 : 0,
                    ),
                    decoration: BoxDecoration(
                      color: hovered
                          ? hoverRed.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hovered
                            ? hoverRed.withValues(alpha: 0.40)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: expanded
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 170),
                          child: Icon(
                            Icons.logout_rounded,
                            key: ValueKey(hovered),
                            color: hovered
                                ? const Color(0xFFFFB4B4)
                                : AppColors.onDarkMuted,
                            size: 22,
                          ),
                        ),
                        if (expanded) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Cerrar sesión',
                              style: TextStyle(
                                color: hovered
                                    ? const Color(0xFFFFD8D8)
                                    : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
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

  Widget _buildTopHeader(double w, bool isDesktop) {
    final compact = Breakpoints.isCompact(w);
    final showUserText = w > 1040;
    final showActions = w > 1180;
    return Container(
      height: 86,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          if (!isDesktop) ...[
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppColors.darkNavy),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Abrir menú',
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
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
                  fillColor: const Color(0xFFF2F6FC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Color(0xFFEDF1F9)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showActions)
            for (final a in widget.headerActions) ...[
              const SizedBox(width: 12),
              a,
            ],
          const SizedBox(width: 20),
          NotificationBell(
            key: const ValueKey('notification-bell'),
            onOpen: widget.onNotificationTap,
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 34, color: AppColors.cardBorder),
          const SizedBox(width: 16),
          _userMenu(
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
        ],
      ),
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
                                  ? const Color(0xFFB91C1C)
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
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
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
