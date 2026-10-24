import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Capa de movimiento compartida por toda la landing.
///
/// Sin dependencias externas. Todo respeta `MediaQuery.disableAnimations`
/// (accesibilidad: "reducir movimiento"): las animaciones automáticas se
/// desactivan y el contenido aparece directamente.

bool _reduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;

// ─────────────────────────────────────────────────────────────────────────────
// InView: avisa (una sola vez) cuando el widget entra al viewport del scroll.
// ─────────────────────────────────────────────────────────────────────────────
class InView extends StatefulWidget {
  const InView({
    super.key,
    required this.builder,
    this.delay = Duration.zero,
    this.triggerAt = 0.9,
  });

  final Widget Function(BuildContext context, bool inView) builder;

  /// Espera extra antes de marcar "visible" (sirve para escalonar elementos).
  final Duration delay;

  /// Fracción de la altura del viewport a partir de la cual se dispara.
  /// 0.9 = cuando el borde superior del widget sube del 90% de la pantalla.
  final double triggerAt;

  @override
  State<InView> createState() => _InViewState();
}

class _InViewState extends State<InView> {
  ScrollPosition? _position;
  Timer? _timer;
  bool _triggered = false;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_check);
      _position = position;
      if (!_triggered) _position?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_triggered || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;

    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    final double top;
    final double height;
    if (viewport is RenderBox && viewport.hasSize) {
      top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      height = viewport.size.height;
    } else {
      top = box.localToGlobal(Offset.zero).dy;
      height = MediaQuery.of(context).size.height;
    }

    if (top <= height * widget.triggerAt) _fire();
  }

  void _fire() {
    _triggered = true;
    _position?.removeListener(_check);
    if (widget.delay == Duration.zero || _reduceMotion(context)) {
      setState(() => _visible = true);
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _position?.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _visible);
}

// ─────────────────────────────────────────────────────────────────────────────
// RevealOnScroll: fade + desplazamiento (+ escala opcional) al entrar a pantalla.
// ─────────────────────────────────────────────────────────────────────────────
class RevealOnScroll extends StatelessWidget {
  const RevealOnScroll({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 700),
    this.offset = const Offset(0, 32),
    this.startScale = 1.0,
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Desplazamiento inicial en píxeles (dx, dy). Termina en (0, 0).
  final Offset offset;
  final double startScale;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) return child;

    return InView(
      delay: delay,
      builder: (context, inView) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: inView ? 1 : 0),
          duration: duration,
          curve: curve,
          child: child,
          builder: (context, t, child) {
            final double opacity = t.clamp(0.0, 1.0).toDouble();
            Widget result = Transform.translate(
              offset: Offset(offset.dx * (1 - t), offset.dy * (1 - t)),
              child: child,
            );
            if (startScale != 1.0) {
              result = Transform.scale(
                scale: startScale + (1 - startScale) * t,
                child: result,
              );
            }
            return Opacity(opacity: opacity, child: result);
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CountUp: número que "sube" hasta su valor final al entrar a pantalla.
// Formato es-VE: punto para miles, coma para decimales.
// ─────────────────────────────────────────────────────────────────────────────
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.end,
    required this.style,
    this.decimals = 0,
    this.prefix = '',
    this.suffix = '',
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 1600),
  });

  final double end;
  final int decimals;
  final String prefix;
  final String suffix;
  final TextStyle style;
  final Duration delay;
  final Duration duration;

  static String format(double value, int decimals) {
    final parts = value.toStringAsFixed(decimals).split('.');
    final integer = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return decimals > 0 ? '$integer,${parts[1]}' : integer;
  }

  @override
  Widget build(BuildContext context) {
    final finalText = '$prefix${format(end, decimals)}$suffix';
    if (_reduceMotion(context)) return Text(finalText, style: style);

    return InView(
      delay: delay,
      builder: (context, inView) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: inView ? end : 0),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, value, _) {
            // El texto final se reserva invisible para que el ancho no "salte"
            // mientras los dígitos cambian.
            return Stack(
              children: [
                Opacity(opacity: 0, child: Text(finalText, style: style)),
                Text('$prefix${format(value, decimals)}$suffix', style: style),
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loop: animación continua (0..1) que se apaga con "reducir movimiento".
// ─────────────────────────────────────────────────────────────────────────────
class Loop extends StatefulWidget {
  const Loop({
    super.key,
    required this.duration,
    required this.builder,
    this.child,
  });

  final Duration duration;
  final Widget Function(BuildContext context, double t, Widget? child) builder;
  final Widget? child;

  @override
  State<Loop> createState() => _LoopState();
}

class _LoopState extends State<Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) =>
            widget.builder(context, _controller.value, child),
      ),
    );
  }
}

/// Flotación suave arriba/abajo (para badges y elementos decorativos).
class Floating extends StatelessWidget {
  const Floating({
    super.key,
    required this.child,
    this.amplitude = 6,
    this.period = const Duration(seconds: 4),
    this.phase = 0,
  });

  final Widget child;
  final double amplitude;
  final Duration period;

  /// Desfase (0..1) para que varios elementos no se muevan sincronizados.
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Loop(
      duration: period,
      child: child,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, math.sin((t + phase) * 2 * math.pi) * amplitude),
        child: child,
      ),
    );
  }
}

/// Resplandor circular que deriva lentamente (fondos).
class DriftingGlow extends StatelessWidget {
  const DriftingGlow({
    super.key,
    required this.color,
    this.size = 360,
    this.dx = 28,
    this.dy = 20,
    this.period = const Duration(seconds: 12),
    this.phase = 0,
    this.opacity = 0.18,
  });

  final Color color;
  final double size;
  final double dx;
  final double dy;
  final Duration period;
  final double phase;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Loop(
      duration: period,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withOpacity(opacity), color.withOpacity(0)],
            ),
          ),
        ),
      ),
      builder: (context, t, child) {
        final angle = (t + phase) * 2 * math.pi;
        return Transform.translate(
          offset: Offset(math.sin(angle) * dx, math.cos(angle) * dy),
          child: child,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hover
// ─────────────────────────────────────────────────────────────────────────────
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = MouseCursor.defer,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// Tarjeta con elevación al hover: se levanta, la sombra crece y el borde
/// cambia. Si tiene [onTap], también se hunde levemente al presionar.
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.builder,
    this.width,
    this.color = Colors.white,
    this.borderColor = AppColors.cardBorder,
    this.hoverBorderColor,
    this.radius = 16,
    this.padding = const EdgeInsets.all(24),
    this.onTap,
    this.lift = 6,
    this.shadowColor = const Color(0xFF0F172A),
    this.restShadowOpacity = 0.03,
    this.hoverShadowOpacity = 0.12,
    this.clip = false,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final double? width;
  final Color color;
  final Color borderColor;
  final Color? hoverBorderColor;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double lift;
  final Color shadowColor;
  final double restShadowOpacity;
  final double hoverShadowOpacity;
  final bool clip;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final bool tappable = widget.onTap != null;

    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: tappable ? (_) => _setPressed(true) : null,
        onTapUp: tappable ? (_) => _setPressed(false) : null,
        onTapCancel: tappable ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: widget.width,
            padding: widget.padding,
            clipBehavior: widget.clip ? Clip.antiAlias : Clip.none,
            transform: Matrix4.translationValues(
              0,
              _hovered ? -widget.lift : 0,
              0,
            ),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(
                color: _hovered
                    ? (widget.hoverBorderColor ?? widget.borderColor)
                    : widget.borderColor,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.shadowColor.withOpacity(
                    _hovered
                        ? widget.hoverShadowOpacity
                        : widget.restShadowOpacity,
                  ),
                  blurRadius: _hovered ? 32 : 12,
                  offset: Offset(0, _hovered ? 16 : 4),
                ),
              ],
            ),
            child: widget.builder(context, _hovered),
          ),
        ),
      ),
    );
  }
}

/// Botón con hover (sube 2px, brillo de color, la flecha se desliza) y ripple.
class AnimatedButton extends StatefulWidget {
  const AnimatedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward,
    this.background = AppColors.primaryBlue,
    this.foreground = Colors.white,
    this.hoverBackground,
    this.borderColor,
    this.hoverBorderColor,
    this.glowColor,
    this.expand = false,
    this.fontWeight = FontWeight.bold,
    this.radius = 10,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color background;
  final Color foreground;
  final Color? hoverBackground;
  final Color? borderColor;
  final Color? hoverBorderColor;
  final Color? glowColor;
  final bool expand;
  final FontWeight fontWeight;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final glow = widget.glowColor;
    final radius = BorderRadius.circular(widget.radius);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: widget.expand ? double.infinity : null,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: _hovered
              ? (widget.hoverBackground ?? widget.background)
              : widget.background,
          borderRadius: radius,
          border: widget.borderColor == null
              ? null
              : Border.all(
                  color: _hovered
                      ? (widget.hoverBorderColor ?? widget.borderColor!)
                      : widget.borderColor!,
                ),
          boxShadow: glow == null
              ? const []
              : [
                  BoxShadow(
                    color: glow.withOpacity(_hovered ? 0.40 : 0.0),
                    blurRadius: _hovered ? 22 : 0,
                    offset: Offset(0, _hovered ? 8 : 0),
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onPressed,
            child: Padding(
              padding: widget.padding,
              child: Row(
                mainAxisSize: widget.expand
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.foreground,
                      fontWeight: widget.fontWeight,
                    ),
                  ),
                  if (widget.icon != null) ...[
                    const SizedBox(width: 8),
                    AnimatedSlide(
                      offset: Offset(_hovered ? 0.35 : 0, 0),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Icon(
                        widget.icon,
                        size: 16,
                        color: widget.foreground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
