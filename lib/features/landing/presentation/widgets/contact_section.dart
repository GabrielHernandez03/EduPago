import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

    // 3 tarjetas de contacto arriba, el correo general va aparte, debajo.
    const double gap = 20;
    const double minCardWidth = 190;
    const double maxCardWidth = 260;
    const int totalCards = 3;

    final double available =
        screenWidth - 48; // padding horizontal de la sección
    double cardWidth = (available - gap * (totalCards - 1)) / totalCards;
    cardWidth = cardWidth.clamp(minCardWidth, maxCardWidth);

    // Si ni siquiera 2 columnas caben, usamos ancho casi completo (1 por fila).
    final bool soloUnaColumna = screenWidth < (minCardWidth * 2 + gap + 48);
    if (soloUnaColumna) {
      cardWidth = available.clamp(0, maxCardWidth * 1.4);
    }

    // Ancho del correo general (independiente, más ancho).
    double emailWidth = available.clamp(0, 360);

    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          const Text(
            'Contáctanos',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Nuestro equipo está listo para ayudarte',
            style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Text(
            'Toca un dato para copiarlo',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 34),

          // Las 3 tarjetas de contacto en una sola fila
          Wrap(
            spacing: gap,
            runSpacing: gap,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _contactos
                .map(
                  (persona) => _InfoCard(
                    width: cardWidth,
                    leading: _Avatar(avatarAsset: persona.avatarAsset),
                    title: persona.nombre,
                    subtitle: persona.telefono,
                    subtitleIcon: Icons.phone_outlined,
                    onTap: () => _copyToClipboard(
                      context,
                      persona.telefono,
                      'Teléfono de ${persona.nombre} copiado',
                    ),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 28),

          // Correo general, debajo y centrado
          _InfoCard(
            width: emailWidth,
            leading: const _IconBubble(icon: Icons.email_outlined),
            title: 'Correo general',
            subtitle: correoContacto,
            titleIsLabel: true,
            onTap: () =>
                _copyToClipboard(context, correoContacto, 'Correo copiado'),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String avatarAsset;

  const _Avatar({required this.avatarAsset});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
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
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;

  const _IconBubble({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: const BoxDecoration(
        color: Color(0xFFEFF6FF),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: const Color(0xFF2563EB), size: 28),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final double width;
  final Widget leading;
  final String title;
  final String subtitle;
  final IconData? subtitleIcon;
  final bool titleIsLabel;
  final VoidCallback onTap;

  const _InfoCard({
    required this.width,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleIcon,
    this.titleIsLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: titleIsLabel ? 13 : 16,
                    fontWeight: titleIsLabel
                        ? FontWeight.w500
                        : FontWeight.w600,
                    color: titleIsLabel
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
                      if (subtitleIcon != null) ...[
                        Icon(
                          subtitleIcon,
                          size: 14,
                          color: const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleIsLabel ? 14 : 14,
                          fontWeight: titleIsLabel
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: titleIsLabel
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
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
