import 'package:supabase_flutter/supabase_flutter.dart';

class AccountStatusService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtener la suma del saldo adeudado desde la vista 'v_saldo_cuotas'
  Future<double> getPendingBalanceUsd(List<String> studentIds) async {
    if (studentIds.isEmpty) return 0.0;

    try {
      final response = await _supabase
          .from('v_saldo_cuotas')
          .select('saldo_usd')
          .filter('estudiante_id', 'in', studentIds);

      final List<dynamic> data = response as List<dynamic>;
      double totalSaldoUsd = 0.0;

      for (var row in data) {
        final num saldo = row['saldo_usd'] ?? 0;
        if (saldo > 0) {
          totalSaldoUsd += saldo.toDouble();
        }
      }

      return totalSaldoUsd;
    } catch (e) {
      return 0.0;
    }
  }
}
