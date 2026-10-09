import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class SecuritySection extends StatelessWidget {
  const SecuritySection({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      color: AppColors.securityBg,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 80, vertical: 80),
      child: Flex(
        direction: isMobile ? Axis.vertical : Axis.horizontal,
        children: [
          // Lado Izquierdo: Gráfico de Escudo
          Expanded(
            flex: isMobile ? 0 : 1,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.08), width: 40),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.shield_outlined, color: AppColors.primaryBlue, size: 50),
                  ),
                  Positioned(
                    top: 40,
                    left: 20,
                    child: _buildBadge(Icons.lock_outline, 'Cifrado TLS 1.3'),
                  ),
                  Positioned(
                    bottom: 40,
                    right: 20,
                    child: _buildBadge(Icons.check, 'Datos protegidos'),
                  ),
                ],
              ),
            ),
          ),

          if (isMobile) const SizedBox(height: 40),

          // Lado Derecho: Textos e Ítems de Seguridad
          Expanded(
            flex: isMobile ? 0 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SEGURIDAD SIN CONCESIONES',
                  style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tu información está en buenas manos.',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Protegemos cada transacción y cada dato con estándares de seguridad de nivel bancario.',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 30),
                _buildCheckItem('Sesiones protegidas', 'Tokens seguros JWT y HttpOnly'),
                _buildCheckItem('Accesos por roles', 'Cada usuario ve únicamente lo que necesita'),
                _buildCheckItem('Trazabilidad completa', 'Registro auditable de cada operación'),
              ],
            ),
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
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.darkNavy),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.white10,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: AppColors.successGreen, size: 16),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}