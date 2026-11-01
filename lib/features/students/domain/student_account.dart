/// Modelos del directorio escolar. No dependen de Flutter ni Supabase.
/// El saldo solo es comprobable mediante la vista SQL `v_saldo_cuotas`.
class StudentAccount {
  StudentAccount(this.data);

  final Map<String, dynamic> data;
  final List<StudentQuota> quotas = [];
  final List<Map<String, dynamic>> representatives = [];

  String get id => studentText(data, ['id']);
  String get name {
    final combined = studentText(data, ['nombre_completo', 'nombre_apellido']);
    if (combined.isNotEmpty) return combined;
    final first = studentText(data, ['nombres', 'nombre']);
    final last = studentText(data, ['apellidos', 'apellido']);
    final result = '$first $last'.trim();
    return result.isNotEmpty ? result : 'Estudiante sin nombre';
  }

  String get grade {
    final separate = studentText(data, ['grado', 'nivel_grado']);
    if (separate.isNotEmpty) return separate;
    final combined = studentText(data, ['grado_seccion']);
    if (combined.isEmpty) return 'Sin grado';
    final match = RegExp(
      r'^(.*?)\s*(?:[-–/]\s*|secci[oó]n\s+)([A-Za-z])$',
      caseSensitive: false,
    ).firstMatch(combined);
    if (match != null) {
      return match
          .group(1)!
          .trim()
          .replaceFirst(RegExp(r'[-–/]\s*$'), '')
          .trim();
    }
    final trailing = RegExp(r'^(.*\S)\s+([A-Za-z])$').firstMatch(combined);
    return trailing == null ? combined : trailing.group(1)!;
  }

  String get section {
    final separate = studentText(data, [
      'seccion',
      'sección',
      'seccion_actual',
      'letra_seccion',
    ]);
    if (separate.isNotEmpty) return separate;
    final combined = studentText(data, ['grado_seccion']);
    final match = RegExp(
      r'(?:[-–/]\s*|secci[oó]n\s+|\s+)([A-Za-z])$',
      caseSensitive: false,
    ).firstMatch(combined);
    return match == null ? 'Sin sección' : match.group(1)!.toUpperCase();
  }

  String get identification => studentText(data, [
    'cedula',
    'cedula_estudiante',
    'documento_identidad',
    'numero_documento',
    'numero_cedula',
    'nro_cedula',
    'ci',
    'codigo',
    'codigo_estudiante',
  ]);

  bool get hasNoQuota => quotas.isEmpty;
  bool get hasIncompleteBalance => quotas.any((q) => !q.hasBalance);
  double get billed =>
      quotas.fold<double>(0.0, (sum, q) => sum + (q.original ?? 0.0));
  double get outstanding => quotas.fold<double>(
    0.0,
    (sum, q) => sum + ((q.balance ?? 0.0) > 0 ? q.balance! : 0.0),
  );
  double get overdueBalance => quotas
      .where((q) => q.isOverdue)
      .fold<double>(0.0, (sum, q) => sum + (q.balance ?? 0.0));
  int get overdueCount => quotas.where((q) => q.isOverdue).length;
  int get pendingCount =>
      quotas.where((q) => q.hasBalance && (q.balance ?? 0) > 0.01).length;
  int get maxOverdueDays => quotas.fold<int>(
    0,
    (max, q) => q.overdueDays > max ? q.overdueDays : max,
  );

  String status(bool balancesAvailable) {
    if (!balancesAvailable) return 'sin_datos';
    if (hasNoQuota) return 'sin_cuotas';
    if (hasIncompleteBalance) return 'sin_datos';
    if (overdueCount > 0) return 'moroso';
    if (pendingCount > 0) return 'pendiente';
    return 'solvente';
  }
}

class StudentQuota {
  StudentQuota(this.raw, this.concept);

  final Map<String, dynamic> raw;
  final String concept;
  Map<String, dynamic>? balanceRow;
  final List<Map<String, dynamic>> applications = [];

  String get id => studentText(raw, ['id']);
  String get period => studentText(raw, ['periodo', 'mes_periodo']).isEmpty
      ? 'Sin período'
      : studentText(raw, ['periodo', 'mes_periodo']);
  DateTime? get due => DateTime.tryParse(studentText(raw, ['fecha_vencimiento']));
  bool get hasBalance =>
      balanceRow != null &&
      studentNumber(balanceRow!['saldo_usd']) != null &&
      studentNumber(balanceRow!['monto_usd']) != null;
  double? get original =>
      balanceRow == null ? null : studentNumber(balanceRow!['monto_usd']);
  double? get balance =>
      balanceRow == null ? null : studentNumber(balanceRow!['saldo_usd']);
  double? get covered => original == null || balance == null
      ? null
      : (original! - balance!).clamp(0.0, double.infinity).toDouble();
  int get overdueDays {
    if (!hasBalance || (balance ?? 0) <= 0.01 || due == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due!.year, due!.month, due!.day);
    final days = today.difference(day).inDays;
    return days > 0 ? days : 0;
  }

  bool get isOverdue => overdueDays > 0;
  String get status {
    if (!hasBalance) return 'Sin datos';
    if ((balance ?? 0) <= 0.01) return 'Pagada';
    return isOverdue ? 'Vencida' : 'Pendiente';
  }
}

String studentText(Map<String, dynamic> data, List<String> names) {
  for (final name in names) {
    final raw = data[name];
    if (raw == null) continue;
    final value = raw.toString().trim();
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

double? studentNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

