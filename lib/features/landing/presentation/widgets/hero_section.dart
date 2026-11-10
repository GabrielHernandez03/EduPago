import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';
import 'landing_section_background.dart';

/// Portada principal de EduPago.
/// Las fotografías se reutilizan de los assets existentes del proyecto.
class HeroSection extends StatelessWidget {
  final VoidCallback onStartPressed;
  final VoidCallback onLoginPressed;

  /// Espacio superior que ocupa la barra flotante. El hero lo incluye para que
  /// sus ondas y su fondo empiecen en el borde de la pantalla, detrás del navbar.
  final double topInset;

  /// Fotografías del carrusel. El fondo se pinta con CustomPainter;
  /// no necesita imágenes ni assets adicionales.
  static const List<String> carouselAssets = <String>[
    'assets/images/landing_img1.webp',
    'assets/images/landing_img2.webp',
    'assets/images/landing_img3.webp',
  ];

  // HomeScreen usa esta lista para precargar únicamente las fotografías.
  static const List<String> imageAssets = carouselAssets;

  /// Limita la resolución de decodificación al tamaño visible del carrusel.
  /// Misma clave de caché en la precarga y en Image.asset.
  static int photoCacheWidth(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final logicalWidth = size.width < 980
        ? size.width - 40.0
        : (size.width * 0.53).clamp(360.0, 790.0);
    return (logicalWidth * ratio).round().clamp(640, 1600).toInt();
  }

  const HeroSection({
    super.key,
    required this.onStartPressed,
    required this.onLoginPressed,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < 980;
    final compact = size.width < 480;
    final horizontal = mobile ? (compact ? 20.46 : 35.34) : 59.52;
    final double targetHeight = ((size.height - 8) * 0.93)
        .clamp(613.8, 837.0)
        .toDouble();

    final copy = _HeroCopy(
      mobile: mobile,
      compact: compact,
      onStartPressed: onStartPressed,
      onLoginPressed: onLoginPressed,
    );
    final gallery = RevealOnScroll(
      delay: const Duration(milliseconds: 170),
      offset: const Offset(27.9, 0),
      child: LandingHover(
        lift: 3,
        scale: 1.005,
        // La imagen no vuelve a rasterizarse por cada frame del hover.
        child: RepaintBoundary(
          child: _HeroGallery(mobile: mobile, tiny: size.width < 460),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: mobile ? 0 : targetHeight),
      child: Stack(
        children: [
          // Fondo del diseño (imagen original), primera variante.
          const Positioned.fill(
            child: LandingBackdrop(style: LandingWaveStyle.hero),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1460.1),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  topInset + (mobile ? 37.2 : 40.92),
                  horizontal,
                  mobile ? 98.58 : 106.95,
                ),
                child: mobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          copy,
                          const SizedBox(height: 39.06),
                          gallery,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 45, child: copy),
                          const SizedBox(width: 33.48),
                          Expanded(flex: 55, child: gallery),
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

// ─────────────────────────────────────────────────────────────────────────────
// Texto principal
// ─────────────────────────────────────────────────────────────────────────────
class _HeroCopy extends StatelessWidget {
  final bool mobile;
  final bool compact;
  final VoidCallback onStartPressed;
  final VoidCallback onLoginPressed;

  const _HeroCopy({
    required this.mobile,
    required this.compact,
    required this.onStartPressed,
    required this.onLoginPressed,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final titleSize = compact
        ? 36.27
        : mobile
        ? 46.5
        : w > 1530
        ? 62.31
        : w > 1220
        ? 51.15
        : 42.78;
    final baseStyle = TextStyle(
      color: AppColors.darkNavy,
      fontSize: titleSize,
      fontWeight: FontWeight.w900,
      letterSpacing: -2.2,
      height: 1.05,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RevealOnScroll(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 13.95,
              vertical: 9.3,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE3EFFD),
              borderRadius: BorderRadius.circular(29.76),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.school_outlined,
                  color: AppColors.primaryBlue,
                  size: 18.6,
                ),
                SizedBox(width: 8.37),
                Flexible(
                  child: Text(
                    'Gestión escolar que sí avanza',
                    style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.09,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 23.25),
        RevealOnScroll(
          delay: const Duration(milliseconds: 110),
          offset: const Offset(0, 22.32),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Pagos escolares,\n'),
                TextSpan(
                  text: 'más simples y\nseguros',
                  style: baseStyle.copyWith(color: const Color(0xFF075FFF)),
                ),
              ],
            ),
            style: baseStyle,
          ),
        ),
        const SizedBox(height: 20.46),
        RevealOnScroll(
          delay: const Duration(milliseconds: 200),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 502.2),
            child: const Text(
              'Pagos, solvencias y cobranzas en un solo lugar.',
              style: TextStyle(
                fontSize: 15.81,
                color: Color(0xFF3A5689),
                height: 1.52,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 26.04),
        RevealOnScroll(
          delay: const Duration(milliseconds: 300),
          child: Wrap(
            spacing: 11.16,
            runSpacing: 11.16,
            children: [
              AnimatedButton(
                label: 'Comenzar ahora',
                onPressed: onStartPressed,
                glowColor: AppColors.primaryBlue,
                radius: 15.81,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22.32,
                  vertical: 17.67,
                ),
              ),
              AnimatedButton(
                label: 'Ya tengo una cuenta',
                icon: null,
                onPressed: onLoginPressed,
                background: Colors.white.withValues(alpha: 0.88),
                hoverBackground: const Color(0xFFE9F2FF),
                foreground: AppColors.darkNavy,
                borderColor: const Color(0xFFB1C4E7),
                hoverBorderColor: AppColors.primaryBlue,
                radius: 15.81,
                padding: const EdgeInsets.symmetric(
                  horizontal: 19.53,
                  vertical: 17.67,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 34.41),
        const RevealOnScroll(
          delay: Duration(milliseconds: 370),
          child: Wrap(
            spacing: 13.02,
            runSpacing: 14.88,
            children: [
              _Benefit(
                icon: Icons.payments_outlined,
                text: 'Gestión\nde pagos',
              ),
              _Benefit(
                icon: Icons.verified_user_outlined,
                text: 'Solvencias\ndigitales',
              ),
              _Benefit(
                icon: Icons.event_note_outlined,
                text: 'Control y\nseguimiento',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Galería: presentación de fotos propia (sin PageView ni paquetes externos)
// ─────────────────────────────────────────────────────────────────────────────
class _HeroGallery extends StatefulWidget {
  final bool mobile;
  final bool tiny;
  const _HeroGallery({required this.mobile, required this.tiny});

  @override
  State<_HeroGallery> createState() => _HeroGalleryState();
}

class _HeroGalleryState extends State<_HeroGallery> {
  static const _images = HeroSection.carouselAssets;

  Timer? _timer;
  int _current = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restartTimer();
  }

  bool _inViewport() {
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return true; // Mantener comportamiento si aún no hay layout.
    }
    final y = render.localToGlobal(Offset.zero).dy;
    return y < MediaQuery.sizeOf(context).height && y + render.size.height > 0;
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_inViewport()) return;
      setState(() => _current = (_current + 1) % _images.length);
    });
  }

  void _select(int index) {
    if (index == _current) return;
    setState(() => _current = index);
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = widget.mobile;
    final tiny = widget.tiny;
    final pictureHeight = mobile ? 279.0 : 404.55;

    return SizedBox(
      height: pictureHeight + 48.36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: pictureHeight + 8.37,
            child: Container(
              padding: const EdgeInsets.all(7.44),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(mobile ? 26.97 : 46.5),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.darkNavy.withValues(alpha: 0.14),
                    blurRadius: 32.55,
                    offset: const Offset(0, 14.88),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(mobile ? 20.46 : 39.99),
                child: RepaintBoundary(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 650),
                    child: SizedBox.expand(
                      key: ValueKey<int>(_current),
                      child: Image.asset(
                        _images[_current],
                        fit: BoxFit.cover,
                        cacheWidth: HeroSection.photoCacheWidth(context),
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFFDCEBFF),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.school_outlined,
                            color: AppColors.primaryBlue,
                            size: 66.96,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: mobile ? 2.79 : -11.16,
            top: mobile ? 9.3 : 32.55,
            child: _InfoBadge(
              compact: tiny,
              icon: Icons.school_outlined,
              title: 'Estado de cuenta',
              body: 'Solvente',
              trailing: Icons.check_circle_rounded,
            ),
          ),
          Positioned(
            left: mobile ? 3.72 : -18.6,
            bottom: mobile ? 25.11 : 27.9,
            child: _PaymentBadge(compact: tiny),
          ),
          Positioned(
            right: 16.74,
            bottom: 6.51,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _images.length; i++)
                  Semantics(
                    button: true,
                    label: 'Ver imagen ${i + 1} de ${_images.length}',
                    child: InkWell(
                      onTap: () => _select(i),
                      borderRadius: BorderRadius.circular(9.3),
                      child: AnimatedContainer(
                        margin: const EdgeInsets.symmetric(horizontal: 3.72),
                        duration: const Duration(milliseconds: 230),
                        width: _current == i ? 22.32 : 8.37,
                        height: 8.37,
                        decoration: BoxDecoration(
                          color: _current == i
                              ? AppColors.primaryBlue
                              : const Color(0xFFCBD9EF),
                          borderRadius: BorderRadius.circular(9.3),
                        ),
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
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => LandingHover(
    lift: 1.5,
    scale: 1.008,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 39.99,
          height: 39.99,
          decoration: BoxDecoration(
            color: const Color(0xFFE2EDFF),
            borderRadius: BorderRadius.circular(12.09),
          ),
          child: Icon(icon, color: AppColors.primaryBlue, size: 22.32),
        ),
        const SizedBox(width: 8.37),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11.16,
            color: AppColors.darkNavy,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}

class _InfoBadge extends StatelessWidget {
  final bool compact;
  final IconData icon;
  final String title;
  final String body;
  final IconData trailing;

  const _InfoBadge({
    required this.compact,
    required this.icon,
    required this.title,
    required this.body,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 11.16 : 17.67,
      vertical: compact ? 10.23 : 15.81,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19.53),
      boxShadow: [
        BoxShadow(
          color: AppColors.darkNavy.withValues(alpha: 0.14),
          blurRadius: 23.25,
          offset: const Offset(0, 8.37),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: compact ? 20.46 : 27.9),
        SizedBox(width: compact ? 8.37 : 13.95),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 10.23 : 12.09,
                color: AppColors.darkNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2.79),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  body,
                  style: TextStyle(
                    fontSize: compact ? 13.95 : 19.53,
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 7.44),
                Icon(
                  trailing,
                  color: const Color(0xFF03A660),
                  size: compact ? 15.81 : 19.53,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _PaymentBadge extends StatelessWidget {
  final bool compact;
  const _PaymentBadge({required this.compact});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 11.16 : 16.74,
      vertical: compact ? 10.23 : 13.95,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20.46),
      boxShadow: [
        BoxShadow(
          color: AppColors.darkNavy.withValues(alpha: 0.14),
          blurRadius: 26.04,
          offset: const Offset(0, 8.37),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.calendar_month_outlined,
          color: AppColors.primaryBlue,
          size: compact ? 21.39 : 28.83,
        ),
        SizedBox(width: compact ? 8.37 : 13.02),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Próximo pago',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 10.23 : 12.09,
              ),
            ),
            const SizedBox(height: 2.79),
            Text(
              'Mensualidad escolar',
              style: TextStyle(
                color: AppColors.darkNavy,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 11.16 : 13.95,
              ),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(width: 14.88),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.09,
              vertical: 9.3,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE5EFFD),
              borderRadius: BorderRadius.circular(20.46),
            ),
            child: const Text(
              'Ver mis pagos',
              style: TextStyle(
                color: AppColors.darkNavy,
                fontWeight: FontWeight.w800,
                fontSize: 11.16,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}