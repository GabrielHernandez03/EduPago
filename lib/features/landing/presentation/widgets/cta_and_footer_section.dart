import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';

class CtaAndFooterSection extends StatelessWidget {
  final VoidCallback onRegisterPressed;
  final VoidCallback onContactPressed;

  const CtaAndFooterSection({
    super.key,
    required this.onRegisterPressed,
    required this.onContactPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(40, 12, 40, 60),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  children: [
                    const RevealOnScroll(
                      child: _SectionHeading(
                        eyebrow: 'ELIGE TU CAMINO',
                        title: 'Una plataforma, dos formas de empezar.',
                        subtitle:
                            'Ya seas representante o institución, el siguiente paso toma menos de un minuto.',
                      ),
                    ),
                    const SizedBox(height: 40),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isNarrow = constraints.maxWidth < 760;

                        // En escritorio entran desde los lados; en móvil, desde abajo.
                        final representanteCard = RevealOnScroll(
                          delay: const Duration(milliseconds: 120),
                          offset: isNarrow
                              ? const Offset(0, 40)
                              : const Offset(-50, 0),
                          child: _CtaCard(
                            eyebrow: 'PARA REPRESENTANTES',
                            icon: Icons.how_to_reg_rounded,
                            title:
                                '¿Ya te dieron permiso\npara crear tu cuenta?',
                            description:
                                'Si el colegio ya te registró como representante, activa tu acceso y gestiona los pagos de tus hijos en minutos.',
                            buttonLabel: 'Crear mi cuenta',
                            buttonIcon: Icons.arrow_forward,
                            onPressed: onRegisterPressed,
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            eyebrowColor: Colors.white70,
                            descriptionColor: Colors.white70,
                            buttonBackgroundColor: Colors.white,
                            buttonForegroundColor: AppColors.primaryBlue,
                            buttonHoverBackgroundColor: const Color(0xFFEFF6FF),
                          ),
                        );

                        final colegioCard = RevealOnScroll(
                          delay: const Duration(milliseconds: 260),
                          offset: isNarrow
                              ? const Offset(0, 40)
                              : const Offset(50, 0),
                          child: _CtaCard(
                            eyebrow: 'PARA INSTITUCIONES',
                            icon: Icons.school_rounded,
                            title: '¿Eres un colegio y\nquieres sumarte?',
                            description:
                                'Conversemos sobre cómo EduPago puede simplificar la gestión financiera y las cobranzas de tu institución.',
                            buttonLabel: 'Contáctanos',
                            buttonIcon: Icons.arrow_forward,
                            onPressed: onContactPressed,
                            backgroundColor: AppColors.darkNavy,
                            foregroundColor: Colors.white,
                            eyebrowColor: Colors.white60,
                            descriptionColor: Colors.white60,
                            buttonBackgroundColor: AppColors.primaryBlue,
                            buttonForegroundColor: Colors.white,
                            buttonHoverBackgroundColor: const Color(0xFF3B82F6),
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              representanteCard,
                              const SizedBox(height: 20),
                              colegioCard,
                            ],
                          );
                        }

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: representanteCard),
                              const SizedBox(width: 20),
                              Expanded(child: colegioCard),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Footer
          Container(
            width: double.infinity,
            color: AppColors.darkNavy,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: RevealOnScroll(
                  offset: const Offset(0, 16),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/images/logo_edupago.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'EduPago',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        '© 2026 EduPago. Tecnología para una educación que avanza.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FooterLink('Privacidad'),
                          SizedBox(width: 16),
                          _FooterLink('Términos'),
                          SizedBox(width: 16),
                          _FooterLink('Ayuda'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Link del footer: se ilumina y se subraya al pasar el mouse.
class _FooterLink extends StatelessWidget {
  final String text;

  const _FooterLink(this.text);

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            color: hovered ? Colors.white : Colors.white60,
            fontSize: 12,
            decoration: hovered
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: AppColors.primaryBlue,
            decorationThickness: 2,
          ),
          child: Text(text),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;

  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          eyebrow,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.darkNavy,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 16,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _CtaCard extends StatelessWidget {
  final String eyebrow;
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final IconData buttonIcon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color eyebrowColor;
  final Color descriptionColor;
  final Color buttonBackgroundColor;
  final Color buttonForegroundColor;
  final Color buttonHoverBackgroundColor;

  const _CtaCard({
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.eyebrowColor,
    required this.descriptionColor,
    required this.buttonBackgroundColor,
    required this.buttonForegroundColor,
    required this.buttonHoverBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      color: backgroundColor,
      borderColor: Colors.transparent,
      radius: 24,
      padding: EdgeInsets.zero,
      lift: 8,
      clip: true,
      shadowColor: backgroundColor,
      restShadowOpacity: 0.10,
      hoverShadowOpacity: 0.40,
      builder: (context, hovered) {
        return Stack(
          children: [
            // Círculo decorativo que crece al hacer hover
            Positioned(
              right: -40,
              top: -40,
              child: AnimatedScale(
                scale: hovered ? 1.4 : 1.0,
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(hovered ? 0.22 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedRotation(
                      turns: hovered ? 0.03 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      child: Icon(icon, color: foregroundColor, size: 20),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    eyebrow,
                    style: TextStyle(
                      color: eyebrowColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 24,
                      height: 1.25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: TextStyle(color: descriptionColor, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedButton(
                      label: buttonLabel,
                      icon: buttonIcon,
                      onPressed: onPressed,
                      expand: true,
                      background: buttonBackgroundColor,
                      hoverBackground: buttonHoverBackgroundColor,
                      foreground: buttonForegroundColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
