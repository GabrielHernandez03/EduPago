import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class AcademicCard extends StatelessWidget {
  const AcademicCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SchoolCard(child: child);
}

class AcademicSelect extends StatelessWidget {
  const AcademicSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.width = 230,
  });
  final String label;
  final String? value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value:${items.keys.join(",")}'),
      initialValue: items.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: schoolInputDecoration(label),
      dropdownColor: AppColors.surfaceWhite,
      borderRadius: BorderRadius.circular(12),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.darkNavy),
      items: items.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: enabled && items.isNotEmpty ? onChanged : null,
    ),
  );
}

class AcademicMessage extends StatelessWidget {
  const AcademicMessage(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: TextStyle(
        height: 1.5,
        color: error ? AppColors.errorRed : AppColors.textMuted,
      ),
    ),
  );
}

/// Patrón del sitio: ícono azul a la izquierda y título azul marino.
class SchoolHeading extends StatelessWidget {
  const SchoolHeading({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.primary = false,
  });
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Icon(
                  icon,
                  color: AppColors.primaryBlue,
                  size: primary ? 27 : 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.darkNavy,
                    fontSize: primary ? (compact ? 25 : 30) : 17,
                    fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
                    height: 1.22,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: primary ? 14 : 12.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class SchoolCard extends StatefulWidget {
  const SchoolCard({super.key, required this.child, this.padding, this.margin});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  @override
  State<SchoolCard> createState() => _SchoolCardState();
}

class _SchoolCardState extends State<SchoolCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding:
          widget.padding ??
          EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 22),
      margin: widget.margin,
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _hover
              ? AppColors.primaryBlue.withValues(alpha: .32)
              : AppColors.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: _hover ? .075 : .035),
            blurRadius: _hover ? 22 : 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: widget.child,
    ),
  );
}

/// Usa el ancho real del panel, incluso al plegar la barra lateral.
class SchoolFieldGrid extends StatelessWidget {
  const SchoolFieldGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final width = box.maxWidth;
      final usable = width / scale;
      final columns = usable >= 940
          ? 5
          : usable >= 650
          ? 3
          : usable >= 420
          ? 2
          : 1;
      if (children.isEmpty) return const SizedBox.shrink();
      final count = children.length < columns ? children.length : columns;
      final fieldWidth = (width - (count - 1) * 14) / count;
      return Wrap(
        spacing: 14,
        runSpacing: 18,
        children: [
          for (final child in children)
            SizedBox(width: fieldWidth, child: child),
        ],
      );
    },
  );
}

InputDecoration schoolInputDecoration(String label, {IconData? icon}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.cardBorder),
  );
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.surfaceWhite,
    labelStyle: const TextStyle(color: AppColors.textMuted),
    prefixIcon: icon == null
        ? null
        : Icon(icon, size: 20, color: AppColors.primaryBlue),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
    ),
    errorBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.errorRed),
    ),
    focusedErrorBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.errorRed, width: 1.5),
    ),
  );
}

class SchoolEmptyState extends StatelessWidget {
  const SchoolEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.school_outlined,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: SchoolCard(
      child: SchoolHeading(title: title, icon: icon, subtitle: message),
    ),
  );
}

/// Selector Estudiantes / Calificaciones: un solo riel con un indicador azul
/// que se desliza entre las dos opciones. Mantiene la API anterior
/// (`grades`, `onChanged`), por lo que no cambia ningún llamador.
class SchoolTabs extends StatelessWidget {
  const SchoolTabs({
    super.key,
    required this.grades,
    required this.onChanged,
    this.firstLabel = 'Estudiantes',
    this.secondLabel = 'Calificaciones',
    this.firstIcon = Icons.people,
    this.secondIcon = Icons.fact_check_outlined,
  });
  final bool grades;
  final ValueChanged<bool> onChanged;
  final String firstLabel, secondLabel;
  final IconData firstIcon, secondIcon;

  static const double _segmentWidth = 200;
  static const Color _track = Color(0xFFF2F6FC);
  static const Color _edge = Color(0xFFEDF1F9);

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    // Con texto grande del sistema el riel crece en vez de recortar.
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14)
        .clamp(1.0, 1.6)
        .toDouble();

    return LayoutBuilder(
      builder: (context, box) {
        const natural = _segmentWidth * 2 + 10; // 2 segmentos + padding y borde
        final width = box.maxWidth < natural ? box.maxWidth : natural;
        return Align(
          alignment: Alignment.center,
          child: Container(
            width: width,
            height: 54 * scale,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _track,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _edge),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: grades
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: .5,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(alpha: .28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Material propio: el hover/ripple se pinta encima del
                // indicador y no queda tapado por el riel.
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: Row(
                      children: [
                        Expanded(
                          child: _SchoolTab(
                            label: firstLabel,
                            icon: firstIcon,
                            selected: !grades,
                            duration: duration,
                            onTap: () => onChanged(false),
                          ),
                        ),
                        Expanded(
                          child: _SchoolTab(
                            label: secondLabel,
                            icon: secondIcon,
                            selected: grades,
                            duration: duration,
                            onTap: () => onChanged(true),
                          ),
                        ),
                      ],
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
}

class _SchoolTab extends StatelessWidget {
  const _SchoolTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.duration,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        hoverColor: selected
            ? Colors.transparent
            : AppColors.primaryBlue.withValues(alpha: .07),
        splashColor: AppColors.primaryBlue.withValues(alpha: .10),
        highlightColor: Colors.transparent,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: duration,
          builder: (context, c, _) => Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: c),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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

/// Conserva la tipografía heredada y aplica los colores existentes a los controles.
class SchoolPageTheme extends StatelessWidget {
  const SchoolPageTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: AppColors.primaryBlue,
          onPrimary: AppColors.surfaceWhite,
          secondary: AppColors.primaryBlue,
          primaryContainer: AppColors.primaryLight,
          onPrimaryContainer: AppColors.darkNavy,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: AppColors.surfaceWhite,
            minimumSize: const Size(44, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryBlue,
            minimumSize: const Size(44, 46),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            side: const BorderSide(color: AppColors.cardBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryBlue,
            minimumSize: const Size(44, 44),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Orden natural para grados, secciones y nombres, independiente de Flutter.
String _schoolText(String value) {
  var text = value.trim().toLowerCase();
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  for (final entry in accents.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text;
}

int compareSchoolText(String a, String b) {
  final left = _schoolText(a), right = _schoolText(b);
  final unknownA = left.isEmpty || left.startsWith('sin ');
  final unknownB = right.isEmpty || right.startsWith('sin ');
  if (unknownA != unknownB) return unknownA ? 1 : -1;
  final tokens = RegExp(r'\d+|\D+');
  final x = tokens.allMatches(left).map((m) => m.group(0)!).toList();
  final y = tokens.allMatches(right).map((m) => m.group(0)!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final nx = int.tryParse(x[i]), ny = int.tryParse(y[i]);
    final result = nx != null && ny != null
        ? nx.compareTo(ny)
        : x[i].compareTo(y[i]);
    if (result != 0) return result;
  }
  return x.length.compareTo(y.length);
}

int _gradeNumber(String grade) {
  final text = _schoolText(grade);
  if (text.isEmpty || text.startsWith('sin ')) return 10000;
  final digits = RegExp(r'\d+').firstMatch(text);
  if (digits != null) return int.parse(digits.group(0)!);
  const ordinals = ['primer', 'segund', 'tercer', 'cuart', 'quint', 'sext'];
  for (var i = 0; i < ordinals.length; i++) {
    if (text.contains(ordinals[i])) return i + 1;
  }
  return 9999;
}

int compareSchoolGrade(String a, String b) {
  final result = _gradeNumber(a).compareTo(_gradeNumber(b));
  return result != 0 ? result : compareSchoolText(a, b);
}

/// Los grados equivalentes (1°, 1er, Primero) comparten prioridad; luego A, B…
int compareSchoolStudent({
  required String gradeA,
  required String sectionA,
  required String nameA,
  required String idA,
  required String gradeB,
  required String sectionB,
  required String nameB,
  required String idB,
}) {
  var result = _gradeNumber(gradeA).compareTo(_gradeNumber(gradeB));
  if (result == 0 && _gradeNumber(gradeA) >= 9999) {
    result = compareSchoolText(gradeA, gradeB);
  }
  if (result == 0) result = compareSchoolText(sectionA, sectionB);
  if (result == 0) result = compareSchoolText(nameA, nameB);
  return result != 0 ? result : idA.compareTo(idB);
}
