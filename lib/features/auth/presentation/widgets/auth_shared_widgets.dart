import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show TextInputFormatter;
import '../../../../core/theme/app_colors.dart';

/// Transición con fundido para pasar entre Login <-> Registro.
/// Como ambas pantallas comparten el panel izquierdo, el cambio se siente
/// continuo en vez de un "salto" de página completa.
PageRoute<void> authFadeRoute(Widget page) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel izquierdo (marca)
// ─────────────────────────────────────────────────────────────────────────────

class AuthFeature {
  const AuthFeature(this.icon, this.text, {this.description});

  final IconData icon;
  final String text;

  /// Línea secundaria opcional bajo el título.
  final String? description;
}

/// Panel izquierdo compartido por Login y Registro.
///
/// Capas: imagen -> degradado navy (más oscuro abajo para que el texto se
/// lea siempre) -> dos halos azules difusos -> contenido. El bloque de texto
/// entra con un fundido + deslizamiento suave al abrir la pantalla.
class AuthBrandPanel extends StatefulWidget {
  const AuthBrandPanel({
    super.key,
    required this.imageAsset,
    required this.onLogoTap,
    required this.headline,
    required this.subtitle,
    required this.description,
    this.features = const [],
    this.footnote,
  });

  final String imageAsset;
  final VoidCallback onLogoTap;
  final String headline;
  final String subtitle;
  final String description;
  final List<AuthFeature> features;
  final String? footnote;

  @override
  State<AuthBrandPanel> createState() => _AuthBrandPanelState();
}

class _AuthBrandPanelState extends State<AuthBrandPanel> {
  bool _logoHovered = false;

  Widget _glow({required double size, required double alpha}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppColors.primaryBlue.withValues(alpha: alpha),
              AppColors.primaryBlue.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return MouseRegion(
      onEnter: (_) => setState(() => _logoHovered = true),
      onExit: (_) => setState(() => _logoHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onLogoTap,
        child: AnimatedScale(
          scale: _logoHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(
                        alpha: _logoHovered ? 0.22 : 0.15,
                      ),
                      AppColors.primaryBlue.withValues(
                        alpha: _logoHovered ? 0.55 : 0.4,
                      ),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: _logoHovered ? 0.35 : 0.2,
                    ),
                  ),
                ),
                child: Image.asset(
                  'assets/images/logo_edupago.png',
                  width: 46,
                  height: 46,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    decoration: TextDecoration.none,
                  ),
                  children: const [
                    TextSpan(
                      text: 'Edu',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextSpan(
                      text: 'Pago',
                      style: TextStyle(color: AppColors.primaryBlue),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextBlock() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - v)),
          child: child,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.headline,
            style: const TextStyle(
              color: AppColors.primaryBlue,
              fontSize: 48,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.subtitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: Text(
              widget.description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 15,
                height: 1.55,
              ),
            ),
          ),
          if (widget.features.isNotEmpty) ...[
            const SizedBox(height: 28),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (int i = 0; i < widget.features.length; i++)
                  _FeatureTile(feature: widget.features[i], index: i),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        color: AppColors.darkNavy,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.32,
                child: Image.asset(widget.imageAsset, fit: BoxFit.cover),
              ),
            ),
            // Degradado: deja ver la foto al centro y oscurece abajo (texto)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.darkNavy.withValues(alpha: 0.85),
                      AppColors.darkNavy.withValues(alpha: 0.45),
                      AppColors.darkNavy.withValues(alpha: 0.96),
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -140,
              right: -140,
              child: _glow(size: 420, alpha: 0.38),
            ),
            Positioned(
              bottom: -180,
              left: -140,
              child: _glow(size: 420, alpha: 0.22),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, c) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 60,
                      vertical: 56,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, c.maxHeight - 112),
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildLogo(),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: _buildTextBlock(),
                            ),
                            if (widget.footnote != null)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.shield_outlined,
                                    color: Colors.white54,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      widget.footnote!,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                        fontSize: 12,
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de característica: icono en una pastilla azul, título y, si hay,
/// una línea de descripción. Borde de vidrio que se ilumina en azul al pasar
/// el cursor. Entran escalonadas.
class _FeatureTile extends StatefulWidget {
  const _FeatureTile({required this.feature, required this.index});

  final AuthFeature feature;
  final int index;

  @override
  State<_FeatureTile> createState() => _FeatureTileState();
}

class _FeatureTileState extends State<_FeatureTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final AuthFeature f = widget.feature;
    final bool hasDesc = f.description != null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 700 + widget.index * 200),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - v)),
          child: child,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(maxWidth: 420),
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          padding: EdgeInsets.fromLTRB(
            12,
            hasDesc ? 14 : 10,
            18,
            hasDesc ? 14 : 10,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: _hover ? 0.16 : 0.11),
                Colors.white.withValues(alpha: _hover ? 0.07 : 0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? AppColors.primaryBlue.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: hasDesc ? 42 : 34,
                height: hasDesc ? 42 : 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.55),
                  ),
                ),
                child: Icon(
                  f.icon,
                  size: hasDesc ? 21 : 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasDesc) ...[
                      const SizedBox(height: 3),
                      Text(
                        f.description!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel derecho: tarjeta con el formulario
// ─────────────────────────────────────────────────────────────────────────────

/// Lado derecho: fondo suave con ondas (tonos de `AppColors`) y, encima, una
/// tarjeta blanca con borde `cardBorder` y sombra suave, centrada
/// horizontal y verticalmente. "Volver al inicio" es la primera fila de la
/// tarjeta. Si la ventana es baja, la tarjeta hace scroll en vez de cortarse.
class AuthFormPanel extends StatefulWidget {
  const AuthFormPanel({
    super.key,
    required this.onBack,
    required this.child,
    this.isDesktop = true,
    this.maxWidth = 640, // 640 - 2*32 de padding = 576 de contenido útil
  });

  final VoidCallback onBack;
  final Widget child;
  final bool isDesktop;
  final double maxWidth;

  @override
  State<AuthFormPanel> createState() => _AuthFormPanelState();
}

class _AuthFormPanelState extends State<AuthFormPanel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final double hPad = widget.isDesktop ? 32 : 16;

    return Stack(
      children: [
        const Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _WavePainter())),
        ),
        Positioned.fill(child: _buildCard(hPad)),
      ],
    );
  }

  Widget _buildCard(double hPad) {
    final bool desktop = widget.isDesktop;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - 48),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                // Al pasar el cursor, el borde se ilumina en azul
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hover = true),
                  onExit: (_) => setState(() => _hover = false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.fromLTRB(
                      desktop ? 32 : 20,
                      22,
                      desktop ? 32 : 20,
                      28,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _hover
                            ? AppColors.primaryBlue.withValues(alpha: 0.55)
                            : AppColors.cardBorder,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(
                            alpha: _hover ? 0.18 : 0.10,
                          ),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AuthBackLink(onTap: widget.onBack),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: widget.child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fondo del panel derecho: base `backgroundLight` y una sola onda grande que
/// sube desde abajo a la izquierda hacia arriba a la derecha, teñida con un
/// azul muy suave (`primaryBlue` con poca opacidad).
class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.backgroundLight,
    );

    // Onda
    final Path front = Path()
      ..moveTo(0, h * 0.81)
      ..cubicTo(w * 0.18, h * 0.60, w * 0.38, h * 0.58, w * 0.52, h * 0.50)
      ..cubicTo(w * 0.68, h * 0.40, w * 0.80, h * 0.20, w, h * 0.04)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.11),
            AppColors.primaryBlue.withValues(alpha: 0.03),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón "Volver al inicio"
// ─────────────────────────────────────────────────────────────────────────────

class AuthBackLink extends StatefulWidget {
  const AuthBackLink({
    super.key,
    required this.onTap,
    this.label = 'Volver al inicio',
  });

  final VoidCallback onTap;
  final String label;

  @override
  State<AuthBackLink> createState() => _AuthBackLinkState();
}

class _AuthBackLinkState extends State<AuthBackLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = _hover ? AppColors.primaryBlue : AppColors.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _hover
                    ? AppColors.primaryBlue.withValues(alpha: 0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _hover ? AppColors.primaryBlue : AppColors.cardBorder,
                ),
              ),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                offset: _hover ? const Offset(-0.1, 0) : Offset.zero,
                child: Icon(Icons.arrow_back, size: 16, color: accent),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style:
                  (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
              child: Text(widget.label),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segmentos y etiquetas (compartidos por los dos selectores)
// ─────────────────────────────────────────────────────────────────────────────

class AuthSegment {
  const AuthSegment({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;
}

Widget _segmentLabelRow(AuthSegment seg, Color c) {
  return Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (seg.icon != null) ...[
          Icon(seg.icon, size: 17, color: c),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            seg.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Selector rápido (Registro <-> Iniciar sesión): deslizamiento corto, sin fluido
// ─────────────────────────────────────────────────────────────────────────────

class AuthSegmentedSelector extends StatelessWidget {
  const AuthSegmentedSelector({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 48,
    this.trackColor = AppColors.backgroundLight,
  });

  final List<AuthSegment> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;
  final Color trackColor;

  static const Duration duration = Duration(milliseconds: 180);
  static const Curve curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final AuthSegment active = segments[selectedIndex];

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final double segW = c.maxWidth / segments.length;

            return Stack(
              children: [
                AnimatedPositioned(
                  duration: duration,
                  curve: curve,
                  left: selectedIndex * segW,
                  top: 0,
                  bottom: 0,
                  width: segW,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: curve,
                    decoration: BoxDecoration(
                      color: active.color,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (int i = 0; i < segments.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == selectedIndex,
                          label: segments[i].label,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (i != selectedIndex) onChanged(i);
                              },
                              child: TweenAnimationBuilder<Color?>(
                                tween: ColorTween(
                                  end: i == selectedIndex
                                      ? Colors.white
                                      : AppColors.textMuted,
                                ),
                                duration: duration,
                                curve: curve,
                                builder: (context, color, _) =>
                                    _segmentLabelRow(
                                      segments[i],
                                      color ?? AppColors.textMuted,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selector líquido (Portal Representante <-> Administrativo)
// ─────────────────────────────────────────────────────────────────────────────

/// Pastilla con física de resortes (en vez de curvas fijas):
///  - cada borde es un resorte; el delantero es rígido y llega primero, el
///    trasero es blando y lo persigue, así que la pastilla se estira sola;
///  - al estirarse se adelgaza y se pellizca por el centro (como un líquido
///    que conserva su volumen) y al llegar "se asienta" con un leve rebote;
///  - si haces clic de nuevo a mitad de camino, conserva la velocidad: no
///    hay saltos ni reinicios;
///  - el color se mezcla entre segmentos y el texto blanco solo aparece
///    donde el líquido ya pasó.
class LiquidSegmentedSelector extends StatefulWidget {
  const LiquidSegmentedSelector({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 50,
    this.trackColor = AppColors.backgroundLight,
    this.hasError = false,
  });

  final List<AuthSegment> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;
  final Color trackColor;
  final bool hasError;

  @override
  State<LiquidSegmentedSelector> createState() =>
      _LiquidSegmentedSelectorState();
}

class _LiquidSegmentedSelectorState extends State<LiquidSegmentedSelector>
    with SingleTickerProviderStateMixin {
  static const double _pad = 4;
  static const double _radius = 10;

  // (rigidez, amortiguación) de los resortes
  static const double _kLead = 380,
      _cLead = 30; // delantero: rápido, poco rebote
  static const double _kTrail = 140,
      _cTrail = 19; // trasero: blando, más rebote

  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Duration? _last;

  // Posición, velocidad y destino de cada borde (en unidades de segmento).
  late double _l, _r;
  double _vl = 0, _vr = 0;
  late double _tl, _tr;
  double _kL = _kLead, _cL = _cLead, _kR = _kLead, _cR = _cLead;

  @override
  void initState() {
    super.initState();
    _l = _tl = widget.selectedIndex.toDouble();
    _r = _tr = _l + 1;
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant LiquidSegmentedSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;

    final bool movingRight = widget.selectedIndex > oldWidget.selectedIndex;
    _tl = widget.selectedIndex.toDouble();
    _tr = _tl + 1;

    if (movingRight) {
      _kR = _kLead;
      _cR = _cLead;
      _kL = _kTrail;
      _cL = _cTrail;
    } else {
      _kL = _kLead;
      _cL = _cLead;
      _kR = _kTrail;
      _cR = _cTrail;
    }

    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final double dt = _last == null
        ? 1 / 60
        : ((elapsed - _last!).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;

    // Integración semi-implícita en pasos pequeños (estable con resortes duros)
    double remaining = dt;
    const double step = 1 / 240;
    while (remaining > 1e-9) {
      final double h = math.min(step, remaining);
      remaining -= h;

      _vl += (_kL * (_tl - _l) - _cL * _vl) * h;
      _l += _vl * h;
      _vr += (_kR * (_tr - _r) - _cR * _vr) * h;
      _r += _vr * h;

      // La pastilla nunca se colapsa
      if (_r - _l < 0.6) {
        _l = _r - 0.6;
      }
    }

    final bool settled =
        (_l - _tl).abs() < 0.0008 &&
        (_r - _tr).abs() < 0.0008 &&
        _vl.abs() < 0.01 &&
        _vr.abs() < 0.01;
    if (settled) {
      _l = _tl;
      _r = _tr;
      _vl = _vr = 0;
      _ticker.stop();
    }
    _frame.value++;
  }

  Color _colorAt(double centerIndex) {
    final int n = widget.segments.length;
    final double p = centerIndex.clamp(0.0, (n - 1).toDouble());
    final int i0 = p.floor();
    final int i1 = math.min(i0 + 1, n - 1);
    return Color.lerp(
      widget.segments[i0].color,
      widget.segments[i1].color,
      p - i0,
    )!;
  }

  Path _pillPath(Size size) {
    final int n = widget.segments.length;
    final double segW = size.width / n;
    // El rebote nunca se sale de la pista
    final double x0 = (_l * segW).clamp(0.0, size.width);
    final double x1 = (_r * segW).clamp(0.0, size.width);

    // Estirada -> más delgada y pellizcada (conserva el "volumen")
    final double stretch = ((_r - _l) - 1).clamp(0.0, 1.2);
    final double inset = stretch * 3.5;
    final double top = inset;
    final double bottom = size.height - inset;
    final double rad = math.min(_radius, (bottom - top) / 2);
    final double mid = (x0 + x1) / 2;
    final double ctrl = stretch * 5; // el punto de control dobla a la mitad

    return Path()
      ..moveTo(x0 + rad, top)
      ..quadraticBezierTo(mid, top + ctrl, x1 - rad, top)
      ..arcToPoint(Offset(x1, top + rad), radius: Radius.circular(rad))
      ..lineTo(x1, bottom - rad)
      ..arcToPoint(Offset(x1 - rad, bottom), radius: Radius.circular(rad))
      ..quadraticBezierTo(mid, bottom - ctrl, x0 + rad, bottom)
      ..arcToPoint(Offset(x0, bottom - rad), radius: Radius.circular(rad))
      ..lineTo(x0, top + rad)
      ..arcToPoint(Offset(x0 + rad, top), radius: Radius.circular(rad))
      ..close();
  }

  Widget _labels({required bool onPill}) {
    final Color c = onPill ? Colors.white : AppColors.textMuted;
    return Row(
      children: [
        for (final seg in widget.segments)
          Expanded(child: _segmentLabelRow(seg, c)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: los 60 repintados por segundo se quedan dentro del
    // selector y no obligan a repintar toda la tarjeta (campos, sombras...).
    return RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: Container(
          padding: const EdgeInsets.all(_pad),
          decoration: BoxDecoration(
            color: widget.trackColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.hasError ? kAuthError : AppColors.cardBorder,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final Size size = Size(c.maxWidth, c.maxHeight);

              return AnimatedBuilder(
                animation: _frame,
                builder: (context, _) {
                  final Path pill = _pillPath(size);
                  final Color color = _colorAt((_l + _r) / 2 - 0.5);

                  return Stack(
                    children: [
                      // 1) Sombra del líquido
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _LiquidShadowPainter(
                            path: pill,
                            color: color,
                          ),
                        ),
                      ),
                      // 2) Textos grises (el líquido los tapa al pasar)
                      Positioned.fill(child: _labels(onPill: false)),
                      // 3) El líquido
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _LiquidFillPainter(path: pill, color: color),
                        ),
                      ),
                      // 4) Textos blancos, solo dentro del líquido
                      Positioned.fill(
                        child: ClipPath(
                          clipper: _PathClipper(pill),
                          child: _labels(onPill: true),
                        ),
                      ),
                      // 5) Zonas táctiles
                      Positioned.fill(
                        child: Row(
                          children: [
                            for (int i = 0; i < widget.segments.length; i++)
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected: i == widget.selectedIndex,
                                  label: widget.segments[i].label,
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        if (i != widget.selectedIndex) {
                                          widget.onChanged(i);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LiquidShadowPainter extends CustomPainter {
  _LiquidShadowPainter({required this.path, required this.color});

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path.shift(const Offset(0, 3)),
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidShadowPainter old) => true;
}

class _LiquidFillPainter extends CustomPainter {
  _LiquidFillPainter({required this.path, required this.color});

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Relleno opaco con un leve brillo superior para dar volumen
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.14)!, color],
        ).createShader(path.getBounds()),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidFillPainter old) => true;
}

class _PathClipper extends CustomClipper<Path> {
  _PathClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _PathClipper oldClipper) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Campos de texto y mensajes de error (compartidos por Login y Registro)
// ─────────────────────────────────────────────────────────────────────────────

/// Rojo de error: borde del campo y mensaje debajo.
const Color kAuthError = Color(0xFFDC2626);
const Color _kAuthSuccessText = Color(0xFF15803D);

/// Correo: formato real (RFC 5322 práctico), con subdominios.
final RegExp kAuthEmailRegex = RegExp(
  r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
  r"@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
);

const TextStyle _kFieldMessageStyle = TextStyle(
  color: kAuthError,
  fontSize: 11.5,
  height: 1.25,
  fontWeight: FontWeight.w500,
);

/// Decoración común: borde gris, azul (acento) al enfocar y ROJO cuando hay
/// error. El mensaje de error sale debajo del campo.
InputDecoration authInputDecoration({
  required String hint,
  IconData? icon,
  Widget? prefix,
  Widget? suffix,
  Color activeColor = AppColors.primaryBlue,
  bool forceError = false,
  double vPad = 13,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
    prefixIcon:
        prefix ??
        (icon != null
            ? Icon(icon, color: AppColors.textMuted, size: 19)
            : null),
    prefixIconConstraints: prefix != null
        ? const BoxConstraints(minWidth: 0, minHeight: 0)
        : null,
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: vPad),
    errorStyle: _kFieldMessageStyle,
    errorMaxLines: 3,
    border: border(AppColors.cardBorder),
    enabledBorder: forceError
        ? border(kAuthError, 1.5)
        : border(AppColors.cardBorder),
    focusedBorder: border(forceError ? kAuthError : activeColor, 1.5),
    errorBorder: border(kAuthError, 1.5),
    focusedErrorBorder: border(kAuthError, 1.5),
  );
}

/// Mensaje de error suelto (mismo estilo que el de un campo), para cosas que
/// no son un TextFormField: casilla de términos, selector de portal...
class AuthFieldError extends StatelessWidget {
  const AuthFieldError(this.text, {super.key, this.left = 12});

  final String text;
  final double left;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 5, left: left),
      child: Text(text, style: _kFieldMessageStyle),
    );
  }
}

/// Aviso de error general (no pertenece a un campo concreto), p. ej. "demasiados
/// intentos". Va justo encima del botón principal.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 17, color: kAuthError),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo con etiqueta, borde rojo + mensaje debajo cuando hay error, y un
/// "check" verde opcional cuando el valor fue aceptado.
///
/// Cuándo se valida:
///  - al SALIR del campo (blur);
///  - después, en vivo mientras se corrige;
///  - y siempre al enviar el formulario (Form.validate).
/// Así no aparece un error en rojo mientras la persona todavía está escribiendo
/// por primera vez.
///
/// [serverError] sirve para errores que vienen del servidor (correo ya
/// registrado, credenciales incorrectas...): se muestran en el mismo campo y
/// se limpian solos cuando el padre pone `null`.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    this.icon,
    this.prefix,
    this.suffix,
    this.validator,
    this.serverError,
    this.forceErrorBorder = false,
    this.successText,
    this.revalidateWhen,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onFieldSubmitted,
    this.activeColor = AppColors.primaryBlue,
    this.compact = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData? icon;
  final Widget? prefix;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final String? serverError;

  /// Borde rojo SIN mensaje propio (el mensaje lo muestra otro campo).
  final bool forceErrorBorder;

  /// Texto verde con check que aparece al salir del campo si el valor es válido.
  final String? successText;

  /// Si cambia (p. ej. la contraseña original), este campo se vuelve a validar.
  final Listenable? revalidateWhen;

  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final Color activeColor;
  final bool compact;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  final GlobalKey<FormFieldState<String>> _fieldKey =
      GlobalKey<FormFieldState<String>>();
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    widget.revalidateWhen?.addListener(_onDependencyChanged);
  }

  @override
  void didUpdateWidget(covariant AuthTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (old.revalidateWhen != widget.revalidateWhen) {
      old.revalidateWhen?.removeListener(_onDependencyChanged);
      widget.revalidateWhen?.addListener(_onDependencyChanged);
    }
    // Llegó (o se quitó) un error del servidor: mostrarlo/limpiarlo ya.
    if (old.serverError != widget.serverError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revalidate();
      });
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    widget.revalidateWhen?.removeListener(_onDependencyChanged);
    super.dispose();
  }

  void _revalidate() {
    _fieldKey.currentState?.validate();
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (!widget.focusNode.hasFocus) {
      _touched = true; // al salir del campo se valida
      _revalidate();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _onDependencyChanged() {
    if (mounted && _touched) _revalidate();
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = widget.focusNode.hasFocus;
    final bool showSuccess =
        !focused &&
        _touched &&
        widget.successText != null &&
        widget.controller.text.isNotEmpty &&
        _fieldKey.currentState?.hasError == false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: widget.compact ? 12 : 13,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        SizedBox(height: widget.compact ? 6 : 8),
        TextFormField(
          key: _fieldKey,
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          onFieldSubmitted: widget.onFieldSubmitted,
          onChanged: (value) {
            // En vivo solo si ya se validó antes o ya hay un error que corregir
            if (_touched || _fieldKey.currentState?.hasError == true) {
              _revalidate();
            }
            widget.onChanged?.call(value);
          },
          validator: (value) =>
              widget.validator?.call(value) ?? widget.serverError,
          decoration: authInputDecoration(
            hint: widget.hint,
            icon: widget.icon,
            prefix: widget.prefix,
            suffix: widget.suffix,
            activeColor: widget.activeColor,
            forceError: widget.forceErrorBorder,
            vPad: widget.compact ? 12 : 14,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: showSuccess
              ? Padding(
                  padding: const EdgeInsets.only(top: 5, left: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.successGreen,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          widget.successText!,
                          style: const TextStyle(
                            color: _kAuthSuccessText,
                            fontSize: 11.5,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
