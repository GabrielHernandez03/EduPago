import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';

class _Feature {
  final IconData icon;
  final String title;
  final String description;

  const _Feature(this.icon, this.title, this.description);
}

const List<_Feature> _features = [
  _Feature(
    Icons.account_balance_wallet_outlined,
    'Pagos centralizados',
    'Consulta mensualidades, registra pagos y descarga comprobantes sin filas ni papeleo.',
  ),
  _Feature(
    Icons.bar_chart_rounded,
    'Control financiero',
    'Indicadores claros y reportes en tiempo real para tomar mejores decisiones.',
  ),
  _Feature(
    Icons.verified_user_outlined,
    'Solvencias al día',
    'Validación automática y constancias digitales siempre disponibles.',
  ),
  _Feature(
    Icons.notifications_none_rounded,
    'Alertas oportunas',
    'Recordatorios de vencimiento y confirmaciones para mantenerte informado.',
  ),
];

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 900;

    return Container(
      color: const Color.fromRGBO(248, 250, 252, 1),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Column(
        children: [
          const RevealOnScroll(
            offset: Offset(0, 16),
            child: Text(
              'TODO EN UN SOLO LUGAR',
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const RevealOnScroll(
            delay: Duration(milliseconds: 100),
            child: Text(
              'Más control para el colegio.\nMás calma para las familias.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.darkNavy,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const RevealOnScroll(
            delay: Duration(milliseconds: 200),
            child: Text(
              'Procesos financieros simples, transparentes y accesibles desde cualquier dispositivo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 15),
            ),
          ),
          const SizedBox(height: 48),

          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < _features.length; i++)
                RevealOnScroll(
                  delay: Duration(milliseconds: i * 110),
                  startScale: 0.96,
                  child: _FeatureCard(
                    feature: _features[i],
                    width: isDesktop ? 260 : 340,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _Feature feature;
  final double width;

  const _FeatureCard({required this.feature, required this.width});

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      width: width,
      hoverBorderColor: AppColors.primaryBlue.withOpacity(0.35),
      shadowColor: AppColors.primaryBlue,
      hoverShadowOpacity: 0.16,
      builder: (context, hovered) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // El icono se "enciende" al hacer hover
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hovered
                    ? AppColors.primaryBlue
                    : AppColors.primaryBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedScale(
                scale: hovered ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(
                    end: hovered ? Colors.white : AppColors.primaryBlue,
                  ),
                  duration: const Duration(milliseconds: 260),
                  builder: (context, color, _) =>
                      Icon(feature.icon, color: color, size: 24),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              feature.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.darkNavy,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              feature.description,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () {},
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Conocer más',
                    style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedSlide(
                    offset: Offset(hovered ? 0.4 : 0, 0),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    child: const Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: AppColors.primaryBlue,
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
