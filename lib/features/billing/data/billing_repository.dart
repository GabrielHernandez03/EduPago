import '../domain/billing_request.dart';
import '../domain/billing_result.dart';

/// Contrato de datos de Facturación, independiente de Supabase y de Flutter.
abstract class BillingRepository {
  Future<int> countActiveStudents({required String colegioId});

  Future<BillingResult> generateBilling(BillingRequest request);
}

/// Error de operación presentable sin depender de PostgrestException en la UI.
class BillingRepositoryException implements Exception {
  const BillingRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
