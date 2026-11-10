import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';
import 'landing_section_background.dart';

/// Contacto centrado y, debajo, preguntas frecuentes.
/// Conserva los fondos de ondas de EduPago y no requiere nuevos assets.
class ContactSection extends StatelessWidget {
  const ContactSection({super.key});

  static const String correoContacto = 'contacto-edupago@gmail.com';

  static const List<_ContactInfo> _integrantes = [
    _ContactInfo('Gabriel Hernandez', '0424-1410949'),
    _ContactInfo('Gabriela Moreta', '0412-8214834'),
    _ContactInfo('Samuel Fernandes', '0412-3096277'),
  ];

  static const List<_FaqEntry> _preguntas = [
    _FaqEntry(
      '¿Mi colegio debe registrarme?',
      'Sí. Tu colegio debe registrarte como representante para que puedas '
          'crear tu cuenta y consultar la información de tus estudiantes.',
    ),
    _FaqEntry(
      '¿Cómo creo mi cuenta?',
      'Una vez registrado por el colegio, selecciona «Crear cuenta» y completa '
          'los datos solicitados para activar tu acceso.',
    ),
    _FaqEntry(
      '¿Dónde veo mis mensualidades y mi estado de cuenta?',
      'Ingresa a «Estado de cuenta» para consultar tus cuotas, fechas de '
          'vencimiento y saldos pendientes.',
    ),
    _FaqEntry(
      '¿Cómo puedo reportar un pago?',
      'Desde «Mis pagos», selecciona «Reportar pago», elige el método, '
          'completa los datos y adjunta el comprobante.',
    ),
    _FaqEntry(
      '¿Cómo sé si mi pago fue aprobado?',
      'Revisa «Mis pagos». Cada reporte indica su estado: en espera, '
          'aprobado o rechazado.',
    ),
  ];

  static void _copiar(BuildContext context, String valor, String descripcion) {
    Clipboard.setData(ClipboardData(text: valor));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('$descripcion copiado al portapapeles'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkNavy,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11.16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;

    // Una sola capa de fondo para Contacto + Preguntas frecuentes.
    return LandingSectionBackground(
      style: LandingWaveStyle.contact,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          mobile ? 18.6 : 44.64,
          mobile ? 53.94 : 72.54,
          mobile ? 18.6 : 44.64,
          mobile ? 74.4 : 93,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 967.2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RevealOnScroll(
                  child: Column(
                    children: [
                      Text(
                        'Contáctanos',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 33.48,
                          fontWeight: FontWeight.w900,
                          color: AppColors.darkNavy,
                          letterSpacing: -0.8,
                        ),
                      ),
                      SizedBox(height: 8.37),
                      Text(
                        'Nuestro equipo está listo para ayudarte',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14.88,
                        ),
                      ),
                      SizedBox(height: 6.51),
                      Text(
                        'Toca un dato para copiarlo',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8095B8),
                          fontStyle: FontStyle.italic,
                          fontSize: 11.16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 29.76),

                // Tres tarjetas alineadas en escritorio; 2 o 1 en pantallas
                // pequeñas. El Wrap nunca usa Expanded sin ancho definido.
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final columns = width >= 890 ? 3 : (width >= 570 ? 2 : 1);
                    const gap = 16.74;
                    final cardWidth = (width - gap * (columns - 1)) / columns;

                    return Wrap(
                      alignment: WrapAlignment.center,
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (var i = 0; i < _integrantes.length; i++)
                          SizedBox(
                            width: cardWidth,
                            child: RevealOnScroll(
                              delay: Duration(milliseconds: 100 + i * 90),
                              startScale: 0.98,
                              child: RepaintBoundary(
                                child: _ContactCard(
                                  icon: Icons.person_rounded,
                                  title: _integrantes[i].nombre,
                                  value: _integrantes[i].telefono,
                                  valueIcon: Icons.phone_outlined,
                                  onTap: () => _copiar(
                                    context,
                                    _integrantes[i].telefono,
                                    'Teléfono',
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20.46),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 372),
                  child: RevealOnScroll(
                    delay: const Duration(milliseconds: 350),
                    startScale: 0.98,
                    child: RepaintBoundary(
                      child: _ContactCard(
                        icon: Icons.mail_outline_rounded,
                        title: 'Correo general',
                        value: correoContacto,
                        valueIcon: Icons.copy_rounded,
                        isEmail: true,
                        onTap: () => _copiar(context, correoContacto, 'Correo'),
                      ),
                    ),
                  ),
                ),

                // Preguntas frecuentes: DEBAJO de las cuatro tarjetas.
                SizedBox(height: mobile ? 66.96 : 87.42),
                const RevealOnScroll(
                  child: Column(
                    children: [
                      Text(
                        'PREGUNTAS FRECUENTES',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: 11.16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      SizedBox(height: 11.16),
                      Text(
                        'Resolvemos tus dudas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.darkNavy,
                          fontSize: 29.76,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                      SizedBox(height: 7.44),
                      Text(
                        'Lo esencial antes de empezar con EduPago.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13.02,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25.11),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 762.6),
                  child: Column(
                    children: [
                      for (var i = 0; i < _preguntas.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10.23),
                          child: RevealOnScroll(
                            delay: Duration(milliseconds: (i % 4) * 65),
                            child: RepaintBoundary(
                              child: _FaqTile(entry: _preguntas[i]),
                            ),
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
    );
  }
}

class _ContactInfo {
  final String nombre;
  final String telefono;

  const _ContactInfo(this.nombre, this.telefono);
}

/// Hover consistente con las tarjetas de Soluciones: borde azul,
/// elevación pequeña, sombra suave e icono destacado.
/// Es una tarjeta clicable: el toque conserva la acción de copiar el dato.
class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final IconData valueIcon;
  final VoidCallback onTap;
  final bool isEmail;

  const _ContactCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.valueIcon,
    required this.onTap,
    this.isEmail = false,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 230);

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          hovered && !reduceMotion ? -3 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17.67),
          border: Border.all(
            color: hovered ? const Color(0xFF8DBAFF) : const Color(0xFFDDE6F3),
            width: hovered ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkNavy.withValues(
                alpha: hovered ? 0.10 : 0.025,
              ),
              blurRadius: hovered ? 26 : 12,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(17.67),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: AppColors.primaryBlue.withValues(alpha: 0.025),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 181.35),
              padding: const EdgeInsets.symmetric(
                horizontal: 16.74,
                vertical: 22.32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    width: 59.52,
                    height: 59.52,
                    decoration: BoxDecoration(
                      color: hovered
                          ? AppColors.primaryBlue
                          : const Color(0xFFECF4FF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: hovered ? Colors.white : AppColors.primaryBlue,
                      size: 26.97,
                    ),
                  ),
                  const SizedBox(height: 15.81),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isEmail ? AppColors.textMuted : AppColors.darkNavy,
                      fontWeight: isEmail ? FontWeight.w600 : FontWeight.w800,
                      fontSize: isEmail ? 12.09 : 14.88,
                    ),
                  ),
                  const SizedBox(height: 6.51),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isEmail) ...[
                        Icon(
                          valueIcon,
                          size: 13.02,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4.65),
                      ],
                      Flexible(
                        child: Text(
                          value,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isEmail
                                ? FontWeight.w800
                                : FontWeight.w500,
                            fontSize: isEmail ? 13.02 : 12.09,
                            color: isEmail
                                ? AppColors.darkNavy
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6.51),
                      Icon(
                        Icons.copy_rounded,
                        size: 13.95,
                        color: hovered
                            ? AppColors.primaryBlue
                            : AppColors.textMuted,
                      ),
                    ],
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

class _FaqEntry {
  final String pregunta;
  final String respuesta;
  const _FaqEntry(this.pregunta, this.respuesta);
}

/// Las preguntas frecuentes reciben el mismo borde al pasar el cursor,
/// sin perder su comportamiento desplegable ni modificar su altura en reposo.
class _FaqTile extends StatelessWidget {
  final _FaqEntry entry;
  const _FaqTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          hovered && !reduceMotion ? -2 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13.95),
          border: Border.all(
            color: hovered ? const Color(0xFF8DBAFF) : const Color(0xFFE1E9F5),
            width: hovered ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkNavy.withValues(alpha: hovered ? 0.08 : 0),
              blurRadius: hovered ? 18 : 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13.95),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 18.6,
                vertical: 2,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18.6, 0, 18.6, 18.6),
              iconColor: AppColors.primaryBlue,
              collapsedIconColor: AppColors.primaryBlue,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                entry.pregunta,
                style: const TextStyle(
                  color: AppColors.darkNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.02,
                ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    entry.respuesta,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.56,
                      height: 1.6,
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
