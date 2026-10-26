import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

//
// Ubicación sugerida: lib/core/widgets/dashboard_shell.dart
//
// Layout único para todos los dashboards (administrador, representante, ...).
// Centraliza: barra lateral colapsable, drawer en pantallas pequeñas,
// encabezado superior, menú de cuenta, confirmación de cierre de sesión,
// breakpoints y los widgets de hover reutilizables.
//

/// Breakpoints compartidos por todas las pantallas del dashboard.
class Breakpoints {
  Breakpoints._();

  /// Por debajo: teléfono.
  static const double compact = 640;

  /// Por encima: la barra lateral es fija. Por debajo: drawer con botón menú.
  static const double desktop = 900;

  /// Por encima: la barra lateral arranca expandida (el usuario puede alternarla).
  static const double wide = 1200;

  static bool isCompact(double w) => w < compact;
  static bool isDesktop(double w) => w > desktop;

  static double pagePadding(double w) =>
      w < compact ? 16 : (w <= desktop ? 24 : 32);

  static EdgeInsets pageInsets(double w) => EdgeInsets.symmetric(
    horizontal: pagePadding(w),
    vertical: w < compact ? 16 : 24,
  );
}

/// Ítem de navegación de la barra lateral.
class DashboardNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  const DashboardNavItem(this.icon, this.activeIcon, this.title);
}

const Color _navy = Color(0xFF0F172A);
const Color _navySurface = Color(0xFF1E293B);
const Color _navActive = Color(0xFF1E3A8A);
const Color _danger = Color(0xFFDC2626);
const Duration _hoverDuration = Duration(milliseconds: 150);

class DashboardShell extends StatefulWidget {
  final List<DashboardNavItem> navItems;
  final int selectedIndex;
  final ValueChanged<int> onNavSelected;

  /// Nombre de la institución (tarjeta superior de la barra lateral).
  final String schoolName;

  /// Datos del usuario (pie de la barra lateral, encabezado y menú de cuenta).
  final String userName;
  final String userInitials;
  final String userRole;

  /// Se ejecuta SOLO después de que el usuario confirma en el diálogo.
  final VoidCallback onLogout;

  /// Texto de la caja de búsqueda del encabezado.
  final String searchHint;

  /// Widgets extra del encabezado (ej. tasa BCV, período). Se ocultan en
  /// pantallas angostas (<= 760 px) para no desbordar.
  final List<Widget> headerActions;

  /// Muestra el punto rojo sobre la campana.
  final bool hasNotifications;

  /// Acción del ítem "Soporte y seguridad". Si es null muestra un aviso.
  final VoidCallback? onSupportTap;

  /// Contenido de la página.
  final Widget body;

  const DashboardShell({
    super.key,
    required this.navItems,
    required this.selectedIndex,
    required this.onNavSelected,
    required this.schoolName,
    required this.userName,
    required this.userInitials,
    required this.userRole,
    required this.onLogout,
    required this.body,
    this.searchHint = 'Buscar...',
    this.headerActions = const [],
    this.hasNotifications = false,
    this.onSupportTap,
  });

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// null = automático según el ancho; true/false = el usuario lo alternó.
  bool? _expandedOverride;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isDesktop = Breakpoints.isDesktop(w);
    final expanded = _expandedOverride ?? (w >= Breakpoints.wide);
    final sidebarW = expanded ? 250.0 : 76.0;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: isDesktop
          ? null
          : Drawer(
              width: 280,
              backgroundColor: _navy,
              child: SafeArea(
                child: _buildSidebar(expanded: true, inDrawer: true),
              ),
            ),
      body: Stack(
        children: [
          Row(
            children: [
              if (isDesktop) _buildSidebar(expanded: expanded),
              Expanded(
                child: Column(
                  children: [
                    _buildTopHeader(w, isDesktop),
                    Expanded(child: widget.body),
                  ],
                ),
              ),
            ],
          ),
          if (isDesktop)
            Positioned(
              left: sidebarW - 12,
              top: 64,
              child: _buildCollapseButton(expanded),
            ),
        ],
      ),
    );
  }

  //
  // Cierre de sesión con confirmación
  //
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const _LogoutConfirmDialog(),
    );
    if (confirmed == true) widget.onLogout();
  }

  //
  // Botón para colapsar / expandir
  //
  Widget _buildCollapseButton(bool expanded) {
    return Tooltip(
      message: expanded ? 'Contraer menú' : 'Expandir menú',
      child: HoverBuilder(
        builder: (context, hovered) => AnimatedScale(
          scale: hovered ? 1.15 : 1.0,
          duration: _hoverDuration,
          child: InkWell(
            onTap: () => setState(() => _expandedOverride = !expanded),
            customBorder: const CircleBorder(),
            hoverColor: Colors.transparent,
            child: AnimatedContainer(
              duration: _hoverDuration,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: hovered ? AppColors.primaryBlue : _navy,
                shape: BoxShape.circle,
                border: Border.all(
                  color: hovered ? AppColors.primaryBlue : Colors.white24,
                ),
              ),
              child: Icon(
                expanded ? Icons.chevron_left : Icons.chevron_right,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  //
  // Barra lateral
  //
  Widget _buildSidebar({required bool expanded, bool inDrawer = false}) {
    return Container(
      width: inDrawer ? null : (expanded ? 250.0 : 76.0),
      color: _navy,
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 16 : 12,
        vertical: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sidebarInstitution(expanded),
          SizedBox(height: expanded ? 28 : 24),
          if (expanded) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'MENÚ PRINCIPAL',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Scroll por si la ventana es baja: el pie nunca se desborda.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < widget.navItems.length; i++)
                  _navItem(i, expanded, inDrawer),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _supportItem(expanded),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          _sidebarUser(expanded),
        ],
      ),
    );
  }

  Widget _sidebarInstitution(bool expanded) {
    final school = widget.schoolName.isEmpty
        ? 'Mi institución'
        : widget.schoolName;

    final iconBox = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.apartment,
        color: AppColors.primaryBlue,
        size: 18,
      ),
    );

    if (!expanded) {
      return Center(
        child: Tooltip(
          message: school,
          child: HoverBuilder(
            builder: (context, hovered) => AnimatedContainer(
              duration: _hoverDuration,
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: hovered ? const Color(0xFF273449) : _navySurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: hovered ? 0.18 : 0.08),
                ),
              ),
              child: Center(child: iconBox),
            ),
          ),
        ),
      );
    }

    return HoverBuilder(
      builder: (context, hovered) => AnimatedContainer(
        duration: _hoverDuration,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hovered ? const Color(0xFF273449) : _navySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: hovered ? 0.18 : 0.08),
          ),
        ),
        child: Row(
          children: [
            iconBox,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'INSTITUCIÓN',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    school,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _select(int index, bool inDrawer) {
    widget.onNavSelected(index);
    if (inDrawer) _scaffoldKey.currentState?.closeDrawer();
  }

  Widget _navItem(int index, bool expanded, bool inDrawer) {
    final item = widget.navItems[index];
    final selected = widget.selectedIndex == index;

    return HoverBuilder(
      builder: (context, hovered) {
        final bg = selected
            ? _navActive
            : (hovered
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent);
        final fg = (selected || hovered) ? Colors.white : Colors.white60;

        if (!expanded) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: Tooltip(
                message: item.title,
                child: InkWell(
                  onTap: () => _select(index, inDrawer),
                  borderRadius: BorderRadius.circular(12),
                  hoverColor: Colors.transparent,
                  child: AnimatedContainer(
                    duration: _hoverDuration,
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.primaryBlue
                            : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      selected ? item.activeIcon : item.icon,
                      color: fg,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: () => _select(index, inDrawer),
            borderRadius: BorderRadius.circular(10),
            hoverColor: Colors.transparent,
            child: AnimatedContainer(
              duration: _hoverDuration,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? item.activeIcon : item.icon,
                    color: fg,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: (selected || hovered)
                            ? Colors.white
                            : Colors.white70,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _supportItem(bool expanded) {
    void onTap() {
      if (widget.onSupportTap != null) {
        widget.onSupportTap!();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Soporte y seguridad estará disponible próximamente.',
            ),
          ),
        );
      }
    }

    return HoverBuilder(
      builder: (context, hovered) {
        final bg = hovered
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.transparent;
        final fg = hovered ? Colors.white : Colors.white60;

        if (!expanded) {
          return Center(
            child: Tooltip(
              message: 'Soporte y seguridad',
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                hoverColor: Colors.transparent,
                child: AnimatedContainer(
                  duration: _hoverDuration,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.shield_outlined, color: fg, size: 20),
                ),
              ),
            ),
          );
        }

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.transparent,
          child: AnimatedContainer(
            duration: _hoverDuration,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: fg, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Soporte y seguridad',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hovered ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sidebarUser(bool expanded) {
    final avatar = CircleAvatar(
      radius: expanded ? 16 : 20,
      backgroundColor: AppColors.primaryBlue,
      child: Text(
        widget.userInitials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (!expanded) {
      return Center(
        child: _userMenu(
          opensUpwards: true,
          child: HoverTint(
            hoverColor: Colors.white.withValues(alpha: 0.08),
            borderRadius: 24,
            padding: const EdgeInsets.all(2),
            child: avatar,
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _userMenu(
            opensUpwards: true,
            child: HoverTint(
              hoverColor: Colors.white.withValues(alpha: 0.08),
              borderRadius: 10,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.userRole,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
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
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.logout, size: 18),
          onPressed: _confirmLogout,
          tooltip: 'Cerrar sesión',
          style:
              IconButton.styleFrom(
                foregroundColor: Colors.white54,
                hoverColor: _danger.withValues(alpha: 0.18),
              ).copyWith(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.hovered)
                      ? const Color(0xFFFCA5A5)
                      : Colors.white54,
                ),
              ),
        ),
      ],
    );
  }

  //
  // Menú de cuenta (avatar). Muestra al usuario y la acción de salir;
  // la salida siempre pasa por el diálogo de confirmación.
  //
  Widget _userMenu({required Widget child, bool opensUpwards = false}) {
    // Alto aproximado del menú (cabecera + divisor + acción + relleno)
    const menuHeight = 140.0;

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: _danger.withValues(alpha: 0.06),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Cuenta',
        position: opensUpwards
            ? PopupMenuPosition.over
            : PopupMenuPosition.under,
        offset: opensUpwards
            ? const Offset(0, -menuHeight)
            : const Offset(0, 8),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        elevation: 14,
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 290),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        onSelected: (v) {
          if (v == 'logout') _confirmLogout();
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primaryBlue,
                  child: Text(
                    widget.userInitials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.userRole,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem<String>(
            value: 'logout',
            height: 52,
            padding: EdgeInsets.zero,
            child: HoverBuilder(
              builder: (context, hovered) => AnimatedContainer(
                duration: _hoverDuration,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                height: 40,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: hovered ? const Color(0xFFFEF2F2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: _danger),
                    SizedBox(width: 12),
                    Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        child: child,
      ),
    );
  }

  //
  // Encabezado superior
  //
  Widget _buildTopHeader(double w, bool isDesktop) {
    final compact = Breakpoints.isCompact(w);
    final showActions = w > 760;
    final showUserText = w > 1000;

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.darkNavy),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Menú',
            ),
          Expanded(
            child: HoverBuilder(
              cursor: SystemMouseCursors.text,
              builder: (context, hovered) => AnimatedContainer(
                duration: _hoverDuration,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: hovered
                      ? const Color(0xFFE9EEF5)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hovered
                        ? const Color(0xFFCBD5E1)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.searchHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (showActions)
            for (final a in widget.headerActions) ...[
              HoverLift(radius: 10, lift: 1, child: a),
              const SizedBox(width: 12),
            ],
          HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => Stack(
              children: [
                AnimatedContainer(
                  duration: _hoverDuration,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hovered ? const Color(0xFFF1F5F9) : Colors.white,
                    border: Border.all(
                      color: hovered
                          ? const Color(0xFF94A3B8)
                          : AppColors.cardBorder,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.notifications_none,
                    size: 18,
                    color: AppColors.darkNavy,
                  ),
                ),
                if (widget.hasNotifications)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _userMenu(
            child: HoverTint(
              borderRadius: 24,
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFDBEAFE),
                    child: Text(
                      widget.userInitials,
                      style: const TextStyle(
                        color: AppColors.primaryBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (showUserText) ...[
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            widget.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 7,
                              color: Color(0xFF059669),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Sesión activa',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//
// Diálogo de confirmación de cierre de sesión
//
class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: _danger,
                  size: 26,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '¿Cerrar sesión?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tu sesión actual se cerrará y volverás a la pantalla de inicio. ¿Seguro que quieres salir?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(false),
                      style:
                          OutlinedButton.styleFrom(
                            foregroundColor: AppColors.darkNavy,
                            side: const BorderSide(color: AppColors.cardBorder),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ).copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.hovered)
                                  ? const Color(0xFFF1F5F9)
                                  : Colors.transparent,
                            ),
                          ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style:
                          ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ).copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.hovered)
                                  ? const Color(0xFFB91C1C)
                                  : _danger,
                            ),
                          ),
                      child: const Text(
                        'Cerrar sesión',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
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

//
// Utilidades de hover reutilizables (solo reaccionan a mouse/trackpad;
// en táctil no cambian nada).
//

/// Expone si el puntero está encima para construir cualquier widget.
class HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = MouseCursor.defer,
  });

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  void _set(bool v) {
    if (_hovered != v) setState(() => _hovered = v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// Al pasar el mouse sube unos píxeles y proyecta una sombra suave. Se envuelve
/// alrededor de una tarjeta ya hecha. Con `lift: 0` solo aparece la sombra
/// (ideal para contenedores grandes).
class HoverLift extends StatelessWidget {
  final Widget child;
  final double radius;
  final double lift;

  const HoverLift({
    super.key,
    required this.child,
    this.radius = 16,
    this.lift = 2,
  });

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, hovered ? -lift : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: _navy.withValues(alpha: lift == 0 ? 0.06 : 0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: child,
      ),
    );
  }
}

/// Fondo que aparece al pasar el mouse (filas de tabla, listas, chips...).
class HoverTint extends StatelessWidget {
  final Widget child;
  final Color hoverColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  const HoverTint({
    super.key,
    required this.child,
    this.hoverColor = const Color(0xFFF1F5F9),
    this.borderRadius = 0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => AnimatedContainer(
        duration: _hoverDuration,
        padding: padding,
        decoration: BoxDecoration(
          color: hovered ? hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: child,
      ),
    );
  }
}

/// Cuadrícula responsive: [wideCols] columnas si el ancho disponible es
/// >= [wideBreak], [mediumCols] si es >= [mediumBreak] y [narrowCols] debajo.
/// Las celdas de una misma fila se estiran a la misma altura.
/// Si [hoverLift] no es null, cada celda sube al pasar el mouse.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> items;
  final int wideCols;
  final int mediumCols;
  final int narrowCols;
  final double wideBreak;
  final double mediumBreak;
  final double gap;
  final double? hoverLift;
  final double hoverRadius;

  const ResponsiveGrid({
    super.key,
    required this.items,
    this.wideCols = 4,
    this.mediumCols = 2,
    this.narrowCols = 1,
    this.wideBreak = 800,
    this.mediumBreak = 520,
    this.gap = 16,
    this.hoverLift,
    this.hoverRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= wideBreak
            ? wideCols
            : (c.maxWidth >= mediumBreak ? mediumCols : narrowCols);
        final rows = <Widget>[];

        for (var i = 0; i < items.length; i += cols) {
          final slice = items.sublist(i, math.min(i + cols, items.length));
          final cells = <Widget>[];

          for (var j = 0; j < cols; j++) {
            if (j > 0) cells.add(SizedBox(width: gap));
            Widget cell = j < slice.length ? slice[j] : const SizedBox();
            if (hoverLift != null && j < slice.length) {
              cell = HoverLift(
                radius: hoverRadius,
                lift: hoverLift!,
                child: cell,
              );
            }
            cells.add(Expanded(child: cell));
          }

          if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          );
        }

        return Column(children: rows);
      },
    );
  }
}
