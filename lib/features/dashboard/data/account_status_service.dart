import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class AccountStatusService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Estado de cuenta del representante autenticado (todos sus hijos).
  ///
  /// LANZA una excepción si no se puede consultar. Antes, un error de red o de
  /// permisos devolvía 0.0 y la pantalla mostraba "SOLVENTE", lo cual además
  /// desbloquea funciones administrativas. Quien llama debe mostrar un estado
  /// de error, nunca asumir solvencia.
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
    if (representanteId == null || representanteId.isEmpty) return 0.0;
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
