import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';
import 'landing_section_background.dart';
import 'stats_bar_section.dart';

class CtaAndFooterSection extends StatelessWidget {
  final VoidCallback onRegisterPressed;
  final VoidCallback onContactPressed;
  final VoidCallback onSecurityPressed;

  const CtaAndFooterSection({
    super.key,
    required this.onRegisterPressed,
    required this.onContactPressed,
    required this.onSecurityPressed,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 780;

    final familyCard = _ActionCard(
      icon: Icons.family_restroom_rounded,
      eyebrow: 'PARA REPRESENTANTES',
      title: 'Ten tus pagos escolares a la mano.',
      body: 'Crea tu cuenta para consultar mensualidades y reportar pagos.',
      buttonText: 'Crear mi cuenta',
      navy: false,
      onPressed: onRegisterPressed,
    );
    final schoolCard = _ActionCard(
      icon: Icons.account_balance_outlined,
      eyebrow: 'PARA INSTITUCIONES',
      title: 'Dale a tu equipo más claridad.',
      body: 'Organiza la cobranza y el seguimiento de cuentas de tu colegio.',
      buttonText: 'Hablar con el equipo',
      navy: true,
      onPressed: onContactPressed,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Separación intencional en azul marino, como la barra de confianza.
        const LandingSeparatorBar(
          headline: 'DEL REGISTRO AL SEGUIMIENTO',
          items: <LandingSeparatorItem>[
            LandingSeparatorItem(
              Icons.person_add_alt_1_outlined,
              'Accede a tu cuenta',
            ),
            LandingSeparatorItem(
              Icons.receipt_long_outlined,
              'Consulta tus cuotas',
            ),
            LandingSeparatorItem(Icons.payments_outlined, 'Reporta tus pagos'),
            LandingSeparatorItem(Icons.fact_check_outlined, 'Revisa su estado'),
          ],
        ),
        LandingSectionBackground(
          style: LandingWaveStyle.action,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              narrow ? 20.46 : 59.52,
              60.45,
              narrow ? 20.46 : 59.52,
              77.19,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1116),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RevealOnScroll(
                      child: _Heading(
                        eyebrow: 'EL SIGUIENTE PASO',
                        title: 'Empieza con EduPago.',
                        subtitle: 'Una plataforma para familias y colegios.',
                      ),
                    ),
                    const SizedBox(height: 34.41),
                    // Dos columnas arriba (alineadas al inicio) o apiladas en
                    // pantallas angostas. Sin Flex + stretch: evita pedir una
                    // altura infinita dentro del scroll.
                    if (narrow) ...[
                      familyCard,
                      const SizedBox(height: 16.74),
                      schoolCard,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: familyCard),
                          const SizedBox(width: 18.6),
                          Expanded(child: schoolCard),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        LandingSectionBackground(
          style: LandingWaveStyle.footer,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 22.32 : 59.52,
              vertical: 31.62,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1116),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 20.46,
                  runSpacing: 18.6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo_edupago.png',
                          width: 32.55,
                          height: 32.55,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.school, color: Colors.white),
                        ),
                        const SizedBox(width: 9.3),
                        const Text(
                          'EduPago',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19.53,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      '© 2026 EduPago. Gestión escolar más sencilla.',
                      style: TextStyle(
                        color: Color(0xFFC6D7F4),
                        fontSize: 11.16,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: onSecurityPressed,
                          child: const Text(
                            'Seguridad',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        TextButton(
                          onPressed: onContactPressed,
                          child: const Text(
                            'Contacto',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatefulWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final String buttonText;
  final bool navy;
  final VoidCallback onPressed;

  const _ActionCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.buttonText,
    required this.navy,
    required this.onPressed,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => RevealOnScroll(
    child: MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -5 : 0, 0),
        decoration: BoxDecoration(
          color: widget.navy ? AppColors.darkNavy : AppColors.primaryBlue,
          borderRadius: BorderRadius.circular(25.11),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkNavy.withValues(
                alpha: _hovered ? 0.23 : 0.11,
              ),
              blurRadius: _hovered ? 30 : 20.46,
              offset: Offset(0, _hovered ? 15 : 8.37),
            ),
          ],
        ),
        // Recorta el círculo decorativo sin cortar la sombra de la tarjeta.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25.11),
          child: Stack(
            children: [
              // El círculo queda detrás del contenido y no recibe eventos.
              Positioned(
                top: -64,
                right: -51,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 230),
                    curve: Curves.easeOutCubic,
                    width: _hovered ? 190 : 172,
                    height: _hovered ? 190 : 172,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(
                        alpha: widget.navy
                            ? (_hovered ? 0.12 : 0.075)
                            : (_hovered ? 0.19 : 0.13),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(29.76),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11.16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(13.95),
                      ),
                      child: Icon(
                        widget.icon,
                        color: Colors.white,
                        size: 24.18,
                      ),
                    ),
                    const SizedBox(height: 16.74),
                    Text(
                      widget.eyebrow,
                      style: const TextStyle(
                        color: Color(0xFFDDEBFF),
                        fontSize: 11.16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 9.3),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24.18,
                        fontWeight: FontWeight.w900,
                        height: 1.23,
                      ),
                    ),
                    const SizedBox(height: 11.16),
                    Text(
                      widget.body,
                      style: const TextStyle(
                        color: Color(0xFFE0EBFF),
                        fontSize: 13.02,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 25.11),
                    AnimatedButton(
                      label: widget.buttonText,
                      onPressed: widget.onPressed,
                      icon: Icons.arrow_forward_rounded,
                      background: widget.navy
                          ? AppColors.primaryBlue
                          : Colors.white,
                      hoverBackground: widget.navy
                          ? const Color(0xFF377FFF)
                          : const Color(0xFFE5F0FF),
                      foreground: widget.navy
                          ? Colors.white
                          : AppColors.primaryBlue,
                      radius: 13.02,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  const _Heading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 650;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eyebrow,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.primaryBlue,
            fontSize: 11.16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 11.16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: mobile ? 27.9 : 35.34,
            fontWeight: FontWeight.w900,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 11.16),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13.95,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
