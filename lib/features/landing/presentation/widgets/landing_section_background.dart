import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Fondo de las secciones de la landing, dibujado 100 % con código
/// (sin imágenes ni assets).
///
/// Composición SIMÉTRICA por puntos (giro de 180°):
///  - esquina superior izquierda  == esquina inferior derecha
///    (onda grande con azul fuerte: UNA cinta, dos líneas blancas);
///  - esquina superior derecha    == esquina inferior izquierda
///    (onda suave y clara: UNA cinta, dos líneas blancas).
/// Cada borde es una sola curva Bézier (sin puntos intermedios), por eso no
/// tiene ondulaciones.
/// Todo se define UNA vez (esquina "TL" y esquina "TR") y las otras dos se
/// obtienen girando el lienzo, así que no pueden quedar desparejas.
///
/// Variación por sección: algunas secciones usan la composición espejada
/// (azul fuerte arriba-derecha / abajo-izquierda), así el fondo va cambiando
/// de diagonal mientras se baja por la página.
///
///   hero      -> azul fuerte arriba-izq + abajo-der
///   solutions -> azul fuerte arriba-der + abajo-izq
///   contact   -> azul fuerte arriba-izq + abajo-der
///   action    -> azul fuerte arriba-der + abajo-izq
///
/// Las barras navy separan las secciones claras, por eso no hay costuras.
enum LandingWaveStyle {
  hero,
  stats,
  solutions,
  security,
  contact,
  faq,
  action,
  footer,
}

class LandingSectionBackground extends StatelessWidget {
  final LandingWaveStyle style;
  final Widget child;

  const LandingSectionBackground({
    super.key,
    required this.style,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case LandingWaveStyle.security:
      case LandingWaveStyle.footer:
        return ColoredBox(color: AppColors.darkNavy, child: child);
      case LandingWaveStyle.stats:
        return child;
      case LandingWaveStyle.hero:
      case LandingWaveStyle.solutions:
      case LandingWaveStyle.contact:
      case LandingWaveStyle.faq:
      case LandingWaveStyle.action:
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(child: LandingBackdrop(style: style)),
            child,
          ],
        );
    }
  }
}

/// Solo la capa de fondo (sin contenido). Úsala como primer hijo de un Stack
/// con `Positioned.fill`, como hace el hero.
class LandingBackdrop extends StatelessWidget {
  final LandingWaveStyle style;
  const LandingBackdrop({super.key, required this.style});

  /// true = composición espejada (azul fuerte arriba-der / abajo-izq).
  bool get _mirrored =>
      style == LandingWaveStyle.solutions || style == LandingWaveStyle.action;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _WavesPainter(mirrored: _mirrored),
            // Pista al motor: dibujo costoso y estático (se cachea).
            isComplex: true,
            willChange: false,
          ),
        ),
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  final bool mirrored;
  const _WavesPainter({required this.mirrored});

  // Tamaño del diseño de referencia; todas las coordenadas de abajo están en
  // esas unidades y se escalan con `s`.
  static const double _designW = 1672;

  // ── Cluster FUERTE (esquina "TL": x desde la izquierda, y desde arriba) ──
  // Borde A: límite del azul intenso. Borde B: borde exterior de la cinta.
  static Path _strongA() => Path()
    ..moveTo(-30, 205)
    ..cubicTo(260, 200, 400, 20, 660, -25);

  static Path _strongB() => Path()
    ..moveTo(-30, 247)
    ..cubicTo(300, 265, 480, 30, 820, -25);

  // ── Cluster SUAVE (esquina "TR": x' desde el borde derecho, y desde arriba)
  // U: curva superior (baja y vuelve a subir). L: curva inferior; arranca
  // pegada a U y se separa suavemente.
  static Path _softU() => Path()
    ..moveTo(500, -10)
    ..cubicTo(380, 20, 260, 100, 172, 100)
    ..cubicTo(100, 100, 40, 60, -30, 30);

  static Path _softL() => Path()
    ..moveTo(500, -10)
    ..cubicTo(380, 20, 200, 140, -30, 148);

  /// Une la curva `from` hacia atrás (recorrida al revés) a `into`,
  /// para cerrar la región entre dos curvas.
  static Path _between(Path first, Path second) {
    final Path out = Path.from(first);
    final ui.PathMetric m = second.computeMetrics().first;
    // Recorre `second` al revés muestreándola; con 64 tramos el error es
    // invisible y evita tener que invertir curvas a mano.
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

    // Escala por ancho (con mínimo para móviles y tope por altura para que
    // las dos esquinas nunca se pisen en secciones bajas).
    final double s = math.min(math.max(w / _designW, 0.42), h / 600);

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    if (mirrored) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }

    _paintBase(canvas, w, h);

    // Suaves primero (TR y BL), fuertes encima (TL y BR).
    _corner(canvas, w, h, s, _Corner.topRight, _paintSoft);
    _corner(canvas, w, h, s, _Corner.bottomLeft, _paintSoft);
    _corner(canvas, w, h, s, _Corner.topLeft, _paintStrong);
    _corner(canvas, w, h, s, _Corner.bottomRight, _paintStrong);

    canvas.restore();
  }

  /// Viñeta elíptica: centro casi blanco, bordes azul claro.
  void _paintBase(Canvas canvas, double w, double h) {
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.scale(w / 2, h / 2);
    const double r = 1.6;
    canvas.drawRect(
      const Rect.fromLTRB(-2, -2, 2, 2),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          r,
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

  /// Coloca el origen local en la esquina pedida. Con `scale(-s, -s)` la
  /// esquina inferior derecha es EXACTAMENTE el giro de 180° de la superior
  /// izquierda (igual con TR/BL), de ahí la simetría.
  void _corner(
    Canvas canvas,
    double w,
    double h,
    double s,
    _Corner corner,
    void Function(Canvas) draw,
  ) {
    canvas.save();
    switch (corner) {
      case _Corner.topLeft:
        canvas.scale(s, s);
      case _Corner.topRight:
        canvas.translate(w, 0);
        canvas.scale(-s, s);
      case _Corner.bottomLeft:
        canvas.translate(0, h);
        canvas.scale(s, -s);
      case _Corner.bottomRight:
        canvas.translate(w, h);
        canvas.scale(-s, -s);
    }
    draw(canvas);
    canvas.restore();
  }

  static Paint _fill(ui.Shader shader) => Paint()..shader = shader;

  /// Borde de "cinta de cristal": brillo difuso muy leve + línea blanca fina.
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

  // ── Cluster fuerte: azul intenso + una cinta, dos líneas ────────────────
  void _paintStrong(Canvas canvas) {
    final Path a = _strongA();
    final Path b = _strongB();

    // Azul intenso (degradado elíptico desde la esquina).
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

    // Cinta entre A y B.
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

  // ── Cluster suave: una cinta clara, dos líneas ──────────────────────────
  void _paintSoft(Canvas canvas) {
    final Path u = _softU();
    final Path l = _softL();

    // Zona sobre U (se desvanece hacia el centro).
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

    // Cinta entre U y L.
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
  bool shouldRepaint(covariant _WavesPainter old) => old.mirrored != mirrored;
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }
