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
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // Padding horizontal más moderado para que no se expanda tanto a los extremos en pantallas grandes
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1280,
          ), // Controla el ancho máximo de la barra
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Logo e Identidad EduPago
              InkWell(
                onTap: onInicioPressed,
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 6,
                            child: Opacity(
                              opacity: 0.10,
                              child: Image.asset(
                                'assets/images/logo_edupago.png',
                                width: 46,
                                height: 46,
                                color: Colors.black,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          Image.asset(
                            'assets/images/logo_edupago.png',
                            width: 62,
                            height: 62,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontFamily: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.fontFamily,
                          fontSize: 24,
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
                    child: Text(
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
                      // Tamaño original restaurado (padding vertical 16)
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
        ),
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
            style: TextStyle(
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
