import 'dart:ui' show ImageFilter;
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

  /// true cuando la página ya se desplazó: la sombra del navbar se intensifica.
  final bool isScrolled;

  /// Progreso de lectura de la página (0.0 - 1.0) para la barra inferior.
  final double scrollProgress;

  const CustomNavbar({
    super.key,
    required this.onInicioPressed,
    required this.onSolucionesPressed,
    required this.onSeguridadPressed,
    required this.onContactoPressed,
    required this.onLoginPressed,
    required this.onRegisterPressed,
    this.activeLink,
    this.isScrolled = false,
    this.scrollProgress = 0.0,
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

    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isScrolled ? 0.08 : 0.03),
                blurRadius: isScrolled ? 18 : 6,
                offset: Offset(0, isScrolled ? 6 : 2),
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
        ),
        // Barra de progreso de lectura
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 3,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: scrollProgress.clamp(0.0, 1.0).toDouble(),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primaryBlue, Color(0xFF60A5FA)],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ],
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
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo con sombra suave (sin efectos de hover).
            SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 8,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Opacity(
                        opacity: 0.28,
                        child: Image.asset(
                          'assets/images/logo_edupago.png',
                          width: 48,
                          height: 48,
                          color: Colors.black,
                          fit: BoxFit.contain,
                        ),
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
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            transform: Matrix4.translationValues(0, _isHovered ? -2.5 : 0, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 16, color: fgColor),
                    const SizedBox(width: 6),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: fgColor,
                      ),
                    ),
                  ],
                ),
                // Subrayado que crece desde el centro (hover / link activo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -6,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      width: widget.isActive ? 26 : 0,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
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
    final Color fgColor = _isHovered
        ? AppColors.primaryBlue
        : AppColors.darkNavy;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          transform: Matrix4.translationValues(0, _isHovered ? -2.5 : 0, 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 16, color: fgColor),
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: fgColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              // Mismo subrayado animado que los links del menú
              Positioned(
                left: 0,
                right: 0,
                bottom: -6,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: _isHovered ? 26 : 0,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
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
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _isHovered ? -3 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isHovered
                    ? const [Color(0xFF3B82F6), Color(0xFF1D4ED8)]
                    : [AppColors.primaryBlue, AppColors.primaryBlue],
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  // Brillo que cruza el botón al pasar el mouse
                  Positioned.fill(
                    child: IgnorePointer(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: _isHovered ? 1 : 0),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeInOut,
                        builder: (context, t, _) {
                          return FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 0.35,
                            child: FractionalTranslation(
                              translation: Offset(-1 + 4 * t, 0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0),
                                      Colors.white.withOpacity(0.28),
                                      Colors.white.withOpacity(0),
                                    ],
                                  ),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Crear cuenta',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSlide(
                          offset: Offset(_isHovered ? 0.4 : 0, 0),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: const Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
