/// Identidad del administrador autenticado.
class AdminDashboardIdentity {
  const AdminDashboardIdentity({required this.name, this.schoolId});

  final String name;
  final String? schoolId;
}

/// Filas obtenidas del backend, aún sin transformar en componentes visuales.
/// Las cuotas y sus saldos están limitados al colegio de la sesión.
class AdminDashboardRows {
  const AdminDashboardRows({
    required this.students,
    required this.quotas,
    required this.balances,
    required this.approvedPayments,
    required this.pendingPayments,
  });

  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> quotas;
  final List<Map<String, dynamic>> balances;
  final List<Map<String, dynamic>> approvedPayments;
  final List<Map<String, dynamic>> pendingPayments;

  /// Un saldo incompleto NO puede convertirse en "solvente" por defecto.
  void requireVerifiedBalances() {
    final ids = quotas
        .map((q) => (q['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    final byQuota = <String, Map<String, dynamic>>{
      for (final balance in balances)
        (balance['cuota_id'] ?? '').toString(): balance,
    };
    for (final id in ids) {
      final row = byQuota[id];
      if (row == null ||
          _number(row['monto_usd']) == null ||
          _number(row['saldo_usd']) == null) {
        throw StateError('No fue posible verificar todos los saldos del colegio.');
      }
    }
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

}

/// Contrato de acceso a datos del panel administrativo.
abstract class AdminDashboardRepository {
  Future<AdminDashboardIdentity> loadIdentity();
  Future<bool> schoolHasStudents(String schoolId);
  Future<AdminDashboardRows> loadRows({required String schoolId, required DateTime fromDate});
  Future<String> loadSchoolName(String schoolId);
  Future<List<Map<String, dynamic>>> loadRecentPayments(String schoolId);
}
