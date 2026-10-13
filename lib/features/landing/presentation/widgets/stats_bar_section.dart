import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class StatsBarSection extends StatelessWidget {
  const StatsBarSection({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      width: double.infinity,
      color: AppColors.darkNavy,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 60,
        vertical: 36,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 30,
            runSpacing: 24,
            children: [
              // Texto Descriptivo Izquierdo
              const SizedBox(
                width: 240,
                child: Text(
                  'UNA SOLUCIÓN\nCONFIABLE PARA TODA LA\nCOMUNIDAD EDUCATIVA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    height: 1.5,
                  ),
                ),
              ),

              // Métricas / Estadísticas
              _buildStatItem(
                icon: Icons.business_outlined,
                title: '+35 colegios',
              ),
              _buildStatItem(
                icon: Icons.people_outline,
                title: '+2.000 familias',
              ),
              _buildStatItem(
                icon: Icons.receipt_long_outlined,
                title: '+18k transacciones',
              ),
              _buildStatItem(
                icon: Icons.verified_user_outlined,
                title: '99,9% disponible',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({required IconData icon, required String title}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 24),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
