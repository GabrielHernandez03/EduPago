/// Un saldo menor o igual a esta tolerancia (USD) se considera liquidado.
/// Debe coincidir con la tolerancia usada en las funciones SQL (0.01).
const double kToleranciaSaldoUsd = 0.01;

/// Una cuota del estado de cuenta familiar (una fila de `mi_estado_cuenta()`).
class CuotaEstadoCuenta {
  final String cuotaId;
  final String estudianteId;
  final String concepto;
  final String periodo;
  final DateTime? fechaVencimiento;
  final double montoUsd;
  final double aplicadoUsd;
  final double saldoUsd;

  /// PAGADO | VENCIDO | PARCIAL | PENDIENTE (calculado en el servidor).
  final String estado;

  const CuotaEstadoCuenta({
    required this.cuotaId,
    required this.estudianteId,
    required this.concepto,
    required this.periodo,
    required this.fechaVencimiento,
    required this.montoUsd,
    required this.aplicadoUsd,
    required this.saldoUsd,
    required this.estado,
  });

  factory CuotaEstadoCuenta.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    return CuotaEstadoCuenta(
      cuotaId: m['cuota_id'].toString(),
      estudianteId: m['estudiante_id'].toString(),
      concepto: (m['concepto'] ?? '').toString(),
      periodo: (m['periodo'] ?? '').toString(),
      fechaVencimiento: DateTime.tryParse(
        (m['fecha_vencimiento'] ?? '').toString(),
      ),
      montoUsd: n(m['monto_usd']),
      aplicadoUsd: n(m['aplicado_usd']),
      saldoUsd: n(m['saldo_usd']),
      estado: (m['estado'] ?? 'PENDIENTE').toString(),
    );
  }

  bool get tienePendiente => saldoUsd > kToleranciaSaldoUsd;
}

/// Estado de cuenta consolidado de todos los hijos de un representante.
class EstadoCuenta {
  /// Todas las cuotas, de la más antigua a la más reciente.
  final List<CuotaEstadoCuenta> cuotas;

  /// Saldo a favor (pagos aprobados aún no aplicados a ninguna cuota).
  final double creditoUsd;

  /// Pagos reportados que están pendientes de revisión por el colegio.
  final double enRevisionUsd;

  const EstadoCuenta({
    required this.cuotas,
    required this.creditoUsd,
    this.enRevisionUsd = 0,
  });

  /// Cuotas con saldo, de la más antigua a la más reciente.
  /// Si se indica [estudianteId], solo las de ese estudiante.
  List<CuotaEstadoCuenta> cuotasPendientes({String? estudianteId}) => cuotas
      .where(
        (c) =>
            c.tienePendiente &&
            (estudianteId == null || c.estudianteId == estudianteId),
      )
      .toList();

  /// Deuda global de la familia en USD (redondeada a centavos).
  double get totalPendienteUsd => pendienteDe();

  /// Deuda en USD, global o de un solo estudiante.
  double pendienteDe({String? estudianteId}) {
    final total = cuotasPendientes(
      estudianteId: estudianteId,
    ).fold<double>(0, (s, c) => s + c.saldoUsd);
    return (total * 100).round() / 100;
  }

  /// Solvente únicamente cuando el saldo GLOBAL de la familia es cero.
  bool get esSolvente => totalPendienteUsd <= kToleranciaSaldoUsd;

  int get cuotasPagadas => cuotas.where((c) => !c.tienePendiente).length;
}
