import 'dart:typed_data';

/// Información suministrada por el representante; valores contables se validan
/// y calculan en la función SQL reportar_pago, no en Flutter.
class PaymentReportRequest {
  const PaymentReportRequest({
    required this.method,
    required this.currency,
    required this.amount,
    required this.exchangeRate,
    required this.reference,
    required this.paymentDate,
    required this.bankOrigin,
    required this.fileName,
    required this.fileBytes,
  });

  final String method;
  final String currency;
  final double amount;
  final double? exchangeRate;
  final String reference;
  final DateTime paymentDate;
  final String? bankOrigin;
  final String fileName;
  final Uint8List fileBytes;
}

class PaymentSubmissionException implements Exception {
  const PaymentSubmissionException(
    this.message, {
    this.proofUploadFailed = false,
  });
  final String message;
  final bool proofUploadFailed;
  @override
  String toString() => message;
}

abstract class PaymentSubmissionRepository {
  Future<String> reportPayment(PaymentReportRequest request);
}
