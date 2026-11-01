// ignore_for_file: avoid_relative_lib_imports
// Sigue el criterio de los tests ya existentes de EduPago.
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/features/payments/domain/reconciliation_decision.dart';

void main() {
  group('ReconciliationDecision', () {
    test('aprobación envía el estado y usuario revisor, sin motivo', () {
      final result = ReconciliationDecision(
        paymentId: 'pago-1',
        schoolId: 'colegio-1',
        reviewerId: 'admin-1',
        action: ReconciliationAction.approve,
      ).toUpdatePayload(reviewedAt: DateTime.utc(2026, 10, 31));
      expect(result['estado'], 'aprobado');
      expect(result['revisado_por'], 'admin-1');
      expect(result['revisado_at'], '2026-10-31T00:00:00.000Z');
      expect(result.containsKey('motivo_rechazo'), false);
    });

    test('rechazo exige motivo no vacío y elimina espacios', () {
      expect(
        () => ReconciliationDecision(
          paymentId: 'p1',
          schoolId: 'c1',
          reviewerId: 'a1',
          action: ReconciliationAction.reject,
          reason: '  ',
        ),
        throwsArgumentError,
      );
      final result = ReconciliationDecision(
        paymentId: 'p1',
        schoolId: 'c1',
        reviewerId: 'a1',
        action: ReconciliationAction.reject,
        reason: '  Referencia inválida  ',
      ).toUpdatePayload(reviewedAt: DateTime.utc(2026, 10, 31));
      expect(result['estado'], 'rechazado');
      expect(result['motivo_rechazo'], 'Referencia inválida');
    });

    test('no permite IDs vacíos', () {
      expect(
        () => ReconciliationDecision(
          paymentId: '',
          schoolId: 'c1',
          reviewerId: 'a1',
          action: ReconciliationAction.approve,
        ),
        throwsArgumentError,
      );
    });
  });
}
