import '../domain/reported_payment.dart';

/// Acceso a los movimientos del representante autenticado.
abstract class PaymentRepository {
  Future<List<ReportedPayment>> loadPayments({
    required String representativeId,
    String? focusPaymentId,
  });

  void startListening({
    required String representativeId,
    required void Function() onChanged,
  });

  void stopListening();
}
