import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';

class SecuritySection extends StatelessWidget {
  const SecuritySection({super.key});

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 940;
    final pad = mobile ? 21.39 : 63.24;
    final illustration = const LandingHover(
      lift: 3,
      scale: 1.006,
      child: _SecurityVisual(),
    );
    final message = const _SecurityMessage();

    return Container(
      width: double.infinity,
      color: AppColors.darkNavy,
      padding: EdgeInsets.symmetric(
        horizontal: pad,
        vertical: mobile ? 61.38 : 81.84,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1134.6),
          child: mobile
              ? Column(
                  children: [illustration, const SizedBox(height: 39.06), message],
                )
              : const Row(
                  children: [
                    Expanded(
              child: LandingHover(
                lift: 3,
                scale: 1.006,
                child: _SecurityVisual(),
              ),
            ),
                    SizedBox(width: 72.54),
                    Expanded(child: _SecurityMessage()),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SecurityVisual extends StatelessWidget {
  const _SecurityVisual();

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width < 460;
    return RevealOnScroll(
      offset: const Offset(-24.18, 0),
      child: SizedBox(
        height: small ? 269.7 : 330.15,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: small ? 218.55 : 279,
              height: small ? 218.55 : 279,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.09),
                  width: 32.55,
                ),
              ),
            ),
            Container(
              width: small ? 162.75 : 209.25,
              height: small ? 162.75 : 209.25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2473EC).withValues(alpha: 0.18),
                border: Border.all(
                  color: const Color(0xFF8EC1FF).withValues(alpha: 0.28),
                ),
              ),
            ),
            Container(
              width: small ? 98.58 : 125.55,
              height: small ? 98.58 : 125.55,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28.83),
                gradient: const LinearGradient(
                  colors: [Color(0xFF378CFF), Color(0xFF1553C7)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF328AFF).withValues(alpha: 0.33),
                    blurRadius: 37.2,
                    spreadRadius: 7.44,
                  ),
                ],
              ),
              child: Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: small ? 51.15 : 64.17,
              ),
            ),
            Positioned(
              top: small ? 21.39 : 28.83,
              left: small ? 0 : 16.74,
              child: const _SecurityChip(
                icon: Icons.lock_outline_rounded,
                label: 'Acceso protegido',
              ),
            ),
            Positioned(
              bottom: small ? 20.46 : 26.97,
              right: small ? 0 : 13.02,
              child: const _SecurityChip(
                icon: Icons.verified_user_outlined,
                label: 'Acceso por roles',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SecurityChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13.02, vertical: 10.23),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13.02),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 18.6,
          offset: const Offset(0, 6.51),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 17.67),
        const SizedBox(width: 6.51),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.darkNavy,
            fontSize: 11.16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _SecurityMessage extends StatelessWidget {
  const _SecurityMessage();

  @override
  Widget build(BuildContext context) => RevealOnScroll(
    offset: const Offset(22.32, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SEGURIDAD Y CONFIANZA',
          style: TextStyle(
            color: Color(0xFF8EC1FF),
            fontSize: 11.16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 13.95),
        Text(
          'Tu información merece estar protegida.',
          style: TextStyle(
            color: Colors.white,
            fontSize: MediaQuery.sizeOf(context).width < 600 ? 29.76 : 36.27,
            fontWeight: FontWeight.w900,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 16.74),
        const Text(
          'Cada persona ve solo lo que le corresponde.',
          style: TextStyle(
            color: Color(0xFFCFDDF3),
            fontSize: 13.95,
            height: 1.65,
          ),
        ),
        const SizedBox(height: 25.11),
        const _SecurityPoint(
          icon: Icons.password_outlined,
          title: 'Inicio de sesión seguro',
          subtitle: 'Tu información vive dentro de tu cuenta.',
        ),
        const SizedBox(height: 16.74),
        const _SecurityPoint(
          icon: Icons.manage_accounts_outlined,
          title: 'Permisos por rol',
          subtitle: 'Familias y administradores ven vistas distintas.',
        ),
        const SizedBox(height: 16.74),
        const _SecurityPoint(
          icon: Icons.history_rounded,
          title: 'Historial claro',
          subtitle: 'Cada movimiento queda registrado.',
        ),
      ],
    ),
  );
}

class _SecurityPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SecurityPoint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => LandingHover(
    lift: 2,
    scale: 1.008,
    child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(9.3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12.09),
        ),
        child: Icon(icon, color: const Color(0xFF7DB9FF), size: 20.46),
      ),
      const SizedBox(width: 13.02),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.95,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4.65),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFFCADAF3),
                fontSize: 12.09,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ],
    ),
  );
}
