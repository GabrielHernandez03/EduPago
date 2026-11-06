import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';
import 'landing_section_background.dart';

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  static const _features = <_Feature>[
    _Feature(
      Icons.account_balance_wallet_outlined,
      'Pagos centralizados',
      'Consulta mensualidades y reporta tus pagos.',
      'Familias',
    ),
    _Feature(
      Icons.receipt_long_outlined,
      'Comprobantes',
      'Tu historial de reportes, siempre en orden.',
      'Familias',
    ),
    _Feature(
      Icons.verified_user_outlined,
      'Solvencia digital',
      'Estado de cuenta y constancias a la mano.',
      'Familias',
    ),
    _Feature(
      Icons.space_dashboard_outlined,
      'Control administrativo',
      'Pagos reportados, conciliación y cobranza.',
      'Colegios',
    ),
    _Feature(
      Icons.notifications_active_outlined,
      'Recordatorios oportunos',
      'Avisos de vencimiento y pagos pendientes.',
      'Familias',
    ),
    _Feature(
      Icons.insert_chart_outlined,
      'Reportes claros',
      'Cobranza y movimientos de un vistazo.',
      'Colegios',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final side = wide ? 59.52 : 20.46;
    return LandingSectionBackground(
      style: LandingWaveStyle.solutions,
      child: Container(
        padding: EdgeInsets.fromLTRB(side, 29.76, side, 76.26),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1153.2),
            child: Column(
              children: [
                const RevealOnScroll(
                  child: _SectionTitle(
                    eyebrow: 'SOLUCIONES',
                    title: 'Todo en un solo lugar.',
                    subtitle:
                        'Menos pasos y más claridad para familias y colegios.',
                  ),
                ),
                const SizedBox(height: 33.48),
                LayoutBuilder(
                  builder: (context, box) {
                    final columns = box.maxWidth >= 990
                        ? 3
                        : box.maxWidth >= 650
                        ? 2
                        : 1;
                    const spacing = 16.74;
                    final tileWidth =
                        (box.maxWidth - (columns - 1) * spacing) / columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (var i = 0; i < _features.length; i++)
                          SizedBox(
                            width: tileWidth,
                            child: RevealOnScroll(
                              delay: Duration(milliseconds: (i % 3) * 100),
                              startScale: 0.97,
                              child: _FeatureCard(item: _features[i]),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 91.14),
                const RevealOnScroll(
                  child: _SectionTitle(
                    eyebrow: 'ASÍ FUNCIONA',
                    title: 'Así de simple.',
                    subtitle: 'Un proceso claro de principio a fin.',
                  ),
                ),
                const SizedBox(height: 33.48),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final mobile = constraints.maxWidth < 780;
                    final steps = <_StepInfo>[
                      const _StepInfo(
                        '01',
                        Icons.person_add_alt_1_outlined,
                        'Accede',
                        'Crea tu cuenta con el registro de tu colegio.',
                      ),
                      const _StepInfo(
                        '02',
                        Icons.payments_outlined,
                        'Consulta y reporta',
                        'Revisa mensualidades y reporta tus pagos.',
                      ),
                      const _StepInfo(
                        '03',
                        Icons.task_alt_rounded,
                        'Haz seguimiento',
                        'Mira si tu reporte está en espera, aprobado o rechazado.',
                      ),
                    ];
                    if (mobile) {
                      return Column(
                        children: [
                          for (var i = 0; i < steps.length; i++) ...[
                            if (i != 0) const SizedBox(height: 14.88),
                            _StepCard(step: steps[i]),
                          ],
                        ],
                      );
                    }
                    // La fila toma la altura real de la tarjeta mas alta.
                    // Los tres pasos quedan iguales sin recortar los textos.
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < steps.length; i++) ...[
                            if (i != 0) const SizedBox(width: 16.74),
                            Expanded(child: _StepCard(step: steps[i])),
                          ],
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
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String description;
  final String audience;
  const _Feature(this.icon, this.title, this.description, this.audience);
}

class _FeatureCard extends StatefulWidget {
  final _Feature item;
  const _FeatureCard({required this.item});
  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 230),
      transform: Matrix4.translationValues(
        0,
        hover && !MediaQuery.disableAnimationsOf(context) ? -3.0 : 0,
        0,
      ),
      padding: const EdgeInsets.all(25.11),
      constraints: const BoxConstraints(minHeight: 186),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21.39),
        border: Border.all(
          color: hover ? const Color(0xFF8DBAFF) : const Color(0xFFE3EAF5),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: hover ? 0.10 : 0.035),
            blurRadius: hover ? 26.04 : 14.88,
            offset: const Offset(0, 8.37),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(11.16),
                decoration: BoxDecoration(
                  color: hover
                      ? AppColors.primaryBlue
                      : const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(13.95),
                ),
                child: Icon(
                  widget.item.icon,
                  color: hover ? Colors.white : AppColors.primaryBlue,
                  size: 23.25,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.23,
                  vertical: 5.58,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6FF),
                  borderRadius: BorderRadius.circular(18.6),
                ),
                child: Text(
                  widget.item.audience,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20.46),
          Text(
            widget.item.title,
            style: const TextStyle(
              color: AppColors.darkNavy,
              fontSize: 16.74,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8.37),
          Text(
            widget.item.description,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12.09,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        eyebrow,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.primaryBlue,
          fontSize: 11.16,
          letterSpacing: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 11.16),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 706.8),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.darkNavy,
            fontSize: MediaQuery.sizeOf(context).width < 600 ? 26.97 : 34.41,
            fontWeight: FontWeight.w900,
            height: 1.16,
            letterSpacing: -0.8,
          ),
        ),
      ),
      const SizedBox(height: 11.16),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 651),
        child: Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13.95,
            height: 1.55,
          ),
        ),
      ),
    ],
  );
}

class _StepInfo {
  final String number;
  final IconData icon;
  final String title;
  final String description;
  const _StepInfo(this.number, this.icon, this.title, this.description);
}

// Copia el tratamiento visual de _FeatureCard: mismo blanco, borde,
// radio, sombra, desplazamiento y cambio de icono al hacer hover.
class _StepCard extends StatefulWidget {
  final _StepInfo step;
  const _StepCard({required this.step});

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 230),
        transform: Matrix4.translationValues(
          0,
          hover && !reduceMotion ? -3.0 : 0,
          0,
        ),
        width: double.infinity,
        padding: const EdgeInsets.all(25.11),
        constraints: const BoxConstraints(minHeight: 186),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(21.39),
          border: Border.all(
            color: hover ? const Color(0xFF8DBAFF) : const Color(0xFFE3EAF5),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkNavy.withValues(alpha: hover ? 0.10 : 0.035),
              blurRadius: hover ? 26.04 : 14.88,
              offset: const Offset(0, 8.37),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.step.number,
                  style: TextStyle(
                    fontSize: 32.55,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryBlue.withValues(alpha: 0.38),
                  ),
                ),
                // Exactamente el mismo icono con fondo del bloque Soluciones.
                Container(
                  padding: const EdgeInsets.all(11.16),
                  decoration: BoxDecoration(
                    color: hover
                        ? AppColors.primaryBlue
                        : const Color(0xFFEAF3FF),
                    borderRadius: BorderRadius.circular(13.95),
                  ),
                  child: Icon(
                    widget.step.icon,
                    color: hover ? Colors.white : AppColors.primaryBlue,
                    size: 23.25,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20.46),
            Text(
              widget.step.title,
              style: const TextStyle(
                color: AppColors.darkNavy,
                fontSize: 16.74,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8.37),
            Text(
              widget.step.description,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.09,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
