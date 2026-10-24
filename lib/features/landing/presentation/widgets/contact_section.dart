import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/widgets/motion.dart';

class _ContactPerson {
  final String nombre;
  final String telefono;
  final String avatarAsset;

  const _ContactPerson({
    required this.nombre,
    required this.telefono,
    required this.avatarAsset,
  });
}

class ContactSection extends StatelessWidget {
  const ContactSection({super.key});

  static const String correoContacto = 'contacto-edupago@gmail.com';

  static const List<_ContactPerson> _contactos = [
    _ContactPerson(
      nombre: 'Gabriel Hernandez',
      telefono: '0424-1410949',
      avatarAsset: 'assets/images/gabriel_hernandez.webp',
    ),
    _ContactPerson(
      nombre: 'Gabriela Moreta',
      telefono: '0412-8214834',
      avatarAsset: 'assets/images/gabriela_moreta.webp',
    ),
    _ContactPerson(
      nombre: 'Samuel Fernandes',
      telefono: '0412-3096277',
      avatarAsset: 'assets/images/samuel_fernandes.webp',
    ),
  ];

  static void _copyToClipboard(
    BuildContext context,
    String valor,
    String mensaje,
  ) {
    Clipboard.setData(ClipboardData(text: valor));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    const double gap = 20;
    const double minCardWidth = 190;
    const double maxCardWidth = 260;
    const int totalCards = 3;

    final double available = screenWidth - 48;
    double cardWidth = (available - gap * (totalCards - 1)) / totalCards;
    cardWidth = cardWidth.clamp(minCardWidth, maxCardWidth);

    final bool soloUnaColumna = screenWidth < (minCardWidth * 2 + gap + 48);
    if (soloUnaColumna) {
      cardWidth = available.clamp(0, maxCardWidth * 1.4);
    }

    double emailWidth = available.clamp(0, 360);

    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          const RevealOnScroll(
            child: Text(
              'Contáctanos',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const RevealOnScroll(
            delay: Duration(milliseconds: 100),
            child: Text(
              'Nuestro equipo está listo para ayudarte',
              style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(height: 6),
          const RevealOnScroll(
            delay: Duration(milliseconds: 180),
            child: Text(
              'Toca un dato para copiarlo',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
          const SizedBox(height: 34),

          Wrap(
            spacing: gap,
            runSpacing: gap,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < _contactos.length; i++)
                RevealOnScroll(
                  delay: Duration(milliseconds: 200 + i * 120),
                  startScale: 0.94,
                  child: _InfoCard(
                    width: cardWidth,
                    leadingBuilder: (hovered) => _Avatar(
                      avatarAsset: _contactos[i].avatarAsset,
                      hovered: hovered,
                    ),
                    title: _contactos[i].nombre,
                    subtitle: _contactos[i].telefono,
                    subtitleIcon: Icons.phone_outlined,
                    onTap: () => _copyToClipboard(
                      context,
                      _contactos[i].telefono,
                      'Teléfono de ${_contactos[i].nombre} copiado',
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 28),

          RevealOnScroll(
            delay: const Duration(milliseconds: 560),
            startScale: 0.94,
            child: _InfoCard(
              width: emailWidth,
              leadingBuilder: (hovered) =>
                  _IconBubble(icon: Icons.email_outlined, hovered: hovered),
              title: 'Correo general',
              subtitle: correoContacto,
              titleIsLabel: true,
              onTap: () =>
                  _copyToClipboard(context, correoContacto, 'Correo copiado'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String avatarAsset;
  final bool hovered;

  const _Avatar({required this.avatarAsset, required this.hovered});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: hovered ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: hovered ? const Color(0xFF2563EB) : Colors.transparent,
            width: 2,
          ),
        ),
        child: CircleAvatar(
          radius: 34,
          backgroundColor: const Color(0xFFEFF6FF),
          child: ClipOval(
            child: Image.asset(
              avatarAsset,
              width: 68,
              height: 68,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.person, size: 34, color: Color(0xFF2563EB)),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final bool hovered;

  const _IconBubble({required this.icon, required this.hovered});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: hovered ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 74,
        height: 74,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? const Color(0xFF2563EB) : const Color(0xFFEFF6FF),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: hovered ? Colors.white : const Color(0xFF2563EB),
          size: 28,
        ),
      ),
    );
  }
}

class _InfoCard extends StatefulWidget {
  final double width;
  final Widget Function(bool hovered) leadingBuilder;
  final String title;
  final String subtitle;
  final IconData? subtitleIcon;
  final bool titleIsLabel;
  final VoidCallback onTap;

  const _InfoCard({
    required this.width,
    required this.leadingBuilder,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleIcon,
    this.titleIsLabel = false,
  });

  @override
  State<_InfoCard> createState() => _InfoCardState();
}

class _InfoCardState extends State<_InfoCard> {
  bool _copied = false;
  Timer? _timer;

  void _handleTap() {
    widget.onTap();
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool label = widget.titleIsLabel;

    return HoverCard(
      width: widget.width,
      radius: 16,
      borderColor: const Color(0xFFE2E8F0),
      hoverBorderColor: const Color(0xFF2563EB).withOpacity(0.45),
      shadowColor: const Color(0xFF2563EB),
      restShadowOpacity: 0.04,
      hoverShadowOpacity: 0.16,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 14),
      onTap: _handleTap,
      builder: (context, hovered) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.leadingBuilder(hovered),
            const SizedBox(height: 14),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: label ? 13 : 16,
                fontWeight: label ? FontWeight.w500 : FontWeight.w600,
                color: label
                    ? const Color(0xFF64748B)
                    : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.subtitleIcon != null) ...[
                    Icon(
                      widget.subtitleIcon,
                      size: 14,
                      color: const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: label ? FontWeight.w700 : FontWeight.normal,
                      color: label
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Copiar → check verde durante unos segundos
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: _copied
                        ? const Icon(
                            Icons.check_rounded,
                            key: ValueKey('copied'),
                            size: 15,
                            color: Color(0xFF16A34A),
                          )
                        : Icon(
                            Icons.copy_rounded,
                            key: const ValueKey('copy'),
                            size: 13,
                            color: hovered
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF94A3B8),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
