import 'package:flutter/material.dart';
import 'package:carousel_slider_plus/carousel_slider_plus.dart'; // Importa el paquete
import '../../../../core/theme/app_colors.dart';

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
  // Lista de tus 3 imágenes locales (en WebP)
  final List<String> _carouselImages = [
    'assets/images/landing_img1.webp',
    'assets/images/landing_img2.webp',
    'assets/images/landing_img3.webp',
  ];

  // Controlador para rastrear la imagen actual
  int _currentSlideIndex = 0;
  final CarouselSliderController _carouselController =
      CarouselSliderController();

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isMobile = screenWidth < 900;

    // Altura mínima para que llene la pantalla inicial
    final double minHeroHeight = screenHeight - 80;

    return Container(
      constraints: BoxConstraints(
        minHeight: isMobile ? 0 : (minHeroHeight > 600 ? minHeroHeight : 600),
      ),
      color: const Color(0xFFF8FAFC),
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
              // Lado Izquierdo: Textos y Botones (Sin cambios)
              Expanded(
                flex: isMobile ? 0 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Tag Superior (Sin cambios)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
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
                    const SizedBox(height: 20),

                    // Título Principal (Sin cambios)
                    const Text(
                      'La tranquilidad\nfinanciera de tu\ncomunidad\nescolar.',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkNavy,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Subtítulo (Sin cambios)
                    const Text(
                      'Centraliza pagos, solvencias y cobranzas en una plataforma\nsegura, clara y creada para las instituciones educativas de\nVenezuela.',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Botones de CTA (Sin cambios)
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: widget.onStartPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          label: const Text(
                            'Comenzar ahora',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          icon: const Icon(Icons.arrow_forward, size: 16),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton(
                          onPressed: widget.onLoginPressed,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 18,
                            ),
                            side: const BorderSide(color: AppColors.cardBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Ya tengo una cuenta',
                            style: TextStyle(
                              color: AppColors.darkNavy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // Social Proof (Sin cambios)
                    Row(
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
                        const Column(
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
                      ],
                    ),
                  ],
                ),
              ),

              if (isMobile) const SizedBox(height: 40),

              // Lado Derecho: CARRUSEL DE IMÁGENES CON BADGES FLOTANTES
              Expanded(
                flex: isMobile ? 0 : 1,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- AQUÍ ESTÁ EL CARRUSEL ---
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
                              cacheWidth:
                                  800, // Mantén la optimización de caché
                            );
                          }).toList(),
                          options: CarouselOptions(
                            height: 420,
                            autoPlay: true, // Reproducción automática
                            autoPlayInterval: const Duration(
                              seconds: 5,
                            ), // Cada 5 segundos
                            autoPlayAnimationDuration: const Duration(
                              milliseconds: 800,
                            ), // Suavidad
                            autoPlayCurve: Curves.fastOutSlowIn,
                            viewportFraction: 1.0, // Que ocupe todo el ancho
                            enlargeCenterPage: false,
                            onPageChanged: (index, reason) {
                              setState(() {
                                _currentSlideIndex = index;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                    // Floating Badge 1: Solvente (Sin cambios)
                    Positioned(
                      top: 20,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
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

                    // Floating Badge 2: Pago verificado (Sin cambios)
                    Positioned(
                      bottom: isMobile
                          ? -30
                          : -20, // Ajuste para que no tape los indicadores en móvil
                      left: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
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
                              'Bs. 2.450',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // --- AQUÍ ESTÁN LOS INDICADORES CIRCULARES ---
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: _carouselImages.asMap().entries.map((entry) {
                          return GestureDetector(
                            onTap: () =>
                                _carouselController.animateToPage(entry.key),
                            child: Container(
                              width: 8.0,
                              height: 8.0,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : AppColors.primaryBlue)
                                        .withOpacity(
                                          _currentSlideIndex == entry.key
                                              ? 0.9
                                              : 0.4,
                                        ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
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
