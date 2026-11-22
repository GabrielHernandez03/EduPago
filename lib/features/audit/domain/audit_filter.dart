import 'audit_operation.dart';

/// Criterios de consulta (CA2). Todos son opcionales y se combinan con AND.
class AuditFilter {
  final AuditOperation? operation;
  final DateTime? from; // inclusive (día completo)
  final DateTime? to; // inclusive (día completo)
  final String user; // texto parcial del nombre

  const AuditFilter({
    this.operation,
    this.from,
    this.to,
    this.user = '',
  });

  bool get isEmpty =>
      operation == null && from == null && to == null && user.trim().isEmpty;

  AuditFilter copyWith({
    AuditOperation? operation,
    bool clearOperation = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    String? user,
  }) =>
      AuditFilter(
        operation: clearOperation ? null : (operation ?? this.operation),
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        user: user ?? this.user,
      );
}
