import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'payment_submission_repository.dart';

/// Conserva el flujo original: identifica representante, sube comprobante,
/// ejecuta la RPC transaccional y limpia archivos huérfanos si falla el reporte.
class SupabasePaymentSubmissionRepository
    implements PaymentSubmissionRepository {
  SupabasePaymentSubmissionRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<String> reportPayment(PaymentReportRequest request) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const PaymentSubmissionException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    }
    final rep = await _client
        .from('representantes')
        .select('id')
        .eq('perfil_id', user.id)
        .maybeSingle();
    if (rep == null) {
      throw const PaymentSubmissionException(
        'No encontramos tu perfil de representante. Contacta al colegio.',
      );
    }
    final repId = rep['id'].toString();
    final extension = request.fileName.split('.').last.toLowerCase();
    final safeRef = request.reference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final storagePath =
        '$repId/${DateTime.now().millisecondsSinceEpoch}_$safeRef.$extension';
    var uploaded = false;
    try {
      await _client.storage
          .from('comprobantes')
          .uploadBinary(storagePath, request.fileBytes);
      uploaded = true;
      final pagoId = await _client.rpc(
        'reportar_pago',
        params: {
          'p_metodo': request.method,
          'p_moneda': request.currency,
          'p_monto': request.amount,
          'p_tasa': request.exchangeRate,
          'p_referencia': request.reference,
          'p_fecha':
              '${request.paymentDate.year}-${request.paymentDate.month.toString().padLeft(2, '0')}-${request.paymentDate.day.toString().padLeft(2, '0')}',
          'p_comprobante_path': storagePath,
          'p_banco_origen': request.bankOrigin,
        },
      );
      return pagoId.toString();
    } catch (error) {
      if (uploaded) {
        try {
          await _client.storage.from('comprobantes').remove([storagePath]);
        } catch (cleanupError) {
          debugPrint(
            'No se pudo borrar el comprobante huérfano: $cleanupError',
          );
        }
        rethrow;
      }
      throw PaymentSubmissionException(
        error.toString(),
        proofUploadFailed: true,
      );
    }
  }
}
