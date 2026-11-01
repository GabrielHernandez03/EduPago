import '../domain/account_status.dart';

/// Contrato de lectura del estado de cuenta de la familia autenticada.
abstract class AccountStatusRepository {
  Future<EstadoCuenta> getEstadoCuenta({String? representanteId});
}
