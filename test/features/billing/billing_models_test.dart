// ignore_for_file: avoid_relative_lib_imports
// Usa los mismos imports de prueba que Calendario y Pagos.
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/billing/domain/billing_request.dart';
import '../../../lib/features/billing/domain/billing_result.dart';

void main() {
  test('La solicitud conserva los parámetros exactos de generar_facturacion', () {
    final request = BillingRequest(
      colegioId: 'colegio-1',
      concepto: ' Mensualidad escolar ',
      periodo: 'Noviembre 2026',
      montoUsd: 45,
      fechaVencimiento: DateTime(2026, 11, 5),
    );
    expect(request.toRpcParams(), {
      'p_colegio': 'colegio-1',
      'p_concepto': 'Mensualidad escolar',
      'p_periodo': 'Noviembre 2026',
      'p_monto_usd': 45.0,
      'p_vencimiento': '2026-11-05',
    });
  });

  test('El resumen interpreta la respuesta en lista de la función SQL', () {
    final result = BillingResult.fromRpcResponse([
      {'generadas': 18, 'omitidas': 2, 'activos': 20},
    ]);
    expect(result.generadas, 18);
    expect(result.omitidas, 2);
    expect(result.activos, 20);
    expect(result.sinEstudiantesActivos, false);
  });

  test('No confunde ausencia de estudiantes con éxito', () {
    final result = BillingResult.fromRpcResponse({
      'generadas': 0,
      'omitidas': 0,
      'activos': 0,
    });
    expect(result.sinEstudiantesActivos, true);
  });

  test('Una respuesta vacía de servidor se trata como error', () {
    expect(() => BillingResult.fromRpcResponse([]), throwsFormatException);
  });
}
