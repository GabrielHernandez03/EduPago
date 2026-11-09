/// Concepto de cobro configurado por el administrador del colegio.
///
/// Todos los montos son en USD. `diaVencimiento` es el día del mes (1..28)
/// en que vencen las cuotas generadas con este concepto.
class BillingConcept {
  const BillingConcept({
    required this.id,
    required this.colegioId,
    required this.nombre,
    required this.montoUsd,
    required this.diaVencimiento,
    required this.activo,
  });

  final String id;
  final String colegioId;
  final String nombre;
  final double montoUsd;
  final int? diaVencimiento;
  final bool activo;

  factory BillingConcept.fromJson(Map<String, dynamic> json) => BillingConcept(
    id: json['id'] as String,
    colegioId: json['colegio_id'] as String,
    nombre: (json['nombre'] ?? '') as String,
    montoUsd: (json['monto_usd'] as num).toDouble(),
    diaVencimiento: (json['dia_vencimiento'] as num?)?.toInt(),
    activo: json['activo'] as bool? ?? true,
  );
}

/// Versión anterior de un concepto, con el rango en que estuvo vigente.
class BillingConceptVersion {
  const BillingConceptVersion({
    required this.nombre,
    required this.montoUsd,
    required this.diaVencimiento,
    required this.activo,
    required this.vigenteDesde,
    required this.vigenteHasta,
  });

  final String nombre;
  final double? montoUsd;
  final int? diaVencimiento;
  final bool activo;
  final DateTime? vigenteDesde;
  final DateTime vigenteHasta;

  factory BillingConceptVersion.fromJson(Map<String, dynamic> json) =>
      BillingConceptVersion(
        nombre: (json['nombre'] ?? '') as String,
        montoUsd: (json['monto_usd'] as num?)?.toDouble(),
        diaVencimiento: (json['dia_vencimiento'] as num?)?.toInt(),
        activo: json['activo'] as bool? ?? true,
        vigenteDesde: DateTime.tryParse(
          json['vigente_desde']?.toString() ?? '',
        )?.toLocal(),
        vigenteHasta: DateTime.parse(json['vigente_hasta'] as String).toLocal(),
      );
}

/// Validaciones compartidas por el formulario y las pruebas.
/// El servidor repite las reglas con CHECK constraints.
class ConceptValidators {
  const ConceptValidators._();

  static String? nombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa el nombre del concepto';
    if (v.length > 80) return 'Máximo 80 caracteres';
    return null;
  }

  /// Acepta coma o punto como separador decimal.
  static double? parseMonto(String? value) =>
      double.tryParse((value ?? '').trim().replaceAll(',', '.'));

  static String? monto(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresa el monto';
    final m = parseMonto(value);
    if (m == null || m <= 0) return 'El monto debe ser mayor a 0';
    return null;
  }

  static String? diaVencimiento(int? dia) {
    if (dia == null) return 'Selecciona el día de vencimiento';
    if (dia < 1 || dia > 28) return 'El día debe estar entre 1 y 28';
    return null;
  }
}
