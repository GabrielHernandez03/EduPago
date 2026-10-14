import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CustomNavbar extends StatelessWidget {
  final VoidCallback onInicioPressed;
  final VoidCallback onSolucionesPressed;
  final VoidCallback onSeguridadPressed;
  final VoidCallback onContactoPressed;
  final VoidCallback onLoginPressed;
  final VoidCallback onRegisterPressed;

  /// Título del link activo (ej. 'Inicio'), para resaltarlo en el menú.
  /// Opcional: si se omite, ningún link se marca como activo.
  final String? activeLink;

  const CustomNavbar({
    super.key,
    required this.onInicioPressed,
    required this.onSolucionesPressed,
    required this.onSeguridadPressed,
    required this.onContactoPressed,
    required this.onLoginPressed,
    required this.onRegisterPressed,
    this.activeLink,
  });

  List<_NavItem> get _navItems => [
    _NavItem('Inicio', Icons.home_rounded, onInicioPressed),
    _NavItem('Soluciones', Icons.auto_awesome_rounded, onSolucionesPressed),
    _NavItem('Seguridad', Icons.shield_rounded, onSeguridadPressed),
    _NavItem('Contacto', Icons.mail_rounded, onContactoPressed),
  ];

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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Logo e Identidad EduPago (con hover que agranda logo + texto)
              _LogoBrand(onTap: onInicioPressed),

              // Menú Navegación Fijo (desktop) con iconos + hover + estado activo
              if (isDesktop)
                Row(
                  children: _navItems
                      .map(
                        (item) => _NavLink(
                          title: item.title,
                          icon: item.icon,
                          onTap: item.onTap,
                          isActive: activeLink == item.title,
                        ),
                      )
                      .toList(),
                ),

              // Botones de Acción (desktop) / Menú hamburguesa (mobile)
              if (isDesktop)
                Row(
                  children: [
                    _HoverTextButton(
                      icon: Icons.login_rounded,
                      label: 'Iniciar sesión',
                      onTap: onLoginPressed,
                    ),
                    const SizedBox(width: 12),
                    _GlowingRegisterButton(onTap: onRegisterPressed),
                  ],
                )
              else
                _MobileMenu(
                  navItems: _navItems,
                  activeLink: activeLink,
                  onLoginPressed: onLoginPressed,
                  onRegisterPressed: onRegisterPressed,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  _NavItem(this.title, this.icon, this.onTap);
}

/// Logo + nombre "EduPago": al pasar el mouse, ambos se agrandan levemente;
/// al hacer clic, redirige a Inicio vía [onTap].
class _LogoBrand extends StatefulWidget {
  final VoidCallback onTap;

  const _LogoBrand({required this.onTap});

  @override
  State<_LogoBrand> createState() => _LogoBrandState();
}

class _LogoBrandState extends State<_LogoBrand> {
  bool _isHovered = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  @override
  Widget build(BuildContext context) {
    // Curva con leve rebote: crece "de más" y se asienta, se siente vivo
    // en vez de un escalado lineal plano.
    const curve = Curves.easeOutBack;
    const duration = Duration(milliseconds: 320);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.04 : 1.0,
          duration: duration,
          curve: curve,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo con leve giro al hacer hover (sin glow/degradado).
              SizedBox(
                width: 54,
                height: 54,
                child: AnimatedRotation(
                  turns: _isHovered ? -0.02 : 0.0,
                  duration: duration,
                  curve: curve,
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
              ),
              const SizedBox(width: 10),
              // El AnimatedScale del Row ya agranda el texto junto al logo
              // de forma fluida (como un solo bloque), sin saltos de tamaño.
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
      ),
    );
  }
}

/// Link de navegación con icono, hover y estado activo.
class _NavLink extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _NavLink({
    required this.title,
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool highlighted = widget.isActive || _isHovered;
    final Color fgColor = highlighted
        ? AppColors.primaryBlue
        : AppColors.darkNavy;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: highlighted
                  ? AppColors.primaryBlue.withOpacity(0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: fgColor),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                    color: fgColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Iniciar sesión" con icono y hover sutil.
class _HoverTextButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HoverTextButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_HoverTextButton> createState() => _HoverTextButtonState();
}

class _HoverTextButtonState extends State<_HoverTextButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? AppColors.darkNavy.withOpacity(0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: AppColors.darkNavy),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: AppColors.darkNavy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón "Crear cuenta" con glow sutil que se intensifica en hover.
class _GlowingRegisterButton extends StatefulWidget {
  final VoidCallback onTap;

  const _GlowingRegisterButton({required this.onTap});

  @override
  State<_GlowingRegisterButton> createState() => _GlowingRegisterButtonState();
}

class _GlowingRegisterButtonState extends State<_GlowingRegisterButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(
                _isHovered ? 0.38 : 0.22,
              ),
              blurRadius: _isHovered ? 20 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        transform: Matrix4.identity()..scale(_isHovered ? 1.03 : 1.0),
        transformAlignment: Alignment.center,
        child: ElevatedButton.icon(
          onPressed: widget.onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
      ),
    );
  }
}

/// Menú hamburguesa para mobile: antes los links de navegación simplemente
/// desaparecían en pantallas angostas sin ninguna forma de acceder a ellos.
class _MobileMenu extends StatelessWidget {
  final List<_NavItem> navItems;
  final String? activeLink;
  final VoidCallback onLoginPressed;
  final VoidCallback onRegisterPressed;

  const _MobileMenu({
    required this.navItems,
    required this.activeLink,
    required this.onLoginPressed,
    required this.onRegisterPressed,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Abrir menú',
      icon: const Icon(Icons.menu_rounded, color: AppColors.darkNavy),
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (callback) => callback(),
      itemBuilder: (context) => [
        for (final item in navItems)
          PopupMenuItem<VoidCallback>(
            value: item.onTap,
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: activeLink == item.title
                      ? AppColors.primaryBlue
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 12),
                Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: activeLink == item.title
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: activeLink == item.title
                        ? AppColors.primaryBlue
                        : AppColors.darkNavy,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem<VoidCallback>(enabled: false, child: Divider()),
        PopupMenuItem<VoidCallback>(
          value: onLoginPressed,
          child: const Row(
            children: [
              Icon(Icons.login_rounded, size: 18, color: AppColors.textMuted),
              SizedBox(width: 12),
              Text(
                'Iniciar sesión',
                style: TextStyle(color: AppColors.darkNavy),
              ),
            ],
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onRegisterPressed,
          child: Row(
            children: [
              const Icon(
                Icons.person_add_alt_1_rounded,
                size: 18,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 12),
              Text(
                'Crear cuenta',
                style: TextStyle(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
