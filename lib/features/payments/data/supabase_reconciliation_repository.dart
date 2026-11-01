import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/reconciliation_decision.dart';
import 'reconciliation_repository.dart';

/// Acceso a Supabase exclusivo de la conciliación administrativa.
///
/// Las comprobaciones en el cliente complementan, pero no sustituyen, RLS,
/// los permisos del administrador ni el trigger de conciliación de PostgreSQL.
class SupabaseReconciliationRepository implements ReconciliationRepository {
  SupabaseReconciliationRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _fields = '''
    id,
    colegio_id,
    representante_id,
    monto,
    moneda,
    tasa_aplicada,
    monto_usd_equivalente,
    metodo,
    referencia,
    banco_origen,
    fecha_pago,
    comprobante_path,
    estado,
    motivo_rechazo,
    creado_at,
    representantes (
      nombres,
      apellidos,
      cedula
    )
  ''';

  @override
  Future<List<Map<String, dynamic>>> loadPayments({
    required String colegioId,
    required String status,
  }) async {
    if (colegioId.trim().isEmpty) {
      throw ArgumentError.value(colegioId, 'colegioId', 'Colegio no identificado.');
    }
    if (!const {'todos', 'pendiente', 'aprobado', 'rechazado'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Filtro de pagos desconocido.');
    }
    var query = _client.from('pagos').select(_fields).eq('colegio_id', colegioId);
    if (status != 'todos') {
      query = query.eq('estado', status);
    }
    final rows = await query.order('creado_at', ascending: false);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  @override
  Future<void> approvePayment({
    required String colegioId,
    required String paymentId,
  }) => _review(
    ReconciliationDecision(
      paymentId: paymentId,
      schoolId: colegioId,
      reviewerId: _requireReviewerId(),
      action: ReconciliationAction.approve,
    ),
  );

  @override
  Future<void> rejectPayment({
    required String colegioId,
    required String paymentId,
    required String reason,
  }) => _review(
    ReconciliationDecision(
      paymentId: paymentId,
      schoolId: colegioId,
      reviewerId: _requireReviewerId(),
      action: ReconciliationAction.reject,
      reason: reason,
    ),
  );

  String _requireReviewerId() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw StateError('Debes iniciar sesión para conciliar pagos.');
    }
    return uid;
  }

  Future<void> _review(ReconciliationDecision decision) async {
    // La condición `estado = pendiente` evita repetir la decisión sobre pagos
    // ya revisados. La transacción y la aplicación a cuotas deben ser atómicas
    // dentro de la base de datos, nunca implementadas aquí.
    final updated = await _client
        .from('pagos')
        .update(decision.toUpdatePayload())
        .eq('id', decision.paymentId)
        .eq('colegio_id', decision.schoolId)
        .eq('estado', 'pendiente')
        .select('id');

    if (updated.isEmpty) {
      throw StateError(
        'No se actualizó el pago. Puede haber sido revisado por otro usuario '
        'o el acceso fue rechazado por RLS.',
      );
    }
  }

  @override
  Future<String?> resolveProofUrl(String storedPath) async {
    final original = storedPath.trim();
    if (original.isEmpty) return null;
    var path = original;
    final legacy = RegExp(
      r'/storage/v1/object/(?:public|sign|authenticated)/comprobantes/',
    ).firstMatch(original);
    if (legacy != null) {
      path = Uri.decodeComponent(original.substring(legacy.end).split('?').first);
    }
    try {
      return await _client.storage.from('comprobantes').createSignedUrl(path, 300);
    } catch (e) {
      debugPrint('No se pudo firmar el comprobante: $e');
      // Mantiene la compatibilidad con los registros antiguos que incluyen
      // una URL pública completa. Para producción es preferible migrarlos.
      return original.startsWith('http') ? original : null;
    }
  }
}
