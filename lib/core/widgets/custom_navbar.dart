import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Barra superior flotante que se superpone al contenido (el fondo de la
/// landing pasa por detrás). Mantiene todos los callbacks del navbar original.
///
/// - Se compacta al hacer scroll y muestra una barra de progreso de lectura.
/// - En pantallas angostas el menú se despliega como panel bajo la barra.
/// - Layout deliberadamente simple: sin blur, sin tamaños animados.
class CustomNavbar extends StatefulWidget {
  /// Alto que la página debe reservar arriba para que el contenido no quede
  /// tapado por la barra (margen superior + barra + aire).
  static const double reservedHeight = 96;

  final VoidCallback onInicioPressed;
  final VoidCallback onSolucionesPressed;
  final VoidCallback onSeguridadPressed;
  final VoidCallback onContactoPressed;
  final VoidCallback onLoginPressed;
  final VoidCallback onRegisterPressed;
  final String? activeLink;
  final bool isScrolled;
  final double scrollProgress;

  /// Opcional: solo actualiza la línea de progreso sin reconstruir el navbar.
  final ValueListenable<double>? scrollProgressListenable;

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
    this.scrollProgress = 0,
    this.scrollProgressListenable,
  });

  @override
  State<CustomNavbar> createState() => _CustomNavbarState();
}

class _NavEntry {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _NavEntry(this.label, this.icon, this.onTap);
}

class _CustomNavbarState extends State<CustomNavbar> {
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    widget.scrollProgressListenable?.addListener(_handleProgressChange);
  }

  @override
  void dispose() {
    widget.scrollProgressListenable?.removeListener(_handleProgressChange);
    super.dispose();
  }

  void _handleProgressChange() {
    // Conserva el cierre automático del menú móvil al hacer scroll.
    if (_menuOpen && mounted) setState(() => _menuOpen = false);
  }

  @override
  void didUpdateWidget(covariant CustomNavbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollProgressListenable != widget.scrollProgressListenable) {
      oldWidget.scrollProgressListenable?.removeListener(_handleProgressChange);
      widget.scrollProgressListenable?.addListener(_handleProgressChange);
    }
    // Si la persona hace scroll con el menú abierto, se cierra solo.
    if (_menuOpen && oldWidget.scrollProgress != widget.scrollProgress) {
      _menuOpen = false;
    }
  }

  void _run(VoidCallback action) {
    setState(() => _menuOpen = false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1140;
    final showIcons = width >= 1300;
    final outer = width >= 850 ? 40.0 : 14.0;
    final scrolled = widget.isScrolled;
    final menuOpen = _menuOpen && !isDesktop;

    final items = <_NavEntry>[
      _NavEntry('Inicio', Icons.home_rounded, widget.onInicioPressed),
      _NavEntry(
        'Soluciones',
        Icons.layers_outlined,
        widget.onSolucionesPressed,
      ),
      _NavEntry('Seguridad', Icons.shield_outlined, widget.onSeguridadPressed),
      _NavEntry(
        'Contacto',
        Icons.mail_outline_rounded,
        widget.onContactoPressed,
      ),
    ];

    final bar = Row(
      children: [
        _Brand(onTap: widget.onInicioPressed, compact: width < 420),
        if (isDesktop) ...[
          const SizedBox(width: 24),
          const _VDivider(),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _NavItem(
                        label: e.label,
                        icon: e.icon,
                        showIcon: showIcons,
                        selected: widget.activeLink == e.label,
                        onTap: e.onTap,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const _VDivider(),
          const SizedBox(width: 16),
          _OutlinedAction(
            label: 'Iniciar sesión',
            icon: Icons.login_rounded,
            showIcon: showIcons,
            onTap: widget.onLoginPressed,
          ),
          const SizedBox(width: 10),
          _PrimaryAction(onTap: widget.onRegisterPressed),
        ] else ...[
          const Spacer(),
          _MenuButton(
            open: menuOpen,
            onTap: () => setState(() => _menuOpen = !_menuOpen),
          ),
        ],
      ],
    );

    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: scrolled ? 62.0 : 72.0,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color(0xFFE3ECFA)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: scrolled ? 0.14 : 0.08),
            blurRadius: scrolled ? 28 : 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 26 : 16),
                child: bar,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: widget.scrollProgressListenable == null
                  ? _ProgressLine(progress: widget.scrollProgress)
                  : ValueListenableBuilder<double>(
                      valueListenable: widget.scrollProgressListenable!,
                      builder: (context, progress, _) =>
                          _ProgressLine(progress: progress),
                    ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(outer, 12, outer, 0),
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1630),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pill,
              if (menuOpen)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _MobilePanel(
                    items: items,
                    activeLink: widget.activeLink,
                    onSelect: _run,
                    onLoginPressed: widget.onLoginPressed,
                    onRegisterPressed: widget.onRegisterPressed,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: const Color(0xFFD5E2F5));
}

class _Brand extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  const _Brand({required this.onTap, required this.compact});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'EduPago, ir al inicio',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo_edupago.png',
              width: compact ? 40 : 45,
              height: 45,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.school_rounded,
                color: AppColors.primaryBlue,
                size: 36,
              ),
            ),
            const SizedBox(width: 7),
            Text.rich(
              const TextSpan(
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
              style: TextStyle(
                fontSize: compact ? 21 : 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.9,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool showIcon;
  final VoidCallback onTap;
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.showIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: _HoverSurface(
      onTap: onTap,
      hoverScale: 1, // Links estables: sin salto ni reentrada del puntero.
      builder: (hovered) {
        final color = selected || hovered
            ? AppColors.primaryBlue
            : AppColors.darkNavy;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: showIcon ? 14 : 16,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            // Solo la sección activa tiene fondo. Hover = color de texto/icono.
            color: selected ? const Color(0xFFE5F0FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon) ...[
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _OutlinedAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool showIcon;
  final bool expand;
  final VoidCallback onTap;
  const _OutlinedAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.showIcon = true,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) => _HoverSurface(
    onTap: onTap,
    hoverScale: expand ? 1 : 1.025,
    builder: (hovered) => AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        border: Border.all(
          color: hovered ? AppColors.primaryBlue : const Color(0xFFB2C7E9),
        ),
        borderRadius: BorderRadius.circular(30),
        color: hovered ? const Color(0xFFF1F7FF) : Colors.white,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showIcon) ...[
            Icon(icon, size: 19, color: AppColors.darkNavy),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(
              color: AppColors.darkNavy,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PrimaryAction extends StatelessWidget {
  final VoidCallback onTap;
  final bool expand;
  const _PrimaryAction({required this.onTap, this.expand = false});

  @override
  Widget build(BuildContext context) => _HoverSurface(
    onTap: onTap,
    hoverScale: expand ? 1 : 1.025,
    builder: (hovered) => AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: hovered ? AppColors.primaryDark : AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(
              alpha: hovered ? 0.30 : 0.16,
            ),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Crear cuenta',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          SizedBox(width: 10),
          Icon(Icons.arrow_forward_rounded, size: 19, color: Colors.white),
        ],
      ),
    ),
  );
}

class _HoverSurface extends StatefulWidget {
  final VoidCallback onTap;
  final Widget Function(bool hovered) builder;
  final double hoverScale;
  const _HoverSurface({
    required this.onTap,
    required this.builder,
    this.hoverScale = 1.025,
  });

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      // Sin overlay, splash ni highlight Material: elimina el flash gris.
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: hovered ? widget.hoverScale : 1,
        child: widget.builder(hovered),
      ),
    ),
  );
}

class _MenuButton extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;
  const _MenuButton({required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: open ? 'Cerrar menú' : 'Abrir menú',
    child: _HoverSurface(
      onTap: onTap,
      hoverScale: 1,
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: open || hovered
              ? const Color(0xFFE5F0FF)
              : const Color(0xFFF1F6FF),
        ),
        child: Icon(
          open ? Icons.close_rounded : Icons.menu_rounded,
          color: AppColors.darkNavy,
          size: 25,
        ),
      ),
    ),
  );
}

class _MobilePanel extends StatelessWidget {
  final List<_NavEntry> items;
  final String? activeLink;
  final void Function(VoidCallback action) onSelect;
  final VoidCallback onLoginPressed;
  final VoidCallback onRegisterPressed;

  const _MobilePanel({
    required this.items,
    required this.activeLink,
    required this.onSelect,
    required this.onLoginPressed,
    required this.onRegisterPressed,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFFE3ECFA)),
      boxShadow: [
        BoxShadow(
          color: AppColors.darkNavy.withValues(alpha: 0.12),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _PanelRow(
              entry: e,
              selected: activeLink == e.label,
              onTap: () => onSelect(e.onTap),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Divider(height: 1, color: Color(0xFFE3ECFA)),
        ),
        _OutlinedAction(
          label: 'Iniciar sesión',
          icon: Icons.login_rounded,
          expand: true,
          onTap: () => onSelect(onLoginPressed),
        ),
        const SizedBox(height: 8),
        _PrimaryAction(expand: true, onTap: () => onSelect(onRegisterPressed)),
      ],
    ),
  );
}

class _PanelRow extends StatelessWidget {
  final _NavEntry entry;
  final bool selected;
  final VoidCallback onTap;
  const _PanelRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: entry.label,
    child: _HoverSurface(
      onTap: onTap,
      hoverScale: 1,
      builder: (hovered) {
        final color = selected || hovered
            ? AppColors.primaryBlue
            : AppColors.darkNavy;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE5F0FF)
                : hovered
                ? const Color(0xFFF1F6FF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(entry.icon, size: 21, color: color),
              const SizedBox(width: 14),
              Text(
                entry.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// La barra se repinta sin reconstruir enlaces, logo ni botones.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: progress.clamp(0.0, 1.0).toDouble(),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryBlue, Color(0xFF61B9FF)],
          ),
        ),
      ),
    ),
  );
}
