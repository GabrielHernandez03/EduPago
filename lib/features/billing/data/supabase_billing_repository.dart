import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/billing_request.dart';
import '../domain/billing_result.dart';
import 'billing_repository.dart';

/// Implementación Supabase. El servidor valida autorización, evita duplicados
/// y procesa crédito/aplicaciones; el cliente solo solicita la operación.
class SupabaseBillingRepository implements BillingRepository {
  SupabaseBillingRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<int> countActiveStudents({required String colegioId}) async {
    final rows = await _client
        .from('estudiantes')
        .select('id')
        .eq('colegio_id', colegioId)
        .eq('activo', true);
    return rows.length;
  }

  @override
  Future<BillingResult> generateBilling(BillingRequest request) async {
    try {
      final response = await _client.rpc(
        'generar_facturacion',
        params: request.toRpcParams(),
      );
      return BillingResult.fromRpcResponse(response);
    } on PostgrestException catch (error) {
      throw BillingRepositoryException(error.message);
    }
  }
}
