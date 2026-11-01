import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_dashboard_repository.dart';

/// Acceso a Supabase para el resumen del colegio autenticado.
/// RLS es obligatorio: estos filtros NO reemplazan las políticas de la BD.
class SupabaseAdminDashboardRepository implements AdminDashboardRepository {
  SupabaseAdminDashboardRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<AdminDashboardIdentity> loadIdentity() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('No hay una sesión activa');
    final row = await _client.from('perfiles')
        .select('nombre_completo, colegio_id')
        .eq('id', user.id).maybeSingle();
    return AdminDashboardIdentity(
      name: (row?['nombre_completo'] ?? user.email ?? 'Administrador').toString(),
      schoolId: row?['colegio_id']?.toString(),
    );
  }

  /// Cada lectura debe comprobar la asociación actual del usuario al colegio.
  Future<void> _checkSchool(String schoolId) async {
    if (schoolId.isEmpty) throw StateError('No hay colegio asignado');
    final identity = await loadIdentity();
    if (identity.schoolId != schoolId) {
      throw StateError('La sesión no está asociada al colegio solicitado');
    }
  }

  Future<List<Map<String, dynamic>>> _pages(
    Future<dynamic> Function(int from, int to) fetch,
  ) async {
    const pageSize = 500;
    final result = <Map<String, dynamic>>[];
    for (var start = 0; ; start += pageSize) {
      final rows = await fetch(start, start + pageSize - 1) as List;
      result.addAll(rows.map((r) => Map<String, dynamic>.from(r as Map)));
      if (rows.length < pageSize) return result;
    }
  }

  @override
  Future<bool> schoolHasStudents(String schoolId) async {
    await _checkSchool(schoolId);
    final rows = await _client.from('estudiantes').select('id')
        .eq('colegio_id', schoolId).limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<AdminDashboardRows> loadRows({
    required String schoolId,
    required DateTime fromDate,
  }) async {
    await _checkSchool(schoolId);
    final students = await _pages((from, to) => _client.from('estudiantes')
        .select('id').eq('colegio_id', schoolId).eq('activo', true)
        .order('id').range(from, to));
    final quotas = await _pages((from, to) => _client.from('cuotas')
        .select('id, estudiante_id, fecha_vencimiento, periodo')
        .eq('colegio_id', schoolId).order('id').range(from, to));

    // v_saldo_cuotas no necesariamente expone colegio_id. Se consulta solo
    // con los IDs de cuotas previamente filtradas por colegio.
    final balances = <Map<String, dynamic>>[];
    final quotaIds = quotas.map((q) => (q['id'] ?? '').toString())
        .where((id) => id.isNotEmpty).toList();
    for (var i = 0; i < quotaIds.length; i += 80) {
      final end = i + 80 < quotaIds.length ? i + 80 : quotaIds.length;
      final ids = quotaIds.sublist(i, end);
      balances.addAll(await _pages((from, to) => _client
          .from('v_saldo_cuotas')
          .select('cuota_id, estudiante_id, monto_usd, saldo_usd')
          .inFilter('cuota_id', ids).order('cuota_id').range(from, to)));
    }
    final fromIso = '${fromDate.year.toString().padLeft(4, '0')}-'
        '${fromDate.month.toString().padLeft(2, '0')}-'
        '${fromDate.day.toString().padLeft(2, '0')}';
    final approved = await _pages((from, to) => _client.from('pagos')
        .select('id, monto_usd_equivalente, fecha_pago')
        .eq('colegio_id', schoolId).eq('estado', 'aprobado')
        .gte('fecha_pago', fromIso).order('id').range(from, to));
    final pending = await _pages((from, to) => _client.from('pagos')
        .select('id, creado_at').eq('colegio_id', schoolId)
        .eq('estado', 'pendiente').order('id').range(from, to));
    final data = AdminDashboardRows(
      students: students,
      quotas: quotas,
      balances: balances,
      approvedPayments: approved,
      pendingPayments: pending,
    );
    data.requireVerifiedBalances();
    return data;
  }

  @override
  Future<String> loadSchoolName(String schoolId) async {
    await _checkSchool(schoolId);
    final row = await _client.from('colegios').select('nombre')
        .eq('id', schoolId).maybeSingle();
    return (row?['nombre'] ?? '').toString();
  }

  @override
  Future<List<Map<String, dynamic>>> loadRecentPayments(String schoolId) async {
    await _checkSchool(schoolId);
    try {
      final rows = await _client.from('pagos').select(
        'id, monto, moneda, estado, creado_at, representantes (nombres, apellidos), '
        'pago_aplicaciones (cuotas (periodo, estudiantes (nombres, apellidos), conceptos_cobro(nombre)))',
      ).eq('colegio_id', schoolId).order('creado_at', ascending: false).limit(6);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      // La relación anidada puede no estar habilitada por la RLS del proyecto.
      final rows = await _client.from('pagos').select(
        'id, monto, moneda, estado, creado_at, representantes (nombres, apellidos)',
      ).eq('colegio_id', schoolId).order('creado_at', ascending: false).limit(6);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    }
  }
}
