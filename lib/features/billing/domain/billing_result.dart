/// Resumen de una ejecución de `generar_facturacion` devuelto por PostgreSQL.
class BillingResult {
  const BillingResult({
    required this.generadas,
    required this.omitidas,
    required this.activos,
  });

  final int generadas;
  final int omitidas;
  final int activos;

  bool get sinEstudiantesActivos => activos == 0;

  /// Acepta una fila o la lista de filas retornada por la RPC de Supabase.
  /// Si no existe un resultado, notifica el error en lugar de asumir éxito.
  factory BillingResult.fromRpcResponse(dynamic response) {
    final dynamic raw;
    if (response is List) {
      if (response.isEmpty) {
        throw const FormatException('La facturación no devolvió resultados.');
      }
      raw = response.first;
    } else {
      raw = response;
    }
    if (raw is! Map) {
      throw const FormatException('Respuesta de facturación inesperada.');
    }
    final row = Map<String, dynamic>.from(raw);
    int number(String key) => (row[key] as num?)?.toInt() ?? 0;
    return BillingResult(
      generadas: number('generadas'),
      omitidas: number('omitidas'),
      activos: number('activos'),
    );
  }
}
