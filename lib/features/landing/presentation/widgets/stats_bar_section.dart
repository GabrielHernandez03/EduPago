import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/motion.dart';

class _Stat {
  final IconData icon;
  final String prefix;
  final double value;
  final int decimals;
  final String suffix;

  const _Stat({
    required this.icon,
    required this.value,
    required this.suffix,
    this.prefix = '',
    this.decimals = 0,
  });
}

const List<_Stat> _stats = [
  _Stat(
    icon: Icons.business_outlined,
    prefix: '+',
    value: 35,
    suffix: ' colegios',
  ),
  _Stat(
    icon: Icons.people_outline,
    prefix: '+',
    value: 2000,
    suffix: ' familias',
  ),
  _Stat(
    icon: Icons.receipt_long_outlined,
    prefix: '+',
    value: 18,
    suffix: 'k transacciones',
  ),
  _Stat(
    icon: Icons.verified_user_outlined,
    value: 99.9,
    decimals: 1,
    suffix: '% disponible',
  ),
];

class StatsBarSection extends StatelessWidget {
  const StatsBarSection({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      width: double.infinity,
      color: AppColors.darkNavy,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 60,
        vertical: 36,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 30,
            runSpacing: 24,
            children: [
              const RevealOnScroll(
                offset: Offset(-24, 0),
                child: SizedBox(
                  width: 240,
                  child: Text(
                    'UNA SOLUCIÓN\nCONFIABLE PARA TODA LA\nCOMUNIDAD EDUCATIVA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < _stats.length; i++)
                RevealOnScroll(
                  delay: Duration(milliseconds: 150 + i * 120),
                  offset: const Offset(0, 20),
                  child: _StatItem(
                    stat: _stats[i],
                    delay: Duration(milliseconds: 150 + i * 120),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final _Stat stat;
  final Duration delay;

  const _StatItem({required this.stat, required this.delay});

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered) {
        return AnimatedScale(
          scale: hovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryBlue.withOpacity(
                    hovered ? 0.28 : 0.12,
                  ),
                ),
                child: Icon(stat.icon, color: AppColors.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              CountUp(
                end: stat.value,
                decimals: stat.decimals,
                prefix: stat.prefix,
                suffix: stat.suffix,
                delay: delay,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
