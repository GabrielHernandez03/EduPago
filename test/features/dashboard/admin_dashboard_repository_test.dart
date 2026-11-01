// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/features/dashboard/data/admin_dashboard_repository.dart';

void main() {
  test('No interpreta saldos incompletos como solvencia confirmada', () {
    const rows = AdminDashboardRows(
      students: [],
      quotas: [{'id': 'cuota-a'}, {'id': 'cuota-b'}],
      balances: [{'cuota_id': 'cuota-a', 'saldo_usd': 0, 'monto_usd': 10}],
      approvedPayments: [],
      pendingPayments: [],
    );
    expect(rows.requireVerifiedBalances, throwsStateError);
  });

  test('Permite colegio sin cuotas emitidas', () {
    const rows = AdminDashboardRows(
      students: [], quotas: [], balances: [],
      approvedPayments: [], pendingPayments: [],
    );
    expect(rows.requireVerifiedBalances, returnsNormally);
  });

  test('No considera verificado un saldo sin monto', () {
    const rows = AdminDashboardRows(
      students: [], quotas: [{'id': 'cuota-a'}],
      balances: [{'cuota_id': 'cuota-a', 'saldo_usd': null}],
      approvedPayments: [], pendingPayments: [],
    );
    expect(rows.requireVerifiedBalances, throwsStateError);
  });

  test('Permite saldos verificados para todas las cuotas', () {
    const rows = AdminDashboardRows(
      students: [],
      quotas: [{'id': 'cuota-a'}],
      balances: [{'cuota_id': 'cuota-a', 'saldo_usd': 15, 'monto_usd': 20}],
      approvedPayments: [], pendingPayments: [],
    );
    expect(rows.requireVerifiedBalances, returnsNormally);
  });
}
