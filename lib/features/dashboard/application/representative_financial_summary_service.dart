import 'package:flutter/foundation.dart';
import '../../../core/services/bcv_service.dart';
import '../../payments/domain/account_status.dart';
import '../../payments/data/account_status_repository.dart';
import '../../payments/data/supabase_account_status_repository.dart';

/// Resultado de la consulta financiera; la UI decide qué hijo mostrar.
class RepresentativeFinancialSnapshot {
  const RepresentativeFinancialSnapshot({
    required this.account,
    required this.rate,
    required this.rateText,
    required this.rateLabel,
  });

  final EstadoCuenta? account;
  final double rate;
  final String rateText;
  final String rateLabel;
}

/// Coordina consultas financieras fuera del widget de Dashboard.
/// No convierte errores del estado de cuenta en deuda cero confirmada.
class RepresentativeFinancialSummaryService {
  RepresentativeFinancialSummaryService({
    AccountStatusRepository? accountService,
    BcvService? bcvService,
  })  : _accountService = accountService ?? SupabaseAccountStatusRepository(),
        _bcvService = bcvService ?? BcvService();

  final AccountStatusRepository _accountService;
  final BcvService _bcvService;

  Future<RepresentativeFinancialSnapshot> load({
    required String representativeId,
    required double previousRate,
    required String previousRateText,
    required String previousRateLabel,
  }) async {
    if (representativeId.isEmpty) {
      return RepresentativeFinancialSnapshot(
        account: null,
        rate: 0,
        rateText: 'No disponible',
        rateLabel: 'Tasa BCV no disponible',
      );
    }
    final accountFuture = _accountService
        .getEstadoCuenta(representanteId: representativeId)
        .then<EstadoCuenta?>((value) => value)
        .catchError((Object error) {
          debugPrint('No se pudo verificar el estado de cuenta: $error');
          return null;
        });
    // No conservar una tasa anterior sin comprobar su vigencia.
    var rate = 0.0;
    var rateText = 'No disponible';
    var rateLabel = 'Tasa BCV no disponible';
    try {
      final bcv = await _bcvService.getLatestBcvRate();
      if (bcv.rate > 0) {
        rate = bcv.rate;
        rateText = bcv.rate.toStringAsFixed(2).replaceAll('.', ',');
        rateLabel = bcv.dateFormatted;
      }
    } catch (e) {
      debugPrint('No se pudo consultar la tasa BCV: $e');
    }
    final account = await accountFuture;
    return RepresentativeFinancialSnapshot(
      account: account,
      rate: rate,
      rateText: rateText,
      rateLabel: rateLabel,
    );
  }
}
