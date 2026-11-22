/// Tipo de operación financiera mostrado al administrador
enum AuditOperation {
  aprobacion('Aprobación', ['aprob']),
  rechazo('Rechazo', ['rechaz']),
  eliminacion('Eliminación', ['elimin', 'delete']),
  modificacion('Modificación', ['modific', 'actualiz', 'update']),
  registro('Registro', ['crea', 'regist', 'generac', 'insert']),
  otro('Otra', []);

  const AuditOperation(this.label, this.patterns);
  final String label;

  /// Fragmentos (en minúsculas) que identifican la operación en `accion`.
  final List<String> patterns;

  static AuditOperation fromAccion(String accion) {
    final a = accion.toLowerCase();
    for (final op in values) {
      if (op.patterns.any(a.contains)) return op;
    }
    return otro;
  }
}