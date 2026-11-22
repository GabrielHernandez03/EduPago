import 'audit_operation.dart';

class AuditChange {
  final String field;
  final Object? before;
  final Object? after;
  const AuditChange(this.field, this.before, this.after);
}

/// Un evento de la bitácora (fila de `auditoria`). Es de solo lectura.
class AuditEntry {
  /// Textos legibles de las acciones conocidas de `auditoria.accion`.
  static const _actionLabels = {
    'CREAR_CONCEPTO_COBRO': 'Creación de concepto de cobro',
    'MODIFICAR_CONCEPTO_COBRO': 'Modificación de concepto de cobro',
    'GENERACION_CUOTAS_MENSUALES': 'Generación de cuotas mensuales',
    'REGISTRAR_PAGO': 'Registro de pago',
    'APROBAR_PAGO': 'Aprobación de pago',
    'RECHAZAR_PAGO': 'Rechazo de pago',
    'MODIFICAR_PAGO': 'Modificación de pago',
    'ELIMINAR_PAGO': 'Eliminación de pago',
  };
  static const _ignoredFields = {'actualizado_at', 'creado_at', 'created_at'};

  final int id;
  final String? userId;
  final String userName;
  final String accion;
  final String tabla;
  final String registroId;
  final Map<String, dynamic>? antes;
  final Map<String, dynamic>? despues;
  final DateTime createdAt;
  final AuditOperation operation;

  const AuditEntry({
    required this.id,
    required this.userId,
    required this.userName,
    required this.accion,
    required this.tabla,
    required this.registroId,
    required this.antes,
    required this.despues,
    required this.createdAt,
    required this.operation,
  });

  factory AuditEntry.fromMap(Map<String, dynamic> m, {String? userName}) {
    Map<String, dynamic>? json(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;
    final antes = json(m['datos_antes']);
    final despues = json(m['datos_despues']);
    final accion = (m['accion'] ?? '').toString();
    final tabla = (m['tabla'] ?? '').toString();
    final userId = m['usuario_id']?.toString();
    return AuditEntry(
      id: (m['id'] as num).toInt(),
      userId: userId,
      userName:
          userName ?? (userId == null ? 'Sistema' : 'Usuario no identificado'),
      accion: accion,
      tabla: tabla,
      registroId: (m['registro_id'] ?? '').toString(),
      antes: antes,
      despues: despues,
      createdAt: DateTime.parse(m['created_at'].toString()).toLocal(),
      operation: AuditOperation.fromAccion(accion),
    );
  }

  String get summary {
    final d = despues ?? antes ?? const <String, dynamic>{};
    final key = accion.toUpperCase();
    final head = _actionLabels[key] ?? _humanize(accion);
    switch (tabla) {
      case 'pagos':
        return d['monto'] == null
            ? head
            : '$head por ${d['monto']} ${d['moneda'] ?? ''}'.trim();
      case 'conceptos_cobro':
        return d['nombre'] == null ? head : '$head · ${d['nombre']}';
      default:
        return head;
    }
  }

  static String _humanize(String a) {
    final t = a.toLowerCase().replaceAll('_', ' ').trim();
    return t.isEmpty ? 'Operación' : t[0].toUpperCase() + t.substring(1);
  }

  /// Campos que cambiaron (o, en altas/bajas, todos los campos del registro).
  List<AuditChange> get changes {
    final a = antes ?? const <String, dynamic>{};
    final b = despues ?? const <String, dynamic>{};
    final keys = {
      ...a.keys,
      ...b.keys,
    }.where((k) => !_ignoredFields.contains(k)).toList()..sort();
    return [
      for (final k in keys)
        if ('${a[k]}' != '${b[k]}') AuditChange(k, a[k], b[k]),
    ];
  }
}
