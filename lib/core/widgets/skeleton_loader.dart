import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// =============================================================================
// Skeleton loaders (sin paquetes externos)
//
// Ubicación sugerida: lib/core/widgets/skeleton_loader.dart
//
// Uso:
//   Representante -> RepresentativeDashboardSkeleton(padding: ...)
//   Administrador -> AdminDashboardSkeleton(padding: ...)
// =============================================================================

const Color _kSkeletonBase = Color(0xFFE2E8F0);
const Color _kSkeletonHighlight = Color(0xFFF1F5F9);

// -----------------------------------------------------------------------------
// Animación compartida (una sola para todas las piezas del skeleton)
// -----------------------------------------------------------------------------
class _SkeletonAnimation extends InheritedNotifier<AnimationController> {
  const _SkeletonAnimation({
    required AnimationController controller,
    required super.child,
  }) : super(notifier: controller);
}

/// Envuelve un conjunto de piezas [SkeletonBox] y les da el brillo animado.
class SkeletonScope extends StatefulWidget {
  final Widget child;
  const SkeletonScope({super.key, required this.child});

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando contenido',
      child: ExcludeSemantics(
        child: _SkeletonAnimation(controller: _controller, child: widget.child),
      ),
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  final double t;
  const _SlideGradientTransform(this.t);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
  }
}

// -----------------------------------------------------------------------------
// Piezas básicas
// -----------------------------------------------------------------------------

/// Rectángulo (o círculo) gris con brillo animado.
/// Dentro de un Row debe ir con [width] o dentro de un Expanded.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context
        .dependOnInheritedWidgetOfExactType<_SkeletonAnimation>()
        ?.notifier;
    final t = controller?.value ?? 0.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: const [_kSkeletonBase, _kSkeletonHighlight, _kSkeletonBase],
          stops: const [0.1, 0.5, 0.9],
          transform: _SlideGradientTransform(t),
        ),
      ),
    );
  }
}

/// Línea de texto simulada.
class _Line extends StatelessWidget {
  final double? width;
  final double height;
  const _Line({this.width, this.height = 12});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: width, height: height, radius: 6);
}

/// Tarjeta blanca con borde, igual a las del dashboard.
class SkeletonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SkeletonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

/// Fila "icono + dos líneas + valor a la derecha" (actividad / pagos).
class _ListRowSkeleton extends StatelessWidget {
  const _ListRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SkeletonBox(width: 40, height: 40, circle: true),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(width: 160, height: 13),
                SizedBox(height: 8),
                _Line(width: 100, height: 10),
              ],
            ),
          ),
          SizedBox(width: 12),
          SkeletonBox(width: 64, height: 14, radius: 6),
        ],
      ),
    );
  }
}

Widget _scrollable({
  required EdgeInsetsGeometry padding,
  required double maxWidth,
  required Widget child,
}) {
  return SkeletonScope(
    child: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    ),
  );
}

// =============================================================================
// REPRESENTANTE
// =============================================================================
class RepresentativeDashboardSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const RepresentativeDashboardSkeleton({
    super.key,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return _scrollable(
      padding: padding,
      maxWidth: 1000,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabecera del representante
              const SkeletonCard(
                child: Row(
                  children: [
                    SkeletonBox(width: 56, height: 56, circle: true),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Line(width: 200, height: 16),
                          SizedBox(height: 10),
                          _Line(width: 130, height: 11),
                        ],
                      ),
                    ),
                    SizedBox(width: 16),
                    SkeletonBox(width: 88, height: 34, radius: 10),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Estudiantes
              const _Line(width: 150, height: 16),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(
                    child: SkeletonCard(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          SkeletonBox(width: 40, height: 40, circle: true),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Line(width: 120, height: 13),
                                SizedBox(height: 8),
                                _Line(width: 80, height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: SkeletonCard(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          SkeletonBox(width: 40, height: 40, circle: true),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Line(width: 100, height: 13),
                                SizedBox(height: 8),
                                _Line(width: 70, height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Banner de estado académico
              const SkeletonBox(height: 56, radius: 14),
              const SizedBox(height: 16),

              // Tarjeta "saldo pendiente"
              const SkeletonCard(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(width: 190, height: 15),
                    SizedBox(height: 22),
                    _Line(width: 70, height: 10),
                    SizedBox(height: 10),
                    _Line(width: 170, height: 38),
                    SizedBox(height: 22),
                    SkeletonBox(height: 40, radius: 10),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Estado de cuenta desglosado
              const SkeletonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(width: 210, height: 15),
                    SizedBox(height: 8),
                    _Line(width: 280, height: 10),
                    SizedBox(height: 18),
                    SkeletonBox(height: 52, radius: 12),
                    SizedBox(height: 10),
                    SkeletonBox(height: 52, radius: 12),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Botones de acción
              if (narrow) ...[
                const SkeletonBox(height: 46, radius: 12),
                const SizedBox(height: 12),
                const SkeletonBox(height: 46, radius: 12),
              ] else
                const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SkeletonBox(height: 46, radius: 12),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SkeletonBox(height: 46, radius: 12),
                    ),
                  ],
                ),
              const SizedBox(height: 28),

              // Actividad reciente
              const SkeletonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(width: 160, height: 15),
                    SizedBox(height: 6),
                    _Line(width: 220, height: 10),
                    SizedBox(height: 10),
                    _ListRowSkeleton(),
                    _ListRowSkeleton(),
                    _ListRowSkeleton(),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Documentos digitales
              SkeletonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Line(width: 180, height: 15),
                    const SizedBox(height: 16),
                    if (narrow) ...[
                      const SkeletonBox(height: 84, radius: 12),
                      const SizedBox(height: 12),
                      const SkeletonBox(height: 84, radius: 12),
                    ] else
                      const Row(
                        children: [
                          Expanded(child: SkeletonBox(height: 84, radius: 12)),
                          SizedBox(width: 12),
                          Expanded(child: SkeletonBox(height: 84, radius: 12)),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// ADMINISTRADOR
// =============================================================================
class AdminDashboardSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const AdminDashboardSkeleton({
    super.key,
    this.padding = const EdgeInsets.all(24),
  });

  static const List<double> _barHeights = [
    60,
    90,
    75,
    120,
    100,
    140,
    110,
    150,
    95,
    130,
    105,
    125,
  ];

  @override
  Widget build(BuildContext context) {
    return _scrollable(
      padding: padding,
      maxWidth: 1200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final wide = w >= 900;
          final kpiCols = wide ? 4 : 2;
          const gap = 16.0;
          final kpiWidth = (w - gap * (kpiCols - 1)) / kpiCols;

          final chartCard = SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Line(width: 180, height: 15),
                const SizedBox(height: 6),
                const _Line(width: 120, height: 10),
                const SizedBox(height: 24),
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final h in _barHeights) ...[
                        Expanded(child: SkeletonBox(height: h, radius: 6)),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );

          const donutCard = SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(width: 150, height: 15),
                SizedBox(height: 6),
                _Line(width: 100, height: 10),
                SizedBox(height: 22),
                Center(
                  child: SkeletonBox(width: 140, height: 140, circle: true),
                ),
                SizedBox(height: 22),
                _Line(height: 11),
                SizedBox(height: 10),
                _Line(height: 11),
                SizedBox(height: 10),
                _Line(height: 11),
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Saludo + acciones rápidas
              const _Line(width: 130, height: 11),
              const SizedBox(height: 10),
              const _Line(width: 280, height: 28),
              const SizedBox(height: 10),
              const _Line(width: 220, height: 13),
              const SizedBox(height: 20),
              const Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SkeletonBox(width: 170, height: 44, radius: 12),
                  SkeletonBox(width: 170, height: 44, radius: 12),
                  SkeletonBox(width: 170, height: 44, radius: 12),
                  SkeletonBox(width: 170, height: 44, radius: 12),
                ],
              ),
              const SizedBox(height: 20),

              // KPIs
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: List.generate(
                  4,
                  (_) => SizedBox(
                    width: kpiWidth,
                    child: const SkeletonCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 36, height: 36, radius: 10),
                          SizedBox(height: 16),
                          _Line(width: 90, height: 11),
                          SizedBox(height: 10),
                          _Line(width: 130, height: 26),
                          SizedBox(height: 10),
                          _Line(width: 100, height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Gráficos
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: chartCard),
                    const SizedBox(width: 16),
                    const Expanded(flex: 2, child: donutCard),
                  ],
                )
              else ...[
                chartCard,
                const SizedBox(height: 16),
                donutCard,
              ],
              const SizedBox(height: 20),

              // Pagos recientes
              const SkeletonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(width: 170, height: 15),
                    SizedBox(height: 6),
                    _Line(width: 240, height: 10),
                    SizedBox(height: 10),
                    _ListRowSkeleton(),
                    _ListRowSkeleton(),
                    _ListRowSkeleton(),
                    _ListRowSkeleton(),
                    _ListRowSkeleton(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
