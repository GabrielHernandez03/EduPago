import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CustomNavbar extends StatelessWidget {
  final VoidCallback onInicioPressed;
  final VoidCallback onSolucionesPressed;
  final VoidCallback onSeguridadPressed;
  final VoidCallback onContactoPressed;
  final VoidCallback onLoginPressed;
  final VoidCallback onRegisterPressed;

  const CustomNavbar({
    super.key,
    required this.onInicioPressed,
    required this.onSolucionesPressed,
    required this.onSeguridadPressed,
    required this.onContactoPressed,
    required this.onLoginPressed,
    required this.onRegisterPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(
            color: Color(
              0xFFE2E8F0,
            ), // Borde definido y elegante para diferenciarlo
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo e Identidad EduPago (Bicolor y Logo Personalizado)
          InkWell(
            onTap: onInicioPressed,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Contenedor con Stack para proyectar sombra exacta en la silueta
                SizedBox(
                  width: 54,
                  height: 54,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Sombra difuminada detrás con desplazamiento
                      Positioned(
                        top: 8,
                        child: Opacity(
                          opacity: 0.10, // Intensidad de la sombra
                          child: Image.asset(
                            'assets/images/logo_edupago.png',
                            width: 48,
                            height: 48,
                            color: Colors
                                .black, // Vuelve silueta negra la copia trasera
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      // Logo real al frente
                      Image.asset(
                        'assets/images/logo_edupago.png',
                        width: 64,
                        height: 64,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                    children: [
                      TextSpan(
                        text: 'Edu',
                        style: TextStyle(color: AppColors.darkNavy),
                      ),
                      TextSpan(
                        text: 'Pago',
                        style: TextStyle(color: AppColors.primaryBlue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menú Navegación Fijo
          if (isDesktop)
            Row(
              children: [
                _NavLink(title: 'Inicio', onTap: onInicioPressed),
                _NavLink(title: 'Soluciones', onTap: onSolucionesPressed),
                _NavLink(title: 'Seguridad', onTap: onSeguridadPressed),
                _NavLink(title: 'Contacto', onTap: onContactoPressed),
              ],
            ),

          // Botones de Acción
          Row(
            children: [
              TextButton(
                onPressed: onLoginPressed,
                child: const Text(
                  'Iniciar sesión',
                  style: TextStyle(
                    color: AppColors.darkNavy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onRegisterPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                label: const Text(
                  'Crear cuenta',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                icon: const Icon(Icons.arrow_forward, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _NavLink({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.darkNavy,
            ),
          ),
        ),
      ),
    );
  }
}
