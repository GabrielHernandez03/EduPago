import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class HeroSection extends StatelessWidget {
  final VoidCallback onStartPressed;
  final VoidCallback onLoginPressed;

  const HeroSection({
    super.key,
    required this.onStartPressed,
    required this.onLoginPressed,
  });

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 900;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 80,
        vertical: 40,
      ),
      child: Flex(
        direction: isMobile ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Lado Izquierdo: Textos y Botones
          Expanded(
            flex: isMobile ? 0 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag Superior
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 14, color: AppColors.primaryBlue),
                      SizedBox(width: 6),
                      Text(
                        'GESTIÓN ESCOLAR QUE SÍ AVANZA',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Título Principal
                const Text(
                  'La tranquilidad\nfinanciera de tu\ncomunidad\nescolar.',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkNavy,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 20),

                // Subtítulo
                const Text(
                  'Centraliza pagos, solvencias y cobranzas en una plataforma\nsegura, clara y creada para las instituciones educativas de\nVenezuela.',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                // Botones de CTA
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: onStartPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      label: const Text('Comenzar ahora', style: TextStyle(fontWeight: FontWeight.bold)),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton(
                      onPressed: onLoginPressed,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                        side: const BorderSide(color: AppColors.cardBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Ya tengo una cuenta',
                        style: TextStyle(color: AppColors.darkNavy, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // Social Proof
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      height: 32,
                      child: Stack(
                        children: [
                          _buildAvatar('MC', Colors.black, 0),
                          _buildAvatar('JR', Colors.amber, 20),
                          _buildAvatar('AG', Colors.green, 40),
                          _buildAvatar('+2k', AppColors.primaryBlue, 60),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Más de 2.000 familias', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('gestionan sus pagos con confianza', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (isMobile) const SizedBox(height: 40),

          // Lado Derecho: Imagen con Badges Flotantes
          Expanded(
            flex: isMobile ? 0 : 1,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Imagen Principal
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    height: 420,
                    width: double.infinity,
                    color: Colors.blueGrey.shade100,
                    child: Image.network(
                      'https://images.unsplash.com/photo-1577896851231-70ef18881754?auto=format&fit=crop&q=80',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                // Floating Badge 1: Solvente (Arriba a la derecha)
                Positioned(
                  top: 20,
                  right: -10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: AppColors.primaryBlue, size: 20),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Estado académico', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            Text('Solvente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.successGreen)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Floating Badge 2: Pago verificado (Abajo a la izquierda)
                Positioned(
                  bottom: -20,
                  left: -10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: AppColors.successGreen, size: 22),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pago verificado', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            Text('Mensualidad · Marzo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
                          ],
                        ),
                        SizedBox(width: 20),
                        Text('Bs. 2.450', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String text, Color bg, double leftOffset) {
    return Positioned(
      left: leftOffset,
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.white,
        child: CircleAvatar(
          radius: 14,
          backgroundColor: bg,
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}