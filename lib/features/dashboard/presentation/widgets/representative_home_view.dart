import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/dashboard_shell.dart';
import '../../data/account_status_service.dart';

//
// Ubicación sugerida:
//   lib/features/<tu_feature>/presentation/widgets/representative_home_view.dart
//
// Cuerpo de la pestaña "Mi resumen" del representante. Es un widget SIN estado
// propio: recibe todo desde RepresentativeDashboardScreen, así que no toca tu
// lógica de Supabase, BCV ni estado de cuenta.
//

// ---------------------------------------------------------------------------
// Modelo de "Últimos movimientos"
// ---------------------------------------------------------------------------
enum MovementStatus { completed, available, inReview, rejected }

class RepMovement {
  final DateTime date;
  final IconData icon;
  final String description;

  /// null => se muestra "-" (recibos, actualizaciones de perfil, etc.)
  final double? amountUsd;
  final MovementStatus status;
  final VoidCallback? onTap;

  const RepMovement({
    required this.date,
    required this.icon,
    required this.description,
    required this.status,
    this.amountUsd,
    this.onTap,
  });
}

// ---------------------------------------------------------------------------
// Constantes locales de color (acentos de los accesos rápidos del mockup)
// ---------------------------------------------------------------------------
const Color _violet = Color(0xFF7C3AED);
const Color _indigo = Color(0xFF4F46E5);

const List<String> _dias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const List<String> _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

// ---------------------------------------------------------------------------
// Formato
// ---------------------------------------------------------------------------
String _fmtNum(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final fromEnd = intPart.length - i;
    buf.write(intPart[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1 && intPart[i] != '-') buf.write('.');
  }
  return '$buf,${parts[1]}';
}

String _fmtUsd(double v) => '\$${_fmtNum(v)}';

String _fmtFecha(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtFechaLarga(DateTime d) =>
    '${_dias[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]} de ${d.year}';

String _fmtVence(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1].substring(0, 3)}. ${d.year}';

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return parts.isNotEmpty && parts[0].isNotEmpty
      ? parts[0][0].toUpperCase()
      : 'U';
}

// ---------------------------------------------------------------------------
// Vista principal
// ---------------------------------------------------------------------------
class RepresentativeHomeView extends StatelessWidget {
  final String firstName;
  final String periodLabel;
  final String schoolName;

  final List<Map<String, dynamic>> students;

  /// -1 = vista consolidada de la familia (igual que en tu pantalla actual).
  final int selectedStudentIndex;
  final ValueChanged<int> onStudentSelected;

  final EstadoCuenta? estadoCuenta;
  final bool estadoCuentaError;
  final double montoUsd;
  final double equivalenteVes;
  final String tasaBcvStr;
  final String tasaFechaLabel;

  final List<RepMovement> movements;

  final VoidCallback onReportPayment;
  final VoidCallback onRetry;
  final VoidCallback onViewStatement;
  final VoidCallback onOpenDocuments;
  final VoidCallback onSupport;
  final VoidCallback? onSecurityInfo;
  final VoidCallback? onSeeAllMovements;

  const RepresentativeHomeView({
    super.key,
    required this.firstName,
    required this.periodLabel,
    required this.students,
    required this.selectedStudentIndex,
    required this.onStudentSelected,
    required this.estadoCuenta,
    required this.estadoCuentaError,
    required this.montoUsd,
    required this.equivalenteVes,
    required this.tasaBcvStr,
    required this.tasaFechaLabel,
    required this.onReportPayment,
    required this.onRetry,
    required this.onViewStatement,
    required this.onOpenDocuments,
    required this.onSupport,
    this.schoolName = '',
    this.movements = const [],
    this.onSecurityInfo,
    this.onSeeAllMovements,
  });

  String? get _selectedId =>
      (selectedStudentIndex >= 0 && selectedStudentIndex < students.length)
      ? students[selectedStudentIndex]['id'].toString()
      : null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final wide = w >= 860;
        const gap = 16.0;

        final topRow = wide
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _studentCard()),
                    const SizedBox(width: gap),
                    Expanded(flex: 2, child: _statusCard()),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _studentCard(),
                  const SizedBox(height: gap),
                  _statusCard(),
                ],
              );

        final cols = w >= 860 ? 4 : (w >= 480 ? 2 : 1);
        final tileW = (w - gap * (cols - 1)) / cols;
        final actions = <Widget>[
          _ActionTile(
            icon: Icons.credit_card_outlined,
            color: AppColors.primaryBlue,
            title: 'Reportar pago',
            subtitle: 'Informa tu pago de forma rápida y segura',
            onTap: onReportPayment,
          ),
          _ActionTile(
            icon: Icons.receipt_long_outlined,
            color: _violet,
            title: 'Ver estado de cuenta',
            subtitle: 'Consulta tus movimientos y saldos',
            onTap: onViewStatement,
          ),
          _ActionTile(
            icon: Icons.description_outlined,
            color: AppColors.successGreen,
            title: 'Documentos',
            subtitle: 'Descarga constancias y recibos',
            onTap: onOpenDocuments,
          ),
          _ActionTile(
            icon: Icons.headset_mic_outlined,
            color: _indigo,
            title: 'Soporte',
            subtitle: 'Estamos para ayudarte',
            onTap: onSupport,
          ),
        ];

        final paymentCard = _NextPaymentCard(
          estado: estadoCuenta,
          error: estadoCuentaError,
          selectedId: _selectedId,
          consolidated: _selectedId == null,
          students: students,
          montoUsd: montoUsd,
          equivalenteVes: equivalenteVes,
          tasaBcvStr: tasaBcvStr,
          tasaFechaLabel: tasaFechaLabel,
          onReportPayment: onReportPayment,
          onRetry: onRetry,
        );

        final sideCards = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SecurityCard(onMore: onSecurityInfo),
            const SizedBox(height: gap),
            _SchoolCard(schoolName: schoolName),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Greeting(
              firstName: firstName,
              periodLabel: periodLabel,
              wide: w >= 640,
            ),
            const SizedBox(height: 20),
            topRow,
            const SizedBox(height: gap),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final a in actions) SizedBox(width: tileW, child: a),
              ],
            ),
            const SizedBox(height: gap),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: paymentCard),
                  const SizedBox(width: gap),
                  Expanded(flex: 2, child: sideCards),
                ],
              )
            else ...[
              paymentCard,
              const SizedBox(height: gap),
              sideCards,
            ],
            const SizedBox(height: gap),
            _MovementsCard(movements: movements, onSeeAll: onSeeAllMovements),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  // ---- Tarjeta del estudiante (con selector) -------------------------------
  Widget _studentCard() {
    final consolidated = selectedStudentIndex < 0;
    final hasStudents = students.isNotEmpty;

    String label = 'ESTUDIANTE';
    String name = 'Sin estudiantes vinculados';
    String sub = 'Contacta al colegio para vincular a tu representado';
    String initials = '—';

    if (hasStudents && consolidated) {
      label = 'VISTA CONSOLIDADA';
      name = 'Toda la familia';
      sub = '${students.length} estudiantes vinculados';
      initials = 'FAM';
    } else if (hasStudents && selectedStudentIndex < students.length) {
      final s = students[selectedStudentIndex];
      name = '${s['nombres'] ?? ''} ${s['apellidos'] ?? ''}'.trim();
      if (name.isEmpty) name = 'Estudiante';
      initials = _initialsOf(name);
      final grade = s['grado_seccion']?.toString() ?? '';
      final ci = s['cedula']?.toString() ?? '';
      sub = [
        if (grade.isNotEmpty) grade,
        if (ci.isNotEmpty) 'C.I. $ci',
      ].join('  •  ');
      if (sub.isEmpty) sub = 'Grado no especificado';
    }

    final canSwitch = students.length > 1;

    final content = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        border: Border.all(
          color: canSwitch ? AppColors.primaryBlue : AppColors.cardBorder,
          width: canSwitch ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.tint(AppColors.primaryBlue, 0.14),
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (canSwitch)
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted,
            ),
        ],
      ),
    );

    if (!canSwitch) return content;

    return Semantics(
      button: true,
      label: 'Cambiar de estudiante. Seleccionado: $name',
      excludeSemantics: true,
      child: PopupMenuButton<int>(
        tooltip: 'Cambiar de estudiante',
        position: PopupMenuPosition.under,
        onSelected: onStudentSelected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (_) => [
          _menuItem(-1, 'Toda la familia'),
          for (var i = 0; i < students.length; i++)
            _menuItem(
              i,
              '${students[i]['nombres'] ?? ''} ${students[i]['apellidos'] ?? ''}'
                  .trim(),
            ),
        ],
        child: content,
      ),
    );
  }

  PopupMenuItem<int> _menuItem(int value, String text) {
    final selected = value == selectedStudentIndex;
    return PopupMenuItem<int>(
      value: value,
      height: AppSizes.minTarget,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: selected
                ? const Icon(
                    Icons.check,
                    size: 18,
                    color: AppColors.primaryBlue,
                  )
                : null,
          ),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.darkNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Estatus académico / financiero -------------------------------------
  Widget _statusCard() {
    final estado = estadoCuenta;
    final bool err = estadoCuentaError || estado == null;
    final bool ok = !err && estado!.esSolvente;

    final Color state = err
        ? AppColors.errorRed
        : (ok ? AppColors.successGreen : AppColors.warningAmber);

    final String title = err
        ? 'NO DISPONIBLE'
        : (ok ? 'SOLVENTE' : 'PENDIENTE');
    final String detail = err
        ? 'No pudimos verificar tu saldo. Toca para reintentar.'
        : (ok
              ? (estado!.creditoUsd > kToleranciaSaldoUsd
                    ? 'Saldo a favor: ${_fmtUsd(estado.creditoUsd)}'
                    : 'Sin deudas pendientes')
              : 'Saldo familiar: ${_fmtUsd(estado!.totalPendienteUsd)}');
    final IconData icon = err
        ? Icons.cloud_off_rounded
        : (ok ? Icons.check_rounded : Icons.priority_high_rounded);

    return Semantics(
      button: true,
      liveRegion: true,
      label:
          'Estatus familiar: ${err ? 'no disponible' : (ok ? 'solvente' : 'pendiente de pago')}. $detail',
      excludeSemantics: true,
      child: _tapCard(
        onTap: err ? onRetry : onViewStatement,
        color: AppColors.tint(state),
        borderColor: AppColors.tint(state, 0.4),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: state, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Estatus familiar',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.darkNavy,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Utilidades de tarjeta
// ---------------------------------------------------------------------------

/// Tarjeta con ripple, borde y radio del UI Kit.
Widget _tapCard({
  required Widget child,
  VoidCallback? onTap,
  Color color = Colors.white,
  Color borderColor = AppColors.cardBorder,
  EdgeInsetsGeometry padding = const EdgeInsets.all(20),
}) {
  return Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusCard),
      side: BorderSide(color: borderColor),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class _PlainCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color borderColor;
  const _PlainCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
    this.borderColor = AppColors.cardBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? Colors.white : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

Widget _pill(String text, Color color, {bool dot = false, IconData? icon}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.tint(color),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.darkNavy,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Saludo
// ---------------------------------------------------------------------------
class _Greeting extends StatelessWidget {
  final String firstName;
  final String periodLabel;
  final bool wide;
  const _Greeting({
    required this.firstName,
    required this.periodLabel,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final hello = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.tint(AppColors.warningAmber, 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.waving_hand_rounded,
            color: AppColors.warningAmber,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¡Hola, $firstName!',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                ),
              ),
              const Text(
                'Aquí tienes el resumen de la información de tu familia.',
                style: TextStyle(fontSize: 15, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );

    final date = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          _fmtFechaLarga(DateTime.now()),
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              periodLabel,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [hello, const SizedBox(height: 10), date],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: hello),
        const SizedBox(width: 16),
        date,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Accesos rápidos
// ---------------------------------------------------------------------------
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: HoverLift(
        radius: AppSizes.radiusCard,
        lift: 2,
        child: _tapCard(
          onTap: onTap,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.tint(color, 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Próxima mensualidad
// ---------------------------------------------------------------------------
class _NextPaymentCard extends StatelessWidget {
  final EstadoCuenta? estado;
  final bool error;
  final String? selectedId;
  final bool consolidated;
  final List<Map<String, dynamic>> students;
  final double montoUsd;
  final double equivalenteVes;
  final String tasaBcvStr;
  final String tasaFechaLabel;
  final VoidCallback onReportPayment;
  final VoidCallback onRetry;

  const _NextPaymentCard({
    required this.estado,
    required this.error,
    required this.selectedId,
    required this.consolidated,
    required this.students,
    required this.montoUsd,
    required this.equivalenteVes,
    required this.tasaBcvStr,
    required this.tasaFechaLabel,
    required this.onReportPayment,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final bool noData = error || e == null;
    final List<CuotaEstadoCuenta> pend = e == null
        ? <CuotaEstadoCuenta>[]
        : e.cuotasPendientes(estudianteId: selectedId);
    final CuotaEstadoCuenta? next = pend.isEmpty ? null : pend.first;

    late final String title;
    late final String subtitle;
    late final String chipText;
    late final Color chipColor;

    if (noData) {
      title = 'Saldo no disponible';
      subtitle = 'No pudimos consultar tu estado de cuenta';
      chipText = 'Sin datos';
      chipColor = AppColors.textMuted;
    } else if (next == null) {
      title = 'Estás al día';
      subtitle = 'No tienes cuotas pendientes';
      chipText = 'Al día';
      chipColor = AppColors.successGreen;
    } else {
      final nombre = next.periodo.isNotEmpty ? next.periodo : next.concepto;
      title = next.estado == 'VENCIDO'
          ? 'Cuota vencida'
          : 'Próxima mensualidad';
      subtitle =
          '$nombre  •  Vence el ${_fmtVence(next.fechaVencimiento)}${pend.length > 1 ? '  •  +${pend.length - 1} más' : ''}';
      switch (next.estado) {
        case 'VENCIDO':
          chipText = 'Vencida';
          chipColor = AppColors.errorRed;
        case 'PARCIAL':
          chipText = 'Pago parcial';
          chipColor = AppColors.warningAmber;
        default:
          chipText = 'Por pagar';
          chipColor = AppColors.warningAmber;
      }
    }

    return _PlainCard(
      padding: EdgeInsets.zero,
      borderColor: AppColors.tint(AppColors.primaryBlue, 0.25),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primaryLight, Colors.white],
        stops: [0.0, 0.55],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 540;

          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.event_note_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _pill(chipText, chipColor),
            ],
          );

          final amounts = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                consolidated ? 'Total pendiente (familia)' : 'Total pendiente',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      noData ? '—' : _fmtUsd(montoUsd),
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'USD',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  text: 'Equivalente en bolívares: ',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                  children: [
                    TextSpan(
                      text: noData ? '—' : 'Bs. ${_fmtNum(equivalenteVes)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final bool showPay = !noData && montoUsd > kToleranciaSaldoUsd;
          final buttons = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (noData)
                ElevatedButton.icon(
                  onPressed: onRetry,
                  style: _primaryStyle,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reintentar', style: _btnText),
                )
              else if (showPay)
                ElevatedButton(
                  onPressed: onReportPayment,
                  style: _primaryStyle,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Reportar pago', style: _btnText),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              if (noData || showPay) const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: noData ? null : () => _showDetail(context, pend),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.darkNavy,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.cardBorder),
                  minimumSize: const Size.fromHeight(AppSizes.control),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusControl),
                  ),
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Ver detalle', style: _btnText),
              ),
            ],
          );

          final rate = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      size: 18,
                      color: AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tasa BCV oficial',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkNavy,
                            ),
                          ),
                          Text(
                            tasaFechaLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '1 USD = Bs. $tasaBcvStr',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Tooltip(
                      message:
                          'Tasa oficial del BCV vigente al momento de la consulta.',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          return Padding(
            padding: EdgeInsets.all(compact ? 18 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 20),
                if (compact) ...[
                  amounts,
                  const SizedBox(height: 18),
                  buttons,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: amounts),
                      const SizedBox(width: 24),
                      SizedBox(width: 250, child: buttons),
                    ],
                  ),
                const SizedBox(height: 18),
                rate,
              ],
            ),
          );
        },
      ),
    );
  }

  static const TextStyle _btnText = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  static final ButtonStyle _primaryStyle = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primaryBlue,
    foregroundColor: Colors.white,
    elevation: 0,
    minimumSize: const Size.fromHeight(AppSizes.control),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusControl),
    ),
  );

  void _showDetail(BuildContext context, List<CuotaEstadoCuenta> pend) {
    final nombres = <String, String>{
      for (final s in students)
        s['id'].toString():
            (s['nombres']?.toString().split(' ').first ?? 'Estudiante'),
    };

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        ),
        title: const Text(
          'Detalle de cuotas pendientes',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.darkNavy,
          ),
        ),
        content: SizedBox(
          width: 460,
          child: pend.isEmpty
              ? const Text(
                  'No hay cuotas pendientes.',
                  style: TextStyle(color: AppColors.textMuted),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: pend.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.cardBorder),
                  itemBuilder: (_, i) {
                    final q = pend[i];
                    final accent = switch (q.estado) {
                      'VENCIDO' => AppColors.errorRed,
                      'PARCIAL' => AppColors.warningAmber,
                      _ => AppColors.primaryBlue,
                    };
                    final titulo = q.periodo.isNotEmpty
                        ? q.periodo
                        : q.concepto;
                    final sub = [
                      if (consolidated && nombres[q.estudianteId] != null)
                        nombres[q.estudianteId]!,
                      'Vence ${_fmtFecha(q.fechaVencimiento)}',
                    ].join('  •  ');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titulo,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.darkNavy,
                                  ),
                                ),
                                Text(
                                  sub,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _fmtUsd(q.saldoUsd),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.darkNavy,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _pill(q.estado, accent),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjetas laterales
// ---------------------------------------------------------------------------
class _SecurityCard extends StatelessWidget {
  final VoidCallback? onMore;
  const _SecurityCard({this.onMore});

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      padding: const EdgeInsets.all(24),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.primaryLight, Colors.white],
      ),
      borderColor: AppColors.tint(AppColors.primaryBlue, 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.tint(AppColors.primaryBlue, 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: AppColors.primaryBlue,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tu información está protegida',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.darkNavy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Usamos medidas de seguridad para proteger tus datos y tu información financiera.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          if (onMore != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onMore,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryDark,
                minimumSize: const Size(AppSizes.minTarget, AppSizes.minTarget),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: const Text(
                'Más información',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SchoolCard extends StatelessWidget {
  final String schoolName;
  const _SchoolCard({required this.schoolName});

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.tint(AppColors.primaryBlue, 0.06),
          AppColors.tint(AppColors.primaryBlue, 0.14),
        ],
      ),
      borderColor: AppColors.tint(AppColors.primaryBlue, 0.25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.school_outlined,
              color: AppColors.primaryBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schoolName.isEmpty
                      ? 'Tu colegio, siempre contigo'
                      : schoolName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkNavy,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Consulta, paga y mantén al día toda la información académica y financiera de tu familia.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.darkNavy,
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

// ---------------------------------------------------------------------------
// Últimos movimientos
// ---------------------------------------------------------------------------
class _MovementsCard extends StatelessWidget {
  final List<RepMovement> movements;
  final VoidCallback? onSeeAll;
  const _MovementsCard({required this.movements, this.onSeeAll});

  static (String, Color) _statusInfo(MovementStatus s) => switch (s) {
    MovementStatus.completed => ('Completado', AppColors.successGreen),
    MovementStatus.available => ('Disponible', AppColors.primaryBlue),
    MovementStatus.inReview => ('En revisión', AppColors.warningAmber),
    MovementStatus.rejected => ('Rechazado', AppColors.errorRed),
  };

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final table = c.maxWidth >= 620;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Últimos movimientos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                  if (onSeeAll != null)
                    TextButton(
                      onPressed: onSeeAll,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          AppSizes.minTarget,
                          AppSizes.minTarget,
                        ),
                        foregroundColor: AppColors.primaryDark,
                      ),
                      child: const Text(
                        'Ver todos  →',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Aún no hay movimientos para mostrar.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              else ...[
                if (table) _tableHeader(),
                for (var i = 0; i < movements.length; i++) ...[
                  const Divider(height: 1, color: AppColors.cardBorder),
                  table ? _tableRow(movements[i]) : _compactRow(movements[i]),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  static const TextStyle _head = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  Widget _tableHeader() => const Padding(
    padding: EdgeInsets.only(bottom: 8, left: 4, right: 4),
    child: Row(
      children: [
        Expanded(flex: 2, child: Text('Fecha', style: _head)),
        Expanded(flex: 4, child: Text('Descripción', style: _head)),
        Expanded(flex: 2, child: Text('Monto', style: _head)),
        Expanded(flex: 3, child: Text('Estado', style: _head)),
        SizedBox(width: 24),
      ],
    ),
  );

  Widget _tableRow(RepMovement m) {
    final (label, color) = _statusInfo(m.status);
    return InkWell(
      onTap: m.onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.minTarget + 8),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                _fmtFecha(m.date),
                style: const TextStyle(fontSize: 13, color: AppColors.darkNavy),
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Icon(m.icon, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      m.description,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                m.amountUsd == null ? '-' : '${_fmtUsd(m.amountUsd!)} USD',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkNavy,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _pill(label, color, dot: true),
              ),
            ),
            SizedBox(
              width: 24,
              child: m.onTap == null
                  ? null
                  : const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactRow(RepMovement m) {
    final (label, color) = _statusInfo(m.status);
    return InkWell(
      onTap: m.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                shape: BoxShape.circle,
              ),
              child: Icon(m.icon, size: 18, color: AppColors.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _fmtFecha(m.date),
                      if (m.amountUsd != null) '${_fmtUsd(m.amountUsd!)} USD',
                    ].join('  •  '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _pill(label, color, dot: true),
          ],
        ),
      ),
    );
  }
}
