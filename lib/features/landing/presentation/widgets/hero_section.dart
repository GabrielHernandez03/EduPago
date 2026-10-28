import 'package:flutter/material.dart';
import 'package:carousel_slider_plus/carousel_slider_plus.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';

class HeroSection extends StatefulWidget {
  final VoidCallback onStartPressed;
  final VoidCallback onLoginPressed;

  const HeroSection({
    super.key,
    required this.onStartPressed,
    required this.onLoginPressed,
  });

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection> {
  final List<String> _carouselImages = [
    'assets/images/landing_img1.webp',
    'assets/images/landing_img2.webp',
    'assets/images/landing_img3.webp',
  ];

  int _currentSlideIndex = 0;
  final CarouselSliderController _carouselController =
      CarouselSliderController();

  static const List<String> _titleLines = [
    'La tranquilidad',
    'financiera de tu',
    'comunidad',
    'escolar.',
  ];

  Duration _ms(int value) => Duration(milliseconds: value);

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isMobile = screenWidth < 900;
    final double minHeroHeight = screenHeight - 80;

    return Container(
      constraints: BoxConstraints(
        minHeight: isMobile ? 0 : (minHeroHeight > 600 ? minHeroHeight : 600),
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.fromARGB(255, 242, 244, 247), Color(0xFFF8FAFC)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Fondo: dos resplandores que derivan lentamente
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: Stack(
                  children: [
                    Align(
                      alignment: const Alignment(1.0, -0.9),
                      child: DriftingGlow(
                        color: AppColors.primaryBlue,
                        size: 460,
                        opacity: 0.16,
                      ),
                    ),
                    Align(
                      alignment: const Alignment(-1.1, 0.95),
                      child: DriftingGlow(
                        color: const Color(0xFF38BDF8),
                        size: 380,
                        phase: 0.45,
                        opacity: 0.14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 80,
              vertical: isMobile ? 40 : 60,
            ),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Flex(
                  direction: isMobile ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: isMobile ? 0 : 1,
                      child: _buildLeft(isMobile),
                    ),
                    if (isMobile) const SizedBox(height: 40),
                    Expanded(
                      flex: isMobile ? 0 : 1,
                      child: _buildRight(isMobile),
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

  // ───────────────────────── Lado izquierdo ─────────────────────────
  Widget _buildLeft(bool isMobile) {
    const String subtitle =
        'Centraliza pagos, solvencias y cobranzas en una plataforma\nsegura, clara y creada para las instituciones educativas de\nVenezuela.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RevealOnScroll(
          offset: const Offset(0, 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: AppColors.primaryBlue,
                ),
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
        ),
        const SizedBox(height: 20),

        // Título: cada línea entra una tras otra (el momento "estrella")
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _titleLines.length; i++)
              RevealOnScroll(
                delay: _ms(140 + i * 90),
                duration: _ms(800),
                offset: const Offset(0, 36),
                child: Text(
                  _titleLines[i],
                  style: TextStyle(
                    fontSize: isMobile ? 36 : 48,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkNavy,
                    height: 1.1,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),

        RevealOnScroll(
          delay: _ms(560),
          child: Text(
            isMobile ? subtitle.replaceAll('\n', ' ') : subtitle,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 32),

        RevealOnScroll(
          delay: _ms(680),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              AnimatedButton(
                label: 'Comenzar ahora',
                onPressed: widget.onStartPressed,
                glowColor: AppColors.primaryBlue,
              ),
              AnimatedButton(
                label: 'Ya tengo una cuenta',
                onPressed: widget.onLoginPressed,
                icon: null,
                background: AppColors.primaryBlue.withOpacity(0),
                hoverBackground: AppColors.primaryBlue.withOpacity(0.06),
                foreground: AppColors.darkNavy,
                borderColor: AppColors.cardBorder,
                hoverBorderColor: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),

        RevealOnScroll(
          delay: _ms(800),
          child: Row(
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
              const Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Más de 2.000 familias',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'gestionan sus pagos con confianza',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────── Lado derecho ─────────────────────────
  Widget _buildRight(bool isMobile) {
    return RevealOnScroll(
      delay: _ms(250),
      duration: _ms(900),
      offset: const Offset(48, 0),
      startScale: 0.96,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Container(
              height: 420,
              width: double.infinity,
              color: Colors.blueGrey.shade100,
              child: CarouselSlider(
                controller: _carouselController,
                items: _carouselImages.map((imgPath) {
                  return Image.asset(
                    imgPath,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    cacheWidth: 800,
                  );
                }).toList(),
                options: CarouselOptions(
                  height: 420,
                  autoPlay: true,
                  autoPlayInterval: const Duration(seconds: 5),
                  autoPlayAnimationDuration: const Duration(milliseconds: 800),
                  autoPlayCurve: Curves.fastOutSlowIn,
                  viewportFraction: 1.0,
                  enlargeCenterPage: false,
                  onPageChanged: (index, reason) {
                    setState(() => _currentSlideIndex = index);
                  },
                ),
              ),
            ),
          ),

          // Badge 1: Solvente (aparece tarde y luego flota)
          Positioned(
            top: 20,
            right: -10,
            child: RevealOnScroll(
              delay: _ms(1000),
              duration: _ms(600),
              offset: const Offset(0, -14),
              startScale: 0.85,
              curve: Curves.easeOutBack,
              child: Floating(
                amplitude: 6,
                period: const Duration(milliseconds: 4200),
                child: _floatingBadge(
                  child: const Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.primaryBlue,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estado académico',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          Text(
                            'Solvente',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.successGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Badge 2: Pago verificado
          Positioned(
            bottom: isMobile ? -30 : -20,
            left: -10,
            child: RevealOnScroll(
              delay: _ms(1200),
              duration: _ms(600),
              offset: const Offset(0, 14),
              startScale: 0.85,
              curve: Curves.easeOutBack,
              child: Floating(
                amplitude: 7,
                phase: 0.5,
                period: const Duration(milliseconds: 4800),
                child: _floatingBadge(
                  child: const Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: AppColors.successGreen,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pago verificado',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          Text(
                            'Mensualidad · Marzo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(width: 20),
                      Text(
                        'Bs. 30.000',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Indicadores: el activo se estira como "píldora"
          Positioned(
            bottom: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _carouselImages.asMap().entries.map((entry) {
                final bool active = _currentSlideIndex == entry.key;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _carouselController.animateToPage(entry.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      width: active ? 22.0 : 8.0,
                      height: 8.0,
                      margin: const EdgeInsets.symmetric(horizontal: 4.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color:
                            (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : AppColors.primaryBlue)
                                .withOpacity(active ? 0.9 : 0.4),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingBadge({required Widget child}) {
    return Container(
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
      child: child,
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
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
