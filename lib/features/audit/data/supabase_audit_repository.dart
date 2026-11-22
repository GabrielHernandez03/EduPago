import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/audit_entry.dart';
import '../domain/audit_filter.dart';
import 'audit_repository.dart';

class SupabaseAuditRepository implements AuditRepository {
  SupabaseAuditRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  /// Tablas con operaciones financieras que alimentan la bitácora.
  static const financialTables = ['pagos', 'cuotas', 'conceptos_cobro'];

  @override
  Future<List<AuditEntry>> fetch({
    required String schoolId,
    AuditFilter filter = const AuditFilter(),
    int offset = 0,
    int limit = 25,
  }) async {
    // `auditoria` guarda solo usuario_id: para filtrar por nombre se buscan
    // primero los perfiles del colegio que coinciden.
    List<String>? userIds;
    final name = filter.user.trim().replaceAll(RegExp(r'[%,()\\]'), '');
    if (name.isNotEmpty) {
      final r = await _client
          .from('perfiles')
          .select('id')
          .eq('colegio_id', schoolId)
          .ilike('nombre_completo', '%$name%');
      userIds = (r as List).map((e) => e['id'].toString()).toList();
      if (userIds.isEmpty) return const [];
    }

    var q = _client
        .from('auditoria')
        .select()
        .eq('colegio_id', schoolId)
        .inFilter('tabla', financialTables);

    if (userIds != null) q = q.inFilter('usuario_id', userIds);

    final op = filter.operation;
    if (op != null && op.patterns.isNotEmpty) {
      q = q.or(op.patterns.map((p) => 'accion.ilike.%$p%').join(','));
    }

    if (filter.from != null) {
      final f = DateTime(
        filter.from!.year,
        filter.from!.month,
        filter.from!.day,
      );
      q = q.gte('created_at', f.toUtc().toIso8601String());
    }
    if (filter.to != null) {
      final t = DateTime(filter.to!.year, filter.to!.month, filter.to!.day + 1);
      q = q.lt('created_at', t.toUtc().toIso8601String());
    }

    final rows = await q
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);

    final list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final names = await _userNames(list);
    return [
      for (final m in list)
        AuditEntry.fromMap(m, userName: names[m['usuario_id']?.toString()]),
    ];
  }

  Future<Map<String, String>> _userNames(
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = rows
        .map((m) => m['usuario_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return {};
    final r = await _client
        .from('perfiles')
        .select('id, nombre_completo')
        .inFilter('id', ids);
    return {
      for (final p in (r as List))
        p['id'].toString(): (p['nombre_completo'] ?? 'Usuario sin nombre')
            .toString(),
    };
  }
}
