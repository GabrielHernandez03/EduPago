import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/billing_request.dart';
import '../domain/billing_result.dart';
import 'billing_repository.dart';

/// Implementación Supabase.
///
/// El servidor valida autorización, evita duplicados
/// y procesa crédito/aplicaciones.
/// El cliente solamente solicita la operación.
class SupabaseBillingRepository implements BillingRepository {
  SupabaseBillingRepository({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;

  final SupabaseClient client;

  @override
  Future<int> countActiveStudents({required String colegioId}) async {
    final rows = await client
        .from('estudiantes')
        .select('id')
        .eq('colegio_id', colegioId)
        .eq('activo', true);

    return rows.length;
  }

  @override
  Future<BillingResult> generateBilling(BillingRequest request) async {
    try {
      // 1. Verificar autenticación.
      final currentUser = client.auth.currentUser;

      if (currentUser == null) {
        throw const BillingRepositoryException('Usuario no autenticado.');
      }

      // 2. Obtener el perfil del usuario.
      //
      // CORRECCIÓN:
      // La columna correcta es "rol", no "role".
      final profileRow = await client
          .from('perfiles')
          .select('rol, colegio_id')
          .eq('id', currentUser.id)
          .maybeSingle();

      // No permitir facturar sin perfil válido.
      if (profileRow == null) {
        throw const BillingRepositoryException(
          'No se encontró un perfil válido para el usuario.',
        );
      }

      // 3. Validar rol administrativo.
      final role = (profileRow['rol'] ?? '').toString().trim().toLowerCase();

      if (role != 'administrador' && role != 'admin') {
        throw const BillingRepositoryException(
          'Acceso denegado: Solo el administrador '
          'del colegio puede generar cuotas.',
        );
      }

      // 4. Verificar pertenencia al colegio.
      final userColegioId = (profileRow['colegio_id'] ?? '').toString();

      if (userColegioId.isEmpty || userColegioId != request.colegioId) {
        throw const BillingRepositoryException(
          'Acceso denegado: No posee permisos '
          'para administrar este colegio.',
        );
      }

      // 5. Ejecutar la generación de cuotas.
      //
      // La función RPC debe validar los permisos
      // nuevamente y evitar cuotas duplicadas.
      final response = await client.rpc(
        'generar_facturacion',
        params: request.toRpcParams(),
      );

      final result = BillingResult.fromRpcResponse(response);

      // 6. La auditoría la registra la propia función SQL
      // `generar_facturacion` dentro de la misma transacción.
      // El cliente no inserta en `auditoria` (evita duplicados y fallos RLS).

      return result;
    } on PostgrestException catch (error) {
      debugPrint(
        'Error PostgreSQL (${error.code}): '
        '${error.message}',
      );

      throw BillingRepositoryException(error.message);
    }
  }
}
