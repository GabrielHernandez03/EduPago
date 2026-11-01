import '../domain/student_account.dart';

/// Resultado del directorio limitado al colegio solicitado.
/// La ausencia de saldos NO debe interpretarse como solvencia.
class StudentDirectorySnapshot {
  final List<StudentAccount> students;
  final Map<String, Map<String, dynamic>> paymentsById;
  final bool balancesAvailable;
  final bool applicationsAvailable;

  const StudentDirectorySnapshot({
    required this.students,
    required this.paymentsById,
    required this.balancesAvailable,
    required this.applicationsAvailable,
  });
}

/// Contrato de acceso a datos para el directorio, validación de documentos
/// y creación de estudiantes a través de la Edge Function existente.
abstract class StudentRepository {
  Future<StudentDirectorySnapshot> fetchDirectory({required String colegioId});
  Future<bool> studentExists({required String colegioId, required String cedula});
  Future<bool> representativeExists({required String colegioId, required String cedula});
  Future<Map<String, dynamic>?> findRepresentative({
    required String colegioId,
    required String cedula,
  });
  Future<Map<String, dynamic>?> importStudents({
    required String colegioId,
    required List<Map<String, dynamic>> rows,
  });
}
