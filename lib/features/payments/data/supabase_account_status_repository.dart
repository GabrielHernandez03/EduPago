import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/account_status.dart';
import 'account_status_repository.dart';

class SupabaseAccountStatusRepository implements AccountStatusRepository {
  SupabaseAccountStatusRepository({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;
  final SupabaseClient _supabase;

  /// Estado de cuenta del representante autenticado (todos sus hijos).
  ///
  /// LANZA una excepción si no se puede consultar. Antes, un error de red o de
  /// permisos devolvía 0.0 y la pantalla mostraba "SOLVENTE", lo cual además
  /// desbloquea funciones administrativas. Quien llama debe mostrar un estado
  /// de error, nunca asumir solvencia.
  @override
  Future<EstadoCuenta> getEstadoCuenta({String? representanteId}) async {
    final results = await Future.wait([
      _supabase.rpc('mi_estado_cuenta'),
      _supabase.rpc('mi_credito_usd'),
    ]);

    final cuotas = (results[0] as List)
        .map(
          (r) => CuotaEstadoCuenta.fromMap(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
    final credito = (results[1] as num?)?.toDouble() ?? 0.0;

    return EstadoCuenta(
      cuotas: cuotas,
      creditoUsd: credito,
      enRevisionUsd: await _getEnRevisionUsd(representanteId),
    );
  }

  /// Dato informativo (evita que la familia reporte dos veces el mismo pago).
  /// Si falla no es crítico: se muestra 0.
  Future<double> _getEnRevisionUsd(String? representanteId) async {
    if (representanteId == null || representanteId.isEmpty) {
      return 0.0;
    }
    try {
      final rows = await _supabase
          .from('pagos')
          .select('monto_usd_equivalente')
          .eq('representante_id', representanteId)
          .eq('estado', 'pendiente');
      return (rows as List).fold<double>(
        0,
        (s, r) => s + ((r['monto_usd_equivalente'] as num?)?.toDouble() ?? 0),
      );
    } catch (e) {
      debugPrint('No se pudo consultar pagos en revisión: $e');
      return 0.0;
    }
  }
}
