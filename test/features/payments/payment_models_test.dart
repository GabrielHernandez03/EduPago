// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/payments/domain/account_status.dart';
import '../../../lib/features/payments/domain/reported_payment.dart';

void main() {
  test('saldo familiar suma únicamente cuotas realmente pendientes', () {
    final account = EstadoCuenta(
      cuotas: [
        CuotaEstadoCuenta(cuotaId: 'a', estudianteId: 'e1', concepto: 'Mensualidad', periodo: 'oct', fechaVencimiento: null, montoUsd: 100, aplicadoUsd: 40, saldoUsd: 60, estado: 'PARCIAL'),
        CuotaEstadoCuenta(cuotaId: 'b', estudianteId: 'e2', concepto: 'Mensualidad', periodo: 'oct', fechaVencimiento: null, montoUsd: 50, aplicadoUsd: 50, saldoUsd: 0, estado: 'PAGADO'),
      ],
      creditoUsd: 0,
      enRevisionUsd: 10,
    );
    expect(account.totalPendienteUsd, 60);
    expect(account.pendienteDe(estudianteId: 'e2'), 0);
    expect(account.esSolvente, isFalse);
    expect(account.enRevisionUsd, 10);
  });

  test('pagos pendientes no son pagos aprobados', () {
    final payment = ReportedPayment({'id': 'p', 'estado': 'pendiente', 'monto': 25, 'moneda': 'USD', 'monto_usd_equivalente': 25});
    expect(payment.normalizedStatus, 'pendiente');
    expect(payment.statusLabel, 'En espera');
    expect(payment.amountUsdEquivalent, 25);
  });

  test('solvencia respeta tolerancia de un centavo', () {
    final account = EstadoCuenta(
      cuotas: [CuotaEstadoCuenta(cuotaId: 'a', estudianteId: 'e', concepto: 'X', periodo: 'oct', fechaVencimiento: null, montoUsd: 1, aplicadoUsd: 0.995, saldoUsd: 0.005, estado: 'PARCIAL')],
      creditoUsd: 0,
    );
    expect(account.esSolvente, isTrue);
  });
}
