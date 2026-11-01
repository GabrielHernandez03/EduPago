/// Contrato para la conciliación administrativa.
///
/// Se mantiene separado de PaymentRepository (historial del representante)
/// porque opera con permisos y casos de uso distintos.
abstract class ReconciliationRepository {
  /// Pagos visibles del colegio según su estado.
  Future<List<Map<String, dynamic>>> loadPayments({
    required String colegioId,
    required String status,
  });

  /// El backend realiza las aplicaciones FIFO al aprobar.
  Future<void> approvePayment({
    required String colegioId,
    required String paymentId,
  });

  Future<void> rejectPayment({
    required String colegioId,
    required String paymentId,
    required String reason,
  });

  /// Enlace temporal al comprobante autorizado, si existe.
  Future<String?> resolveProofUrl(String storedPath);
}
