import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tokens y utilidades
// ─────────────────────────────────────────────────────────────────────────────

/// Rojo de error: borde del campo y mensaje debajo.
const Color kAuthError = Color(0xFFDC2626);
const Color _kAuthErrorSoft = Color(0xFFFEF2F2);
const Color _kAuthErrorBorder = Color(0xFFFECACA);
const Color _kAuthSuccessText = Color(0xFF15803D);

/// Radio común de campos y botones (la landing usa esquinas muy redondeadas).
const double _kRadius = 14;

/// Texto secundario SOBRE el fondo de ondas o dentro de tarjetas: un poco más
/// oscuro que `textMuted` para mantener contraste AA sobre celeste.
Color get _kBodyText =>
    Color.lerp(AppColors.textMuted, AppColors.darkNavy, 0.35)!;

/// Correo: formato real (RFC 5322 práctico), con subdominios.
final RegExp kAuthEmailRegex = RegExp(
  r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
  r"@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
);

/// Duración de una animación respetando "reducir movimiento" del sistema.
Duration authMotion(BuildContext context, [int ms = 180]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

/// Transición con fundido para pasar entre Login <-> Registro.
PageRoute<void> authFadeRoute(Widget page) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Fondo de ondas (adaptado de la landing, más pequeño y suave)
// ─────────────────────────────────────────────────────────────────────────────

/// Fondo dibujado con código, con la misma paleta y geometría de cintas que
/// `LandingBackdrop`, pero a menor escala para no competir con el formulario.
/// Si prefieres reutilizar directamente el de la landing, reemplaza este widget
/// por `LandingBackdrop(style: LandingWaveStyle.hero)`.
class AuthWaveBackground extends StatelessWidget {
  const AuthWaveBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _AuthWavesPainter(),
            isComplex: true,
            willChange: false,
          ),
        ),
      ),
    );
  }
}

class _AuthWavesPainter extends CustomPainter {
  const _AuthWavesPainter();

  static const double _designW = 1672;

  static Path _strongA() => Path()
    ..moveTo(-30, 205)
    ..cubicTo(260, 200, 400, 20, 660, -25);

  static Path _strongB() => Path()
    ..moveTo(-30, 247)
    ..cubicTo(300, 265, 480, 30, 820, -25);

  static Path _softU() => Path()
    ..moveTo(500, -10)
    ..cubicTo(380, 20, 260, 100, 172, 100)
    ..cubicTo(100, 100, 40, 60, -30, 30);

  static Path _softL() => Path()
    ..moveTo(500, -10)
    ..cubicTo(380, 20, 200, 140, -30, 148);

  /// Región cerrada entre dos curvas.
  static Path _between(Path first, Path second) {
    final Path out = Path.from(first);
    final ui.PathMetric m = second.computeMetrics().first;
    const int n = 64;
    for (int i = n; i >= 0; i--) {
      final ui.Tangent? t = m.getTangentForOffset(m.length * i / n);
      if (t != null) out.lineTo(t.position.dx, t.position.dy);
    }
    out.close();
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final double w = size.width;
    final double h = size.height;
    // 0.8: más discreto que en la landing.
    final double s = math.min(math.max(w / _designW, 0.42), h / 600) * 0.8;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _paintBase(canvas, w, h);

    _corner(canvas, w, h, s, 0, _paintSoft);
    _corner(canvas, w, h, s, 1, _paintSoft);
    _corner(canvas, w, h, s, 2, _paintStrong);
    _corner(canvas, w, h, s, 3, _paintStrong);
    canvas.restore();
  }

  void _paintBase(Canvas canvas, double w, double h) {
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.scale(w / 2, h / 2);
    canvas.drawRect(
      const Rect.fromLTRB(-2, -2, 2, 2),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          1.6,
          const [
            Color(0xFFF4F7FE),
            Color(0xFFE4EFFD),
            Color(0xFFD0E4FD),
            Color(0xFFC4DFFD),
          ],
          const [0.0, 0.3125, 0.625, 1.0],
        ),
    );
    canvas.restore();
  }

  /// 0 = arriba-der (suave), 1 = abajo-izq (suave),
  /// 2 = arriba-izq (fuerte), 3 = abajo-der (fuerte).
  void _corner(
    Canvas canvas,
    double w,
    double h,
    double s,
    int corner,
    void Function(Canvas) draw,
  ) {
    canvas.save();
    switch (corner) {
      case 0:
        canvas.translate(w, 0);
        canvas.scale(-s, s);
      case 1:
        canvas.translate(0, h);
        canvas.scale(s, -s);
      case 2:
        canvas.scale(s, s);
      default:
        canvas.translate(w, h);
        canvas.scale(-s, -s);
    }
    draw(canvas);
    canvas.restore();
  }

  static Paint _fill(ui.Shader shader) => Paint()..shader = shader;

  static void _highlight(Canvas canvas, Path path, double alpha) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Colors.white.withValues(alpha: alpha * 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  void _paintStrong(Canvas canvas) {
    final Path a = _strongA();
    final Path b = _strongB();

    canvas.drawPath(
      Path.from(a)
        ..lineTo(-30, -25)
        ..close(),
      _fill(
        ui.Gradient.radial(
          Offset.zero,
          620,
          const [
            Color(0xFF006DFE),
            Color(0xFF0472FD),
            Color(0xFF2A90FA),
            Color(0xFF69B4FC),
            Color(0xFF9ACCFD),
            Color(0xFFC6E0FC),
          ],
          const [0.0, 0.30, 0.48, 0.62, 0.78, 1.0],
          TileMode.clamp,
          Float64List.fromList(<double>[
            1, 0, 0, 0, //
            0, 300 / 620, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
          ]),
        ),
      ),
    );

    canvas.drawPath(
      _between(a, b),
      _fill(
        ui.Gradient.linear(
          const Offset(0, 240),
          const Offset(760, 0),
          const [
            Color(0xFF92C8FE),
            Color(0xFFA9D4FE),
            Color(0xFFBADBFD),
            Color(0xFFCDE4FD),
            Color(0xFFC4DFFD),
          ],
          const [0.0, 0.25, 0.55, 0.85, 1.0],
        ),
      ),
    );

    _highlight(canvas, a, 0.85);
    _highlight(canvas, b, 0.70);
  }

  void _paintSoft(Canvas canvas) {
    final Path u = _softU();
    final Path l = _softL();

    canvas.drawPath(
      Path.from(u)
        ..lineTo(-30, -30)
        ..lineTo(500, -30)
        ..close(),
      _fill(
        ui.Gradient.linear(
          const Offset(500, 0),
          const Offset(0, 0),
          const [
            Color(0x00C8E1FD),
            Color(0xFFB3D7FD),
            Color(0xFFA4D0FD),
            Color(0xFF91C8FE),
          ],
          const [0.0, 0.35, 0.7, 1.0],
        ),
      ),
    );

    canvas.drawPath(
      _between(l, u),
      _fill(
        ui.Gradient.linear(
          const Offset(330, 60),
          const Offset(-30, 150),
          const [Color(0xFFB2D6FD), Color(0xFF98C9FE)],
        ),
      ),
    );

    _highlight(canvas, u, 0.80);
    _highlight(canvas, l, 0.70);
  }

  @override
  bool shouldRepaint(covariant _AuthWavesPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Estructura de página: barra superior + (marca) + tarjeta
// ─────────────────────────────────────────────────────────────────────────────

/// Entrada muy sutil (fundido + 14 px de desplazamiento). Se desactiva con
/// "reducir movimiento".
class AuthEntrance extends StatelessWidget {
  const AuthEntrance({super.key, required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final int total = 520 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1.0, curve: Curves.easeOutCubic),
      builder: (context, v, ch) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: ch),
      ),
      child: child,
    );
  }
}

/// Estructura compartida por Login y Registro (sin barra de navegación).
///
/// Escritorio (>= 1000 px) con [intro]: a la izquierda el logo y el mensaje de
/// marca; a la derecha el enlace "Volver" y la tarjeta. Tablet y móvil: una
/// fila con logo + "Volver" y debajo la tarjeta. Todo se centra en la ventana y
/// hace scroll si esta es baja.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.onBack,
    required this.child,
    this.intro,
    this.cardMaxWidth = 540,
    this.cardExtraVerticalPadding = 0,
    this.backLabel = 'Volver al inicio',
  });

  final VoidCallback onBack;
  final Widget child;
  final Widget? intro;
  final double cardMaxWidth;
  final double cardExtraVerticalPadding;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final Size viewport = MediaQuery.sizeOf(context);
    final double width = viewport.width;
    final bool shortWindow = viewport.height < 780;
    final bool wide = width >= 1000 && intro != null;
    final double pad = width < 640 ? 16 : 32;

    // En escritorio la tarjeta crece hasta [cardMaxWidth] solo si sobra
    // espacio: la columna de marca conserva al menos ~400 px, y por debajo de
    // 500 px la tarjeta no se encoge (comportamiento anterior).
    final double rowAvail = math.min(1240.0, width - pad * 2) - 48;
    final double cardW = wide
        ? math.min(cardMaxWidth, math.max(500.0, rowAvail - 72 - 400))
        : cardMaxWidth;
    final Widget card = AuthCard(
      maxWidth: cardW,
      extraVerticalPadding: cardExtraVerticalPadding,
      child: child,
    );
    final Widget back = AuthTextLink(
      label: backLabel,
      icon: Icons.arrow_back_rounded,
      onTap: onBack,
      color: AppColors.darkNavy,
      dense: true,
    );

    final Widget content;
    if (wide) {
      // Alineación vertical real: el logo forma parte del bloque informativo,
      // no está superpuesto sobre el título.
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 48),
                child: AuthEntrance(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AuthLogo(onTap: onBack, size: 54),
                      const SizedBox(height: 18),
                      intro!,
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: cardW,
              child: AuthEntrance(
                delayMs: 80,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: back,
                    ),
                    SizedBox(height: shortWindow ? 6 : 10),
                    card,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AuthLogo(onTap: onBack, size: 40),
              const Spacer(),
              back,
            ],
          ),
          const SizedBox(height: 18),
          AuthEntrance(child: card),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Stack(
        children: [
          const Positioned.fill(child: AuthWaveBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final double topPad = shortWindow ? 10 : 24;
                final double bottomPad = shortWindow ? 12 : 32;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, topPad, pad, bottomPad),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0, c.maxHeight - topPad - bottomPad),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: wide ? 1240 : cardMaxWidth,
                        ),
                        child: content,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo EduPago (imagen + nombre). Lleva a la landing.
///
/// Hover sencillo: símbolo y texto crecen y suben juntos como un solo bloque.
/// El mismo efecto se activa al enfocar con teclado.
/// Con [flush] se compensa el relleno interno para que el borde izquierdo
/// quede alineado con el texto que tiene debajo.
class AuthLogo extends StatefulWidget {
  const AuthLogo({
    super.key,
    required this.onTap,
    this.size = 40,
    this.flush = false,
  });

  final VoidCallback onTap;
  final double size;
  final bool flush;

  @override
  State<AuthLogo> createState() => _AuthLogoState();
}

class _AuthLogoState extends State<AuthLogo> {
  static const double _pad = 6;

  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final bool active = _hover || _focus;
    final Duration d = authMotion(context, 220);

    final Widget logo = Semantics(
      button: true,
      label: 'EduPago, ir al inicio',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          onFocusChange: (v) => setState(() => _focus = v),
          borderRadius: BorderRadius.circular(16),
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: AppColors.primaryBlue.withValues(alpha: 0.08),
          focusColor: AppColors.primaryBlue.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad + 2, _pad + 4),
            child: AnimatedContainer(
              duration: d,
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, active ? -3 : 0, 0),
              child: AnimatedScale(
                scale: active ? 1.04 : 1,
                duration: d,
                curve: Curves.easeOutCubic,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo_edupago.png',
                      width: widget.size,
                      height: widget.size,
                      fit: BoxFit.contain,
                    ),
                    SizedBox(width: math.max(6, widget.size * 0.12)),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: widget.size * 0.54,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                        children: const [
                          TextSpan(
                            text: 'Edu',
                            style: TextStyle(color: AppColors.darkNavy),
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
          ),
        ),
      ),
    );

    return widget.flush
        ? Transform.translate(offset: const Offset(-_pad, -_pad), child: logo)
        : logo;
  }
}

/// Tarjeta con más espacio vertical y borde azul al entrar con el cursor.
class AuthCard extends StatefulWidget {
  const AuthCard({
    super.key,
    required this.child,
    this.maxWidth = 540,
    this.extraVerticalPadding = 0,
  });

  final Widget child;
  final double maxWidth;
  final double extraVerticalPadding;

  @override
  State<AuthCard> createState() => _AuthCardState();
}

class _AuthCardState extends State<AuthCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Size viewport = MediaQuery.sizeOf(context);
    final bool compact = viewport.width < 480;
    final double horizontalPad = compact ? 20 : 32;
    // Más aire en los tres pasos; conserva el padding compacto cuando
    // la ventana es baja o el teclado reduce el espacio disponible.
    final double availableHeight =
        viewport.height -
        MediaQuery.viewInsetsOf(context).bottom -
        MediaQuery.paddingOf(context).vertical;
    final double verticalPad = availableHeight < 700
        ? 16
        : availableHeight < 780
        ? 28
        : availableHeight < 900
        ? 40
        : (compact ? 40 : 64);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: authMotion(context, 220),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: verticalPad + widget.extraVerticalPadding,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            // Grosor constante para que el contenido no salte con el hover.
            border: Border.all(
              color: _hover ? AppColors.primaryBlue : AppColors.cardBorder,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(
                  alpha: _hover ? 0.14 : 0.08,
                ),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: AppColors.darkNavy.withValues(alpha: 0.035),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AnimatedSize(
            duration: authMotion(context, 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Título + subtítulo de la tarjeta. Con [icon] muestra un icono dentro de una
/// pastilla suave a la izquierda del título (el color sigue a [accent]).
class AuthCardHeader extends StatelessWidget {
  const AuthCardHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.accent = AppColors.primaryBlue,
    this.iconDecorated = true,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final Color accent;
  final bool iconDecorated;

  @override
  Widget build(BuildContext context) {
    final Duration d = authMotion(context, 220);

    final Widget titleText = Semantics(
      header: true,
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 26,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: AppColors.darkNavy,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon == null)
          titleText
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (iconDecorated)
                AnimatedContainer(
                  duration: d,
                  curve: Curves.easeOut,
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: accent.withValues(alpha: 0.20)),
                  ),
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: accent),
                    duration: d,
                    builder: (context, c, _) => Icon(icon, size: 22, color: c),
                  ),
                )
              else
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: accent),
                  duration: d,
                  builder: (context, c, _) => Icon(icon, size: 26, color: c),
                ),
              const SizedBox(width: 10),
              Flexible(child: titleText),
            ],
          ),
        SizedBox(height: icon == null ? 6 : 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.45, color: _kBodyText),
        ),
      ],
    );
  }
}

/// Indicador de progreso del registro: barras + "Paso X de Y".
class AuthStepper extends StatelessWidget {
  const AuthStepper({super.key, required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Paso $current de $total',
      excludeSemantics: true,
      child: Row(
        children: [
          for (int i = 1; i <= total; i++)
            Expanded(
              child: AnimatedContainer(
                duration: authMotion(context, 260),
                curve: Curves.easeOut,
                height: 5,
                margin: EdgeInsets.only(right: i == total ? 0 : 6),
                decoration: BoxDecoration(
                  color: i <= current
                      ? AppColors.primaryBlue
                      : AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          const SizedBox(width: 14),
          Text(
            'Paso $current de $total',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _kBodyText,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Columna de marca (solo escritorio)
// ─────────────────────────────────────────────────────────────────────────────

class AuthFeature {
  const AuthFeature(this.icon, this.text, {this.description});

  final IconData icon;
  final String text;

  /// Línea secundaria opcional.
  final String? description;
}

/// Mensaje de marca: línea azul grande ([lead]) + titular marino ([title]),
/// con un párrafo suave debajo. Si no hay [lead], se usa el estilo del hero de
/// la landing: [title] marino + [highlight] azul.
class AuthBrandIntro extends StatelessWidget {
  const AuthBrandIntro({
    super.key,
    this.lead,
    required this.title,
    this.highlight,
    required this.description,
    this.badgeIcon,
    this.badge,
    this.children = const <Widget>[],
  });

  final String? lead;
  final String title;
  final String? highlight;
  final String description;
  final IconData? badgeIcon;
  final String? badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final double fs = MediaQuery.sizeOf(context).width >= 1240 ? 54 : 44;
    final bool hasLead = lead != null;
    final TextStyle leadStyle = TextStyle(
      fontSize: fs * 0.9,
      height: 1.1,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      color: AppColors.primaryBlue,
    );
    final TextStyle titleStyle = TextStyle(
      fontSize: hasLead ? fs * 0.62 : fs,
      height: hasLead ? 1.18 : 1.08,
      fontWeight: FontWeight.w800,
      letterSpacing: hasLead ? -0.8 : -1.4,
      color: AppColors.darkNavy,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badgeIcon != null) ...[
                  Icon(badgeIcon, size: 16, color: AppColors.primaryBlue),
                  const SizedBox(width: 8),
                ],
                Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
        Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasLead) ...[
                Text(lead!, textAlign: TextAlign.center, style: leadStyle),
                const SizedBox(height: 10),
              ],
              Text(title, textAlign: TextAlign.center, style: titleStyle),
              if (highlight != null)
                Text(
                  highlight!,
                  textAlign: TextAlign.center,
                  style: titleStyle.copyWith(color: AppColors.primaryBlue),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.6, color: _kBodyText),
          ),
        ),
        if (children.isNotEmpty) const SizedBox(height: 32),
        ...children,
      ],
    );
  }
}

/// Fila de características con icono, como las de la base del hero.
class AuthFeatureChips extends StatelessWidget {
  const AuthFeatureChips({super.key, required this.features});

  final List<AuthFeature> features;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 34,
      runSpacing: 16,
      children: [
        for (final f in features)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white),
                ),
                child: Icon(f.icon, size: 20, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 116),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f.text,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    if (f.description != null)
                      Text(
                        f.description!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: _kBodyText,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class AuthStepInfo {
  const AuthStepInfo(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

/// Lista vertical de pasos (aquí sí es una secuencia real). Marca el paso
/// actual y los completados.
class AuthStepsOverview extends StatelessWidget {
  const AuthStepsOverview({
    super.key,
    required this.current,
    required this.steps,
  });

  /// Paso actual, empezando en 1.
  final int current;
  final List<AuthStepInfo> steps;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        children: [for (int i = 0; i < steps.length; i++) _row(context, i)],
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final int n = i + 1;
    final bool done = n < current;
    final bool active = n == current;
    final bool last = i == steps.length - 1;
    final Duration d = authMotion(context, 240);

    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'Paso $n: ${steps[i].title}. '
          '${done ? 'Completado' : (active ? 'Paso actual' : 'Pendiente')}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 34,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: d,
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? AppColors.primaryBlue
                          : Colors.white.withValues(alpha: active ? 1 : 0.65),
                      border: Border.all(
                        color: (done || active)
                            ? AppColors.primaryBlue
                            : AppColors.cardBorder,
                        width: active ? 2 : 1.2,
                      ),
                    ),
                    child: done
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : Text(
                            '$n',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: active
                                  ? AppColors.primaryBlue
                                  : _kBodyText,
                            ),
                          ),
                  ),
                  if (!last)
                    Expanded(
                      child: AnimatedContainer(
                        duration: d,
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.primaryBlue
                              : AppColors.cardBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: last ? 0 : 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      steps[i].title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: (done || active)
                            ? AppColors.darkNavy
                            : _kBodyText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      steps[i].subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: _kBodyText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botones y enlaces
// ─────────────────────────────────────────────────────────────────────────────

/// Botón principal: degradado suave, sombra azul, elevación al pasar el
/// cursor, anillo de foco, y estado de carga con spinner + texto.
class AuthPrimaryButton extends StatefulWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel = 'Procesando…',
    this.icon = Icons.arrow_forward_rounded,
    this.color = AppColors.primaryBlue,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String loadingLabel;
  final IconData? icon;
  final Color color;
  final double height;

  @override
  State<AuthPrimaryButton> createState() => _AuthPrimaryButtonState();
}

class _AuthPrimaryButtonState extends State<AuthPrimaryButton> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null && !widget.loading;
    final bool lifted = enabled && _hover;
    final Color c = widget.color;
    final Duration d = authMotion(context, 160);
    const TextStyle labelStyle = TextStyle(
      color: Colors.white,
      fontSize: 15.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: d,
        curve: Curves.easeOut,
        height: widget.height,
        transform: Matrix4.translationValues(0, lifted ? -1.5 : 0, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(c, Colors.white, 0.14)!, c],
          ),
          borderRadius: BorderRadius.circular(_kRadius),
          boxShadow: [
            if (_focus)
              BoxShadow(color: c.withValues(alpha: 0.30), spreadRadius: 4),
            BoxShadow(
              color: c.withValues(
                alpha: enabled || widget.loading
                    ? (lifted ? 0.38 : 0.26)
                    : 0.10,
              ),
              blurRadius: lifted ? 24 : 16,
              offset: Offset(0, lifted ? 10 : 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? widget.onPressed : null,
            onHover: (v) => setState(() => _hover = v),
            onFocusChange: (v) => setState(() => _focus = v),
            borderRadius: BorderRadius.circular(_kRadius),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            focusColor: Colors.white.withValues(alpha: 0.12),
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Center(
              child: AnimatedSwitcher(
                duration: d,
                child: widget.loading
                    ? Row(
                        key: const ValueKey('loading'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(widget.loadingLabel, style: labelStyle),
                        ],
                      )
                    : Row(
                        key: const ValueKey('idle'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.label,
                              style: labelStyle,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.icon != null) ...[
                            const SizedBox(width: 8),
                            AnimatedSlide(
                              duration: d,
                              offset: lifted
                                  ? const Offset(0.15, 0)
                                  : Offset.zero,
                              child: Icon(
                                widget.icon,
                                size: 20,
                                color: Colors.white,
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
    );
  }
}

/// Botón secundario de contorno (volver, atrás...).
class AuthOutlineButton extends StatefulWidget {
  const AuthOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 44,
    this.pill = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool pill;
  final String? semanticLabel;

  @override
  State<AuthOutlineButton> createState() => _AuthOutlineButtonState();
}

class _AuthOutlineButtonState extends State<AuthOutlineButton> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final double radius = widget.pill ? widget.height / 2 : _kRadius;
    final bool active = _hover || _focus;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: AnimatedContainer(
        duration: authMotion(context, 160),
        height: widget.height,
        decoration: BoxDecoration(
          color: _hover
              ? AppColors.primaryBlue.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: active ? AppColors.primaryBlue : AppColors.cardBorder,
            width: 1.5,
          ),
          boxShadow: [
            if (_focus)
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.25),
                spreadRadius: 3,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onPressed,
            onHover: (v) => setState(() => _hover = v),
            onFocusChange: (v) => setState(() => _focus = v),
            borderRadius: BorderRadius.circular(radius),
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            splashColor: AppColors.primaryBlue.withValues(alpha: 0.10),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.pill ? 16 : 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    AnimatedSlide(
                      duration: authMotion(context, 160),
                      offset: _hover ? const Offset(-0.12, 0) : Offset.zero,
                      child: Icon(
                        widget.icon,
                        size: 18,
                        color: active
                            ? AppColors.primaryBlue
                            : AppColors.darkNavy,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? AppColors.primaryBlue
                          : AppColors.darkNavy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Volver al inicio": versión en píldora del botón de contorno.
class AuthBackLink extends StatelessWidget {
  const AuthBackLink({
    super.key,
    required this.onTap,
    this.label = 'Volver al inicio',
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AuthOutlineButton(
      label: label,
      semanticLabel: semanticLabel,
      icon: Icons.arrow_back_rounded,
      onPressed: onTap,
      height: 40,
      pill: true,
    );
  }
}

/// Enlace que sube suavemente sobre un subrayado separado del texto.
class AuthTextLink extends StatefulWidget {
  const AuthTextLink({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color = AppColors.primaryBlue,
    this.fontSize = 13.5,
    this.dense = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color color;
  final double fontSize;

  /// Menos relleno, para colocarlo junto a una etiqueta.
  final bool dense;

  @override
  State<AuthTextLink> createState() => _AuthTextLinkState();
}

class _AuthTextLinkState extends State<AuthTextLink> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final TextStyle baseStyle =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w700,
          color: widget.color,
        );

    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          onFocusChange: (v) => setState(() => _focus = v),
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.transparent,
          focusColor: widget.color.withValues(alpha: 0.12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 2 : 6,
              vertical: widget.dense ? 2 : 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: widget.fontSize + 3,
                    color: widget.color,
                  ),
                  const SizedBox(width: 6),
                ],
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: authMotion(context, 160),
                      curve: Curves.easeOutCubic,
                      transform: Matrix4.translationValues(
                        0,
                        _hover || _focus ? -2 : 0,
                        0,
                      ),
                      child: Text(
                        widget.label,
                        style: baseStyle.copyWith(
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -3,
                      child: AnimatedOpacity(
                        opacity: _hover || _focus ? 1 : 0,
                        duration: authMotion(context, 160),
                        child: Container(height: 1, color: widget.color),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila al pie de la tarjeta para pasar de Login a Registro y viceversa.
class AuthSwitchRow extends StatelessWidget {
  const AuthSwitchRow({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
    this.color = AppColors.primaryBlue,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.cardBorder),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(prompt, style: TextStyle(fontSize: 13.5, color: _kBodyText)),
            AuthTextLink(label: action, onTap: onTap, color: color),
          ],
        ),
      ],
    );
  }
}

/// Ojo para mostrar/ocultar contraseña (área táctil de 40 px, con tooltip).
class AuthVisibilityToggle extends StatelessWidget {
  const AuthVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onPressed,
  });

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: obscured ? 'Mostrar contraseña' : 'Ocultar contraseña',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      iconSize: 20,
      color: AppColors.textMuted,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selector segmentado (Representante <-> Administrativo)
// ─────────────────────────────────────────────────────────────────────────────

class AuthSegment {
  const AuthSegment({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;
}

/// Selector con pastilla deslizante. Cada segmento es un botón con foco de
/// teclado; el color de la pastilla es el de cada segmento.
class AuthSegmentedSelector extends StatelessWidget {
  const AuthSegmentedSelector({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 48,
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
  Widget build(BuildContext context) {
    final Duration d = authMotion(context, 220);
    final AuthSegment active = segments[selectedIndex];

    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(_kRadius),
        border: Border.all(
          color: hasError ? kAuthError : AppColors.cardBorder,
          width: hasError ? 1.5 : 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final double segW = c.maxWidth / segments.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: d,
                curve: Curves.easeOutCubic,
                left: selectedIndex * segW,
                top: 0,
                bottom: 0,
                width: segW,
                child: AnimatedContainer(
                  duration: d,
                  decoration: BoxDecoration(
                    color: active.color,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: active.color.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
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
                        excludeSemantics: true,
                        onTap: () {
                          if (i != selectedIndex) onChanged(i);
                        },
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            focusColor: AppColors.primaryBlue.withValues(
                              alpha: 0.14,
                            ),
                            onTap: () {
                              if (i != selectedIndex) onChanged(i);
                            },
                            child: TweenAnimationBuilder<Color?>(
                              tween: ColorTween(
                                end: i == selectedIndex
                                    ? Colors.white
                                    : _kBodyText,
                              ),
                              duration: d,
                              builder: (context, color, _) => Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (segments[i].icon != null) ...[
                                      Icon(
                                        segments[i].icon,
                                        size: 18,
                                        color: color,
                                      ),
                                      const SizedBox(width: 7),
                                    ],
                                    Flexible(
                                      child: Text(
                                        segments[i].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: color,
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
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Campos de texto y mensajes de error (compartidos por Login y Registro)
// ─────────────────────────────────────────────────────────────────────────────

const TextStyle _kFieldMessageStyle = TextStyle(
  color: kAuthError,
  fontSize: 12,
  height: 1.3,
  fontWeight: FontWeight.w600,
);

/// Decoración común: borde gris, azul (acento) al pasar el cursor, azul grueso
/// al enfocar y ROJO cuando hay error. El mensaje sale debajo del campo.
InputDecoration authInputDecoration({
  required String hint,
  IconData? icon,
  Widget? prefix,
  Widget? suffix,
  Color activeColor = AppColors.primaryBlue,
  bool forceError = false,
  double vPad = 14,
  bool hovered = false,
  bool focused = false,
}) {
  OutlineInputBorder border(Color color, [double width = 1.2]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_kRadius),
        borderSide: BorderSide(color: color, width: width),
      );

  final Color idle = hovered
      ? Color.lerp(AppColors.cardBorder, activeColor, 0.45)!
      : AppColors.cardBorder;

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14.5),
    prefixIcon:
        prefix ??
        (icon != null
            ? Icon(
                icon,
                size: 20,
                color: forceError
                    ? kAuthError
                    : (focused ? activeColor : AppColors.textMuted),
              )
            : null),
    prefixIconConstraints: prefix != null
        ? const BoxConstraints(minWidth: 0, minHeight: 0)
        : null,
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: vPad),
    errorStyle: _kFieldMessageStyle,
    errorMaxLines: 3,
    border: border(AppColors.cardBorder),
    enabledBorder: forceError ? border(kAuthError, 1.6) : border(idle),
    focusedBorder: border(forceError ? kAuthError : activeColor, 2),
    errorBorder: border(kAuthError, 1.6),
    focusedErrorBorder: border(kAuthError, 2),
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
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.only(top: 6, left: left),
        child: Text(text, style: _kFieldMessageStyle),
      ),
    );
  }
}

/// Aviso de error general (no pertenece a un campo concreto). Va justo encima
/// del botón principal y se anuncia a lectores de pantalla.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
        decoration: BoxDecoration(
          color: _kAuthErrorSoft,
          borderRadius: BorderRadius.circular(_kRadius),
          border: Border.all(color: _kAuthErrorBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 19,
              color: kAuthError,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF991B1B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo con etiqueta, anillo de foco, borde rojo + mensaje cuando hay error,
/// texto de ayuda y un "check" verde opcional cuando el valor fue aceptado.
///
/// Cuándo se valida:
///  - al SALIR del campo (blur);
///  - después, en vivo mientras se corrige;
///  - y siempre al enviar el formulario (Form.validate).
///
/// [serverError] sirve para errores que vienen del servidor: se muestran en el
/// mismo campo y se limpian solos cuando el padre pone `null`.
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
    this.helperText,
    this.labelTrailing,
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

  /// Texto de ayuda bajo el campo; se oculta mientras haya un error.
  final String? helperText;

  /// Widget a la derecha de la etiqueta (p. ej. "¿Olvidaste tu contraseña?").
  final Widget? labelTrailing;

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
  bool _hasError = false;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    widget.revalidateWhen?.addListener(_onDependencyChanged);
    // Si el campo nace con un error del servidor (p. ej. al volver a un paso
    // anterior), se muestra de inmediato.
    if (widget.serverError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revalidate();
      });
    }
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

  /// Envuelve el validador para saber (y repintar) si el campo tiene error,
  /// incluso cuando la validación la dispara el Form al enviar.
  String? _validate(String? value) {
    final String? result = widget.validator?.call(value) ?? widget.serverError;
    final bool has = result != null;
    if (has != _hasError) {
      _hasError = has;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    return result;
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
    } else {
      setState(() {});
    }
  }

  void _onDependencyChanged() {
    if (mounted && _touched) _revalidate();
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = widget.focusNode.hasFocus;
    final bool showError = _hasError || widget.forceErrorBorder;
    final bool showSuccess =
        !focused &&
        _touched &&
        widget.successText != null &&
        widget.controller.text.isNotEmpty &&
        !_hasError;

    Widget footer = const SizedBox(width: double.infinity);
    if (showSuccess) {
      footer = Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              size: 15,
              color: AppColors.successGreen,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.successText!,
                style: const TextStyle(
                  color: _kAuthSuccessText,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (widget.helperText != null && !_hasError) {
      footer = Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(
          widget.helperText!,
          style: TextStyle(fontSize: 12, height: 1.35, color: _kBodyText),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.compact ? 12.5 : 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkNavy,
                ),
              ),
            ),
            if (widget.labelTrailing != null) widget.labelTrailing!,
          ],
        ),
        SizedBox(height: widget.compact ? 6 : 8),
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: authMotion(context, 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kRadius),
              boxShadow: [
                // Halo exterior difuminado; el borde mantiene el foco claro.
                if (focused && !showError)
                  BoxShadow(
                    color: widget.activeColor.withValues(alpha: 0.14),
                    blurRadius: 14,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: TextFormField(
              key: _fieldKey,
              controller: widget.controller,
              focusNode: widget.focusNode,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              autofillHints: widget.autofillHints,
              inputFormatters: widget.inputFormatters,
              onFieldSubmitted: widget.onFieldSubmitted,
              cursorColor: widget.activeColor,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: AppColors.darkNavy,
              ),
              onChanged: (value) {
                // En vivo solo si ya se validó antes o ya hay un error.
                if (_touched || _hasError) _revalidate();
                widget.onChanged?.call(value);
              },
              validator: _validate,
              decoration: authInputDecoration(
                hint: widget.hint,
                icon: widget.icon,
                prefix: widget.prefix,
                suffix: widget.suffix,
                activeColor: widget.activeColor,
                forceError: widget.forceErrorBorder,
                vPad: widget.compact || MediaQuery.sizeOf(context).height < 780
                    ? 12
                    : 14,
                hovered: _hover,
                focused: focused,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: authMotion(context, 160),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: footer,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo de estado (verificación pendiente, enlace expirado...)
// ─────────────────────────────────────────────────────────────────────────────

enum AuthTone { warning, danger, success }

class _ToneColors {
  const _ToneColors(this.accent, this.soft, this.border, this.text);

  final Color accent;
  final Color soft;
  final Color border;
  final Color text;
}

_ToneColors _toneColors(AuthTone t) {
  switch (t) {
    case AuthTone.warning:
      return const _ToneColors(
        Color(0xFFD97706),
        Color(0xFFFFFBEB),
        Color(0xFFFDE68A),
        Color(0xFF92400E),
      );
    case AuthTone.danger:
      return const _ToneColors(
        Color(0xFFDC2626),
        Color(0xFFFEF2F2),
        Color(0xFFFECACA),
        Color(0xFF991B1B),
      );
    case AuthTone.success:
      return const _ToneColors(
        Color(0xFF059669),
        Color(0xFFF0FDF4),
        Color(0xFFBBF7D0),
        Color(0xFF166534),
      );
  }
}

/// Diálogo con la misma identidad que las tarjetas: icono, etiqueta de estado,
/// título, mensaje, aviso destacado y una acción principal.
class AuthStatusDialog extends StatelessWidget {
  const AuthStatusDialog({
    super.key,
    required this.icon,
    required this.tone,
    required this.badge,
    required this.title,
    required this.message,
    required this.noticeTitle,
    required this.noticeText,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final AuthTone tone;
  final String badge;
  final String title;
  final Widget message;
  final String noticeTitle;
  final String noticeText;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final _ToneColors t = _toneColors(tone);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: t.soft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.border),
                ),
                child: Icon(icon, color: t.accent, size: 30),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: t.soft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.darkNavy,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DefaultTextStyle.merge(
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: _kBodyText),
                child: message,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.soft,
                  borderRadius: BorderRadius.circular(_kRadius),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule_rounded, color: t.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            noticeTitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            noticeText,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: t.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AuthPrimaryButton(label: primaryLabel, onPressed: onPrimary),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 8),
                AuthTextLink(
                  label: secondaryLabel!,
                  onTap: onSecondary!,
                  color: _kBodyText,
                  fontSize: 13,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
