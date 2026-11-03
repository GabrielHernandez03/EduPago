/// Estado de acceso de un estudiante vinculado a un representante.
/// Un valor ausente no debe interpretarse automáticamente como "Activo".
enum StudentAccountAccess { active, inactive, unverified }

class StudentAccountSelection {
  const StudentAccountSelection._();

  /// `estudiantes.activo` normalmente es booleano en Supabase.
  /// Las cadenas se soportan por compatibilidad con datos serializados.
  static StudentAccountAccess accessOf(Map<String, dynamic> student) {
    final raw = student['activo'];
    if (raw == true || raw == 1) return StudentAccountAccess.active;
    if (raw == false || raw == 0) return StudentAccountAccess.inactive;
    if (raw is String) {
      switch (raw.trim().toLowerCase()) {
        case 'true':
        case 't':
        case '1':
        case 'activo':
          return StudentAccountAccess.active;
        case 'false':
        case 'f':
        case '0':
        case 'no':
        case 'inactivo':
        case 'retirado':
          return StudentAccountAccess.inactive;
      }
    }
    return StudentAccountAccess.unverified;
  }

  static bool canSelect(Map<String, dynamic> student) =>
      accessOf(student) == StudentAccountAccess.active;

  static String labelOf(Map<String, dynamic> student) =>
      switch (accessOf(student)) {
        StudentAccountAccess.active => 'Activo',
        StudentAccountAccess.inactive => 'Inactivo',
        StudentAccountAccess.unverified => 'Estado no verificado',
      };
}
