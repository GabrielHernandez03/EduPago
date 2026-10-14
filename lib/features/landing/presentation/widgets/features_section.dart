import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 900;

    return Container(
      // backgrund color
      color: const Color.fromRGBO(248, 250, 252, 1),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Column(
        children: [
          const Text(
            'TODO EN UN SOLO LUGAR',
            style: TextStyle(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Más control para el colegio.\nMás calma para las familias.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.darkNavy,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Procesos financieros simples, transparentes y accesibles desde cualquier dispositivo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 15),
          ),
          const SizedBox(height: 48),

          // Cards Grid
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _FeatureCard(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Pagos centralizados',
                description:
                    'Consulta mensualidades, registra pagos y descarga comprobantes sin filas ni papeleo.',
                width: isDesktop ? 260 : 340,
              ),
              _FeatureCard(
                icon: Icons.bar_chart_rounded,
                title: 'Control financiero',
                description:
                    'Indicadores claros y reportes en tiempo real para tomar mejores decisiones.',
                width: isDesktop ? 260 : 340,
              ),
              _FeatureCard(
                icon: Icons.verified_user_outlined,
                title: 'Solvencias al día',
                description:
                    'Validación automática y constancias digitales siempre disponibles.',
                width: isDesktop ? 260 : 340,
              ),
              _FeatureCard(
                icon: Icons.notifications_none_rounded,
                title: 'Alertas oportunas',
                description:
                    'Recordatorios de vencimiento y confirmaciones para mantenerte informado.',
                width: isDesktop ? 260 : 340,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final double width;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 24),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.darkNavy,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () {},
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Conocer más',
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AppColors.primaryBlue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
