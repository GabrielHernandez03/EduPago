import '../domain/audit_entry.dart';
import '../domain/audit_filter.dart';

/// Contrato de solo lectura. Intencionalmente NO hay insert/update/delete
/// (CA3): los eventos los escribe la base de datos, no la app.
abstract class AuditRepository {
  Future<List<AuditEntry>> fetch({
    required String schoolId,
    AuditFilter filter = const AuditFilter(),
    int offset = 0,
    int limit = 25,
  });
}
