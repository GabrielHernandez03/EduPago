import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/student_account.dart';
import 'student_repository.dart';

class SupabaseStudentRepository implements StudentRepository {
  SupabaseStudentRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Lee todas las páginas: Supabase suele limitar una consulta a 1000 filas.
  /// No se informa solvencia sobre una lista de cuotas truncada.
  Future<List<Map<String, dynamic>>> _pages(
    Future<dynamic> Function(int start, int end) query,
  ) async {
    const size = 500;
    final output = <Map<String, dynamic>>[];
    for (var from = 0; ; from += size) {
      final response = await query(from, from + size - 1);
      final batch = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      output.addAll(batch);
      if (batch.length < size) break;
    }
    return output;
  }

  /// No filtra saldos por colegio_id porque la vista v_saldo_cuotas puede no
  /// exponerlo. Los IDs proceden exclusivamente de estudiantes del colegio.
  Future<List<Map<String, dynamic>>> _batchIds(
    List<String> ids,
    Future<List<Map<String, dynamic>>> Function(List<String> ids) fetch,
  ) async {
    final all = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += 100) {
      final end = i + 100 < ids.length ? i + 100 : ids.length;
      all.addAll(await fetch(ids.sublist(i, end)));
    }
    return all;
  }

  @override
  Future<StudentDirectorySnapshot> fetchDirectory({required String colegioId}) async {
    if (colegioId.trim().isEmpty) {
      throw ArgumentError.value(colegioId, 'colegioId', 'Se requiere un colegio');
    }
      final client = _client;
      final studentRows = await _pages(
        (from, to) => client
            .from('estudiantes')
            .select('*')
            .eq('colegio_id', colegioId)
            .order('id')
            .range(from, to),
      );
      final students = studentRows.map(StudentAccount.new).toList();
      final studentById = {for (final s in students) s.id: s};
      final ids = students
          .map((s) => s.id)
          .where((id) => id.isNotEmpty)
          .toList();

      final quotaRows = await _pages(
        (from, to) => client
            .from('cuotas')
            .select('*')
            .eq('colegio_id', colegioId)
            .order('id')
            .range(from, to),
      );
      final conceptIds = quotaRows
          .map((q) => studentText(q, ['concepto_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final concepts = <String, String>{};
      if (conceptIds.isNotEmpty) {
        try {
          final conceptRows = await _batchIds(
            conceptIds,
            (part) => _pages(
              (from, to) => client
                  .from('conceptos_cobro')
                  .select('*')
                  .inFilter('id', part)
                  .order('id')
                  .range(from, to),
            ),
          );
          for (final row in conceptRows) {
            concepts[studentText(
              row,
              ['id'],
            )] = studentText(row, ['nombre', 'descripcion', 'titulo', 'tipo']).isEmpty
                ? 'Concepto sin nombre'
                : studentText(row, ['nombre', 'descripcion', 'titulo', 'tipo']);
          }
        } catch (e) {
          debugPrint('No se pudieron consultar conceptos de cobro: $e');
        }
      }
      final quotaById = <String, StudentQuota>{};
      for (final row in quotaRows) {
        final student = studentById[studentText(row, ['estudiante_id'])];
        if (student == null) continue;
        final conceptId = studentText(row, ['concepto_id']);
        final quota = StudentQuota(
          row,
          concepts[conceptId] ?? 'Concepto no disponible',
        );
        quotaById[quota.id] = quota;
        student.quotas.add(quota);
      }

      // Si la vista no se puede leer, nunca etiquetamos alumnos como solventes.
      var balancesAvailable = true;
      try {
        if (ids.isNotEmpty) {
          final balances = await _batchIds(
            ids,
            (part) => _pages(
              (from, to) => client
                  .from('v_saldo_cuotas')
                  .select('cuota_id, estudiante_id, monto_usd, saldo_usd')
                  .inFilter('estudiante_id', part)
                  .order('cuota_id')
                  .range(from, to),
            ),
          );
          for (final row in balances) {
            final quota = quotaById[studentText(row, ['cuota_id'])];
            if (quota != null) quota.balanceRow = row;
          }
        }
      } catch (e) {
        balancesAvailable = false;
        debugPrint('No fue posible leer v_saldo_cuotas: $e');
      }

      var applicationsAvailable = true;
      final paymentsById = <String, Map<String, dynamic>>{};
      if (quotaById.isNotEmpty) {
        try {
          final applicationRows = await _batchIds(
            quotaById.keys.toList(),
            (part) => _pages(
              (from, to) => client
                  .from('pago_aplicaciones')
                  .select('*')
                  .inFilter('cuota_id', part)
                  .order('cuota_id')
                  .range(from, to),
            ),
          );
          final paymentIds = <String>{};
          for (final app in applicationRows) {
            final quota = quotaById[studentText(app, ['cuota_id'])];
            if (quota == null) continue;
            quota.applications.add(app);
            final id = studentText(app, ['pago_id']);
            if (id.isNotEmpty) paymentIds.add(id);
          }
          if (paymentIds.isNotEmpty) {
            final paymentRows = await _batchIds(
              paymentIds.toList(),
              (part) => _pages(
                (from, to) => client
                    .from('pagos')
                    .select(
                      'id, colegio_id, referencia, fecha_pago, metodo, estado',
                    )
                    .eq('colegio_id', colegioId)
                    .inFilter('id', part)
                    .order('id')
                    .range(from, to),
              ),
            );
            for (final pay in paymentRows) {
              paymentsById[studentText(pay, ['id'])] = pay;
            }
          }
        } catch (e) {
          applicationsAvailable = false;
          debugPrint('No fue posible leer el desglose de pagos: $e');
          // No se presentan aplicaciones parciales si falló alguna página.
          for (final quota in quotaById.values) {
            quota.applications.clear();
          }
        }
      }

      // Relación estudiante-representante: la pantalla sigue funcionando cuando
      // los permisos no permiten acceder a los datos de contacto.
      if (ids.isNotEmpty) {
        try {
          final relations = await _batchIds(
            ids,
            (part) => _pages(
              (from, to) => client
                  .from('representante_estudiante')
                  .select('estudiante_id, representante_id')
                  .inFilter('estudiante_id', part)
                  .order('estudiante_id')
                  .range(from, to),
            ),
          );
          final repIds = relations
              .map((r) => studentText(r, ['representante_id']))
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          final repsById = <String, Map<String, dynamic>>{};
          if (repIds.isNotEmpty) {
            final reps = await _batchIds(
              repIds,
              (part) => _pages(
                (from, to) => client
                    .from('representantes')
                    .select('*')
                    .eq('colegio_id', colegioId)
                    .inFilter('id', part)
                    .order('id')
                    .range(from, to),
              ),
            );
            for (final r in reps) {
              repsById[studentText(r, ['id'])] = r;
            }
          }
          for (final relation in relations) {
            final s = studentById[studentText(relation, ['estudiante_id'])];
            final r = repsById[studentText(relation, ['representante_id'])];
            if (s != null && r != null) s.representatives.add(r);
          }
        } catch (e) {
          debugPrint('Representantes no disponibles en directorio: $e');
        }
      }

      for (final s in students) {
        s.quotas.sort((a, b) {
          if (a.due == null) return 1;
          if (b.due == null) return -1;
          return a.due!.compareTo(b.due!);
        });
      }
      students.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return StudentDirectorySnapshot(
      students: students,
      paymentsById: paymentsById,
      balancesAvailable: balancesAvailable,
      applicationsAvailable: applicationsAvailable,
    );
  }

  @override
  Future<bool> studentExists({required String colegioId, required String cedula}) async {
    final row = await _client.from('estudiantes').select('id')
        .eq('colegio_id', colegioId).eq('cedula', cedula)
        .limit(1).maybeSingle();
    return row != null;
  }

  @override
  Future<bool> representativeExists({required String colegioId, required String cedula}) async {
    final row = await _client.from('representantes').select('id')
        .eq('colegio_id', colegioId).eq('cedula', cedula)
        .limit(1).maybeSingle();
    return row != null;
  }

  @override
  Future<Map<String, dynamic>?> findRepresentative({required String colegioId, required String cedula}) async {
    final row = await _client.from('representantes')
        .select('id, nombres, apellidos, telefono_whatsapp, email, direccion')
        .eq('colegio_id', colegioId).eq('cedula', cedula)
        .limit(1).maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<Map<String, dynamic>?> importStudents({required String colegioId, required List<Map<String, dynamic>> rows}) async {
    final response = await _client.functions.invoke(
      'import-students',
      body: {'colegio_id': colegioId, 'rows': rows},
    );
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }
}
