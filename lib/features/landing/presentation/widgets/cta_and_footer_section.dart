import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class CtaAndFooterSection extends StatelessWidget {
  final VoidCallback onRegisterPressed;

  const CtaAndFooterSection({super.key, required this.onRegisterPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          // Banner Azul CTA
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center, // Propiedad corregida
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('EMPIEZA HOY', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                        SizedBox(height: 8),
                        Text(
                          'Una escuela solvente es una escuela\nque crece.',
                          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text('Únete a las instituciones que ya simplificaron su gestión financiera con EduPago.', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: onRegisterPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      label: const Text('Crear mi cuenta', style: TextStyle(fontWeight: FontWeight.bold)),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Footer Oscuro
          Container(
            width: double.infinity,
            color: AppColors.darkNavy,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center, // Propiedad corregida
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.phonelink_setup, color: Colors.white, size: 18),
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
                        Text('Privacidad', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        SizedBox(width: 16),
                        Text('Términos', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        SizedBox(width: 16),
                        Text('Ayuda', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}