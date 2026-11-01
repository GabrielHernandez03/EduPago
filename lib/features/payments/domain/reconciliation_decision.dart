/// Decisión administrativa sobre un pago pendiente.
///
/// La validación de permisos y la conciliación financiera son responsabilidad
/// del servidor (RLS, restricciones y triggers). Este modelo solo valida los
/// parámetros que envía el cliente.
enum ReconciliationAction { approve, reject }

class ReconciliationDecision {
  ReconciliationDecision({
    required this.paymentId,
    required this.schoolId,
    required this.reviewerId,
    required this.action,
    this.reason,
  }) {
    if (paymentId.trim().isEmpty) {
      throw ArgumentError.value(paymentId, 'paymentId', 'El pago es obligatorio.');
    }
    if (schoolId.trim().isEmpty) {
      throw ArgumentError.value(schoolId, 'schoolId', 'El colegio es obligatorio.');
    }
    if (reviewerId.trim().isEmpty) {
      throw ArgumentError.value(reviewerId, 'reviewerId', 'Inicia sesión para revisar pagos.');
    }
    if (action == ReconciliationAction.reject && (reason?.trim().isEmpty ?? true)) {
      throw ArgumentError.value(reason, 'reason', 'Indica el motivo del rechazo.');
    }
  }

  final String paymentId;
  final String schoolId;
  final String reviewerId;
  final ReconciliationAction action;
  final String? reason;

  String get resultingStatus =>
      action == ReconciliationAction.approve ? 'aprobado' : 'rechazado';

  Map<String, dynamic> toUpdatePayload({DateTime? reviewedAt}) {
    final payload = <String, dynamic>{
      'estado': resultingStatus,
      'revisado_por': reviewerId,
      'revisado_at': (reviewedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
    if (action == ReconciliationAction.reject) {
      payload['motivo_rechazo'] = reason!.trim();
    }
    return payload;
  }
}
