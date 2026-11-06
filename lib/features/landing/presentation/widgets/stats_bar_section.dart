import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';

/// Barra horizontal azul marino que separa dos secciones de la landing.
/// Usa mensajes funcionales en lugar de estadísticas no verificadas.
class StatsBarSection extends StatelessWidget {
  const StatsBarSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const LandingSeparatorBar(
      headline: 'UNA SOLUCIÓN\nCONFIABLE PARA TODA LA\nCOMUNIDAD EDUCATIVA',
      items: <LandingSeparatorItem>[
        LandingSeparatorItem(Icons.school_outlined, 'Para colegios'),
        LandingSeparatorItem(Icons.groups_2_outlined, 'Para las familias'),
        LandingSeparatorItem(Icons.receipt_long_outlined, 'Pagos y comprobantes'),
        LandingSeparatorItem(Icons.verified_user_outlined, 'Acceso por roles'),
      ],
    );
  }
}

/// Pieza reutilizable: también se muestra entre Preguntas frecuentes y el CTA.
class LandingSeparatorItem {
  final IconData icon;
  final String label;

  const LandingSeparatorItem(this.icon, this.label);
}

class LandingSeparatorBar extends StatelessWidget {
  final String headline;
  final List<LandingSeparatorItem> items;

  const LandingSeparatorBar({
    super.key,
    required this.headline,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;

    return Container(
      width: double.infinity,
      color: AppColors.darkNavy,
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 20.46 : 48.36,
        vertical: narrow ? 25.11 : 26.97,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1143.9),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final wide = bounds.maxWidth >= 1030;
              final heading = Text(
                headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.35,
                  height: 1.4,
                ),
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: 204.6, child: heading),
                    const SizedBox(width: 20.46),
                    for (final item in items) ...[
                      Expanded(child: _SeparatorTile(item: item)),
                      if (item != items.last) const SizedBox(width: 11.16),
                    ],
                  ],
                );
              }

              final oneColumn = bounds.maxWidth < 520;
              final tileWidth = oneColumn
                  ? bounds.maxWidth
                  : (bounds.maxWidth - 16) / 2;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  const SizedBox(height: 19.53),
                  Wrap(
                    spacing: 14.88,
                    runSpacing: 16.74,
                    children: [
                      for (final item in items)
                        SizedBox(
                          width: tileWidth,
                          child: _SeparatorTile(item: item),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SeparatorTile extends StatelessWidget {
  final LandingSeparatorItem item;

  const _SeparatorTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return LandingHover(
      lift: 2.5,
      scale: 1.015,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36.27,
          height: 36.27,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF1A396D),
          ),
          child: Icon(item.icon, size: 19.53, color: const Color(0xFF3986FF)),
        ),
        const SizedBox(width: 10.23),
        Flexible(
          child: Text(
            item.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.09,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ),
      ],
      ),
    );
  }
}
