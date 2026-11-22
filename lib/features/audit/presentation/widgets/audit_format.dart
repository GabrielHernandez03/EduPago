import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String fmtDateTime(DateTime d) =>
    '${fmtDate(d)}  ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

String fmtTime(DateTime d) =>
    '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// Tokens visuales del módulo, alineados con las tarjetas del dashboard
/// (blanco, borde cardBorder, radio 16; controles con radio 10).
const double kAuditCardRadius = 16;
const double kAuditControlRadius = 10;
const double kAuditControlHeight = 44;

BoxDecoration auditCardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(kAuditCardRadius),
  border: Border.all(color: AppColors.cardBorder),
);

OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(kAuditControlRadius),
  borderSide: BorderSide(color: c, width: w),
);

/// Misma tipografía Lexend del resto del dashboard, aplicada de forma
/// explícita para que campos, desplegables y botones no usen la fuente por
/// defecto de Material.
TextStyle auditText({
  double size = 14,
  FontWeight? weight,
  Color color = AppColors.darkNavy,
}) => GoogleFonts.lexend(fontSize: size, fontWeight: weight, color: color);

InputDecoration auditInputDecoration({String? hint, IconData? icon}) =>
    InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: auditText(color: AppColors.textMuted),
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 18, color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: _border(AppColors.cardBorder),
      focusedBorder: _border(AppColors.primaryBlue, 1.5),
      border: _border(AppColors.cardBorder),
    );

ButtonStyle auditOutlinedButtonStyle() => OutlinedButton.styleFrom(
  minimumSize: const Size(0, kAuditControlHeight),
  foregroundColor: AppColors.darkNavy,
  side: const BorderSide(color: AppColors.cardBorder),
  backgroundColor: Colors.white,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(kAuditControlRadius),
  ),
  textStyle: auditText(weight: FontWeight.w600),
);

/// Campos técnicos que no aportan al administrador (los ids y el responsable
/// ya se ven en la fila). Siguen guardados íntegros en `auditoria`.
const auditHiddenFields = {
  'id',
  'colegio_id',
  'concepto_id',
  'representante_id',
  'estudiante_id',
  'revisado_por',
  'decidido_at',
  'comprobante_path',
  'actualizado_at',
};

const _labels = {
  'estado': 'Estado',
  'monto': 'Monto',
  'moneda': 'Moneda',
  'metodo': 'Método de pago',
  'referencia': 'Referencia',
  'fecha_pago': 'Fecha de pago',
  'banco_origen': 'Banco de origen',
  'revisado_at': 'Revisado el',
  'motivo_rechazo': 'Motivo de rechazo',
  'monto_usd_equivalente': 'Equivalente (USD)',
  'tasa_aplicada': 'Tasa aplicada',
  'concepto': 'Concepto',
  'periodo': 'Período',
  'cuotas_generadas': 'Cuotas generadas',
  'cuotas_omitidas': 'Cuotas omitidas',
  'estudiantes_activos': 'Estudiantes activos',
  'fecha_vencimiento': 'Vencimiento',
  'monto_usd': 'Monto (USD)',
  'monto_defecto_usd': 'Monto por defecto (USD)',
  'dia_vencimiento': 'Día de vencimiento',
  'nombre': 'Nombre',
  'activo': 'Activo',
};

String auditFieldLabel(String key) {
  final l = _labels[key];
  if (l != null) return l;
  final t = key.replaceAll('_', ' ').trim();
  return t.isEmpty ? key : t[0].toUpperCase() + t.substring(1);
}

final _isoDateTime = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String auditFormatValue(Object? v) {
  if (v == null) return '—';
  if (v is bool) return v ? 'Sí' : 'No';
  final s = v.toString();
  if (_isoDateTime.hasMatch(s)) {
    final d = DateTime.tryParse(s);
    if (d != null) return fmtDateTime(d.toLocal());
  }
  if (_isoDate.hasMatch(s)) {
    final d = DateTime.tryParse(s);
    if (d != null) return fmtDate(d);
  }
  if (s.isEmpty) return '—';
  // estados y valores enumerados: "aprobado" -> "Aprobado"
  if (RegExp(r'^[a-z_]+$').hasMatch(s)) {
    final t = s.replaceAll('_', ' ');
    return t[0].toUpperCase() + t.substring(1);
  }
  return s;
}
