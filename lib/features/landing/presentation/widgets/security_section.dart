import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';

class SecuritySection extends StatelessWidget {
  const SecuritySection({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      color: AppColors.securityBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 80,
        vertical: 80,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: Stack(
                  children: [
                    Align(
                      alignment: const Alignment(-1.1, -1.0),
                      child: DriftingGlow(
                        color: AppColors.primaryBlue,
                        size: 560,
                        opacity: 0.22,
                      ),
                    ),
                    Align(
                      alignment: const Alignment(1.1, 1.0),
                      child: DriftingGlow(
                        color: const Color(0xFF38BDF8),
                        size: 460,
                        phase: 0.5,
                        opacity: 0.14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Flex(
            direction: isMobile ? Axis.vertical : Axis.horizontal,
            children: [
              // Lado izquierdo: escudo con pulsos tipo radar
              Expanded(
                flex: isMobile ? 0 : 1,
                child: RevealOnScroll(
                  offset: const Offset(-40, 0),
                  startScale: 0.9,
                  duration: const Duration(milliseconds: 900),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const _PulseRings(),
                        Container(
                          width: 280,
                          height: 280,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                              width: 40,
                            ),
                          ),
                        ),
                        // El escudo "respira"
                        Loop(
                          duration: const Duration(milliseconds: 3200),
                          builder: (context, t, child) {
                            final double s =
                                1 + 0.05 * math.sin(t * 2 * math.pi);
                            return Transform.scale(scale: s, child: child);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryBlue.withOpacity(
                                    0.35,
                                  ),
                                  blurRadius: 40,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.shield_outlined,
                              color: AppColors.primaryBlue,
                              size: 50,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 40,
                          left: 20,
                          child: Floating(
                            amplitude: 5,
                            period: const Duration(milliseconds: 4000),
                            child: _buildBadge(
                              Icons.lock_outline,
                              'Cifrado TLS 1.3',
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 40,
                          right: 20,
                          child: Floating(
                            amplitude: 6,
                            phase: 0.5,
                            period: const Duration(milliseconds: 4600),
                            child: _buildBadge(Icons.check, 'Datos protegidos'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (isMobile) const SizedBox(height: 40),

              // Lado derecho: textos y checks escalonados
              Expanded(
                flex: isMobile ? 0 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RevealOnScroll(
                      offset: Offset(40, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SEGURIDAD SIN CONCESIONES',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Tu información está en buenas manos.',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Protegemos cada transacción y cada dato con estándares de seguridad de nivel bancario.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    const _CheckItem(
                      delay: Duration(milliseconds: 250),
                      title: 'Sesiones protegidas',
                      subtitle: 'Tokens seguros JWT y HttpOnly',
                    ),
                    const _CheckItem(
                      delay: Duration(milliseconds: 400),
                      title: 'Accesos por roles',
                      subtitle: 'Cada usuario ve únicamente lo que necesita',
                    ),
                    const _CheckItem(
                      delay: Duration(milliseconds: 550),
                      title: 'Trazabilidad completa',
                      subtitle: 'Registro auditable de cada operación',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.darkNavy),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.darkNavy,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tres anillos que se expanden y desvanecen desde el escudo (efecto radar).
class _PulseRings extends StatelessWidget {
  const _PulseRings();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Loop(
        duration: const Duration(milliseconds: 3600),
        builder: (context, t, _) {
          return Stack(
            alignment: Alignment.center,
            children: [for (var i = 0; i < 3; i++) _ring((t + i / 3) % 1.0)],
          );
        },
      ),
    );
  }

  Widget _ring(double p) {
    final double size = 110 + 170 * p;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primaryBlue.withOpacity((1 - p) * 0.35),
          width: 1.5,
        ),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final Duration delay;
  final String title;
  final String subtitle;

  const _CheckItem({
    required this.delay,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return RevealOnScroll(
      delay: delay,
      offset: const Offset(30, 0),
      child: HoverBuilder(
        builder: (context, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(hovered ? 6 : 0, 0, 0),
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: hovered
                        ? AppColors.successGreen.withOpacity(0.22)
                        : Colors.white10,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: AppColors.successGreen,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
