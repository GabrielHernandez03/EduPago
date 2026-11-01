/// Datos de una emisión masiva de cuotas escolares.
///
/// No determina permisos ni crea cuotas: la operación financiera permanece
/// exclusivamente en la función SQL `generar_facturacion`.
class BillingRequest {
  const BillingRequest({
    required this.colegioId,
    required this.concepto,
    required this.periodo,
    required this.montoUsd,
    required this.fechaVencimiento,
  });

  final String colegioId;
  final String concepto;
  final String periodo;
  final double montoUsd;
  final DateTime fechaVencimiento;

  /// PostgreSQL recibe DATE sin hora ni zona horaria.
  String get fechaVencimientoSql =>
      '${fechaVencimiento.year.toString().padLeft(4, '0')}-'
      '${fechaVencimiento.month.toString().padLeft(2, '0')}-'
      '${fechaVencimiento.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toRpcParams() => {
    'p_colegio': colegioId,
    'p_concepto': concepto.trim(),
    'p_periodo': periodo,
    'p_monto_usd': montoUsd,
    'p_vencimiento': fechaVencimientoSql,
  };
}
