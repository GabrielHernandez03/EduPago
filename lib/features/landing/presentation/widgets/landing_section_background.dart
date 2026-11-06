import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Fondo de EduPago: ondas RELLENAS como las del hero (no trazos ovalados).
/// Conserva la API usada por las secciones existentes.
enum LandingWaveStyle {
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
    final dark = style == LandingWaveStyle.security ||
        style == LandingWaveStyle.footer;

    final decoratedContent = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _EduPagoWaves(style),
              ),
            ),
          ),
        ),
        child,
      ],
    );

    // Las secciones claras dejan ver el mismo fondo de home_screen.dart.
    // No usar ClipPath ni degradados: así no aparecen líneas entre secciones.
    return dark
        ? ColoredBox(color: AppColors.darkNavy, child: decoratedContent)
        : decoratedContent;
  }
}

class _EduPagoWaves extends CustomPainter {
  final LandingWaveStyle style;
  const _EduPagoWaves(this.style);

  static const Color azulHero = Color(0xFF075FFF);
  static const Color celeste = Color(0xFFBEDCFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // La franja de beneficios y el footer quedan limpios para evitar cortes.
    if (style == LandingWaveStyle.stats ||
        style == LandingWaveStyle.footer) {
      return;
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    switch (style) {
      case LandingWaveStyle.solutions:
        _topLeft(canvas, size, 1.0);
        _bottomRight(canvas, size, 1.0);
        break;
      case LandingWaveStyle.contact:
        _topLeft(canvas, size, 0.78);
        break;
      case LandingWaveStyle.faq:
        _bottomRight(canvas, size, 0.72);
        break;
      case LandingWaveStyle.action:
        _topLeft(canvas, size, 0.70);
        _bottomRight(canvas, size, 0.85);
        break;
      case LandingWaveStyle.security:
        _bottomRight(canvas, size, 0.70, dark: true);
        break;
      case LandingWaveStyle.stats:
      case LandingWaveStyle.footer:
        break;
    }

    canvas.restore();
  }

  // Como en la referencia: dos superficies azules, una sobre otra,
  // empezando FUERA del borde superior izquierdo.
  void _topLeft(Canvas canvas, Size size, double scale) {
    final w = size.width;
    final h = size.height;
    final waveWidth = math.min(w * 0.38, 680.0) * scale;
    final waveDepth = math.min(h * 0.26, 220.0) * scale;
    if (waveWidth < 1 || waveDepth < 1) return;

    final outer = Path()
      ..moveTo(0, 0)
      ..lineTo(waveWidth, 0)
      ..cubicTo(
        waveWidth * 0.70, waveDepth * 0.10,
        waveWidth * 0.34, waveDepth * 1.02,
        0, waveDepth,
      )
      ..close();
    canvas.drawPath(outer, Paint()..color = celeste);

    final innerWidth = waveWidth * 0.77;
    final innerDepth = waveDepth * 0.81;
    final inner = Path()
      ..moveTo(0, 0)
      ..lineTo(innerWidth, 0)
      ..cubicTo(
        innerWidth * 0.66, innerDepth * 0.12,
        innerWidth * 0.35, innerDepth * 1.03,
        0, innerDepth,
      )
      ..close();
    canvas.drawPath(inner, Paint()..color = azulHero);
  }

  // La ola inferior es MÁS ANCHA y sube con una curva suave.
  // Las formas están rellenas; no se usan Stroke ni extremos redondos.
  void _bottomRight(Canvas canvas, Size size, double scale, {bool dark = false}) {
    final w = size.width;
    final h = size.height;
    final waveWidth = math.min(w * 0.66, 1220.0) * scale;
    final waveDepth = math.min(h * 0.42, 350.0) * scale;
    if (waveWidth < 1 || waveDepth < 1) return;

    final outer = Path()
      ..moveTo(w - waveWidth, h)
      ..cubicTo(
        w - waveWidth * 0.56, h - waveDepth * 0.02,
        w - waveWidth * 0.39, h - waveDepth * 0.53,
        w - waveWidth * 0.18, h - waveDepth * 0.91,
      )
      ..cubicTo(
        w - waveWidth * 0.11, h - waveDepth * 1.06,
        w - waveWidth * 0.035, h - waveDepth * 0.97,
        w, h - waveDepth * 0.85,
      )
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      outer,
      Paint()..color = dark ? const Color(0xFF244F96) : celeste,
    );

    final inner = Path()
      ..moveTo(w - waveWidth * 0.76, h)
      ..cubicTo(
        w - waveWidth * 0.52, h - waveDepth * 0.04,
        w - waveWidth * 0.32, h - waveDepth * 0.53,
        w - waveWidth * 0.13, h - waveDepth * 0.77,
      )
      ..cubicTo(
        w - waveWidth * 0.075, h - waveDepth * 0.86,
        w - waveWidth * 0.025, h - waveDepth * 0.84,
        w, h - waveDepth * 0.78,
      )
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      inner,
      Paint()..color = dark ? const Color(0xFF1550B9) : azulHero,
    );
  }

  @override
  bool shouldRepaint(covariant _EduPagoWaves oldDelegate) =>
      style != oldDelegate.style;
}
