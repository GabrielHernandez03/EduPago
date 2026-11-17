import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/student_account.dart';
import 'student_repository.dart';

typedef _Rows = List<Map<String, dynamic>>;

class _ApplicationsData {
  const _ApplicationsData(this.applications, this.payments);
  final _Rows applications;
  final _Rows payments;
}

class _RepresentativesData {
  const _RepresentativesData(this.relations, this.representatives);
  final _Rows relations;
  final _Rows representatives;
}

class SupabaseStudentRepository implements StudentRepository {
  SupabaseStudentRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _pageSize = 500;
  static const _chunkSize = 100;

  /// Máximo de consultas de un mismo lote que viajan a la vez.
  static const _concurrency = 4;

  /// Lee todas las páginas: Supabase suele limitar una consulta a 1000 filas.
  /// No se informa solvencia sobre una lista de cuotas truncada.
  Future<_Rows> _pages(
    Future<dynamic> Function(int start, int end) query,
  ) async {
    final output = <Map<String, dynamic>>[];
    for (var from = 0; ; from += _pageSize) {
      final response = await query(from, from + _pageSize - 1);
      final batch = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      output.addAll(batch);
      if (batch.length < _pageSize) break;
    }
    return output;
  }

  /// Divide [ids] en bloques de 100 y los consulta en paralelo (ventanas de
  /// [_concurrency] peticiones) conservando el orden de los resultados.
  ///
  /// No filtra saldos por colegio_id porque la vista v_saldo_cuotas puede no
  /// exponerlo. Los IDs proceden exclusivamente de estudiantes del colegio.
  Future<_Rows> _batchIds(
    List<String> ids,
    Future<_Rows> Function(List<String> ids) fetch,
  ) async {
    final chunks = <List<String>>[
      for (var i = 0; i < ids.length; i += _chunkSize)
        ids.sublist(i, math.min(i + _chunkSize, ids.length)),
    ];
    final all = <Map<String, dynamic>>[];
    for (var i = 0; i < chunks.length; i += _concurrency) {
      final window = chunks.skip(i).take(_concurrency);
      final results = await Future.wait(window.map(fetch));
      for (final rows in results) {
        all.addAll(rows);
      }
    }
    return all;
  }

  // ---------------------------------------------------------------------------
  // Cargas secundarias. Cada una captura sus propios errores y devuelve null si
  // falla, para no tumbar el directorio completo (mismo comportamiento previo).
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _loadConcepts(List<String> conceptIds) async {
    final concepts = <String, String>{};
    if (conceptIds.isEmpty) return concepts;
    try {
      final rows = await _batchIds(
        conceptIds,
        (part) => _pages(
          (from, to) => _client
              .from('conceptos_cobro')
              .select('*')
              .inFilter('id', part)
              .order('id')
              .range(from, to),
        ),
      );
      for (final row in rows) {
        final name = studentText(row, [
          'nombre',
          'descripcion',
          'titulo',
          'tipo',
        ]);
        concepts[studentText(row, ['id'])] = name.isEmpty
            ? 'Concepto sin nombre'
            : name;
      }
    } catch (e) {
      debugPrint('No se pudieron consultar conceptos de cobro: $e');
    }
    return concepts;
  }

  Future<_Rows?> _loadBalances(List<String> studentIds) async {
    if (studentIds.isEmpty) return <Map<String, dynamic>>[];
    try {
      return await _batchIds(
        studentIds,
        (part) => _pages(
          (from, to) => _client
              .from('v_saldo_cuotas')
              .select('cuota_id, estudiante_id, monto_usd, saldo_usd')
              .inFilter('estudiante_id', part)
              .order('cuota_id')
              .range(from, to),
        ),
      );
    } catch (e) {
      debugPrint('No fue posible leer v_saldo_cuotas: $e');
      return null;
    }
  }

  Future<_ApplicationsData?> _loadApplications(
    String colegioId,
    List<String> quotaIds,
  ) async {
    if (quotaIds.isEmpty) {
      return const _ApplicationsData([], []);
    }
    try {
      final applications = await _batchIds(
        quotaIds,
        (part) => _pages(
          (from, to) => _client
              .from('pago_aplicaciones')
              .select('*')
              .inFilter('cuota_id', part)
              .order('cuota_id')
              .range(from, to),
        ),
      );
      final paymentIds = applications
          .map((a) => studentText(a, ['pago_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final payments = paymentIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _batchIds(
              paymentIds,
              (part) => _pages(
                (from, to) => _client
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
      return _ApplicationsData(applications, payments);
    } catch (e) {
      debugPrint('No fue posible leer el desglose de pagos: $e');
      return null; // No se presentan aplicaciones parciales.
    }
  }

  Future<_RepresentativesData?> _loadRepresentatives(
    String colegioId,
    List<String> studentIds,
  ) async {
    if (studentIds.isEmpty) return const _RepresentativesData([], []);
    try {
      final relations = await _batchIds(
        studentIds,
        (part) => _pages(
          (from, to) => _client
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
      final reps = repIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _batchIds(
              repIds,
              (part) => _pages(
                (from, to) => _client
                    .from('representantes')
                    .select('*')
                    .eq('colegio_id', colegioId)
                    .inFilter('id', part)
                    .order('id')
                    .range(from, to),
              ),
            );
      return _RepresentativesData(relations, reps);
    } catch (e) {
      // La pantalla sigue funcionando si los permisos no dan acceso a contactos.
      debugPrint('Representantes no disponibles en directorio: $e');
      return null;
    }
  }

  @override
  Future<StudentDirectorySnapshot> fetchDirectory({
    required String colegioId,
  }) async {
    if (colegioId.trim().isEmpty) {
      throw ArgumentError.value(
        colegioId,
        'colegioId',
        'Se requiere un colegio',
      );
    }
    final sw = Stopwatch()..start();

    // Ola 1: estudiantes y cuotas no dependen entre sí.
    final wave1 = await Future.wait([
      _pages(
        (from, to) => _client
            .from('estudiantes')
            .select('*')
            .eq('colegio_id', colegioId)
            .order('id')
            .range(from, to),
      ),
      _pages(
        (from, to) => _client
            .from('cuotas')
            .select('*')
            .eq('colegio_id', colegioId)
            .order('id')
            .range(from, to),
      ),
    ]);
    final students = wave1[0].map(StudentAccount.new).toList();
    final studentById = {for (final s in students) s.id: s};
    final studentIds = studentById.keys.where((id) => id.isNotEmpty).toList();

    final quotaRows = wave1[1]
        .where(
          (q) => studentById.containsKey(studentText(q, ['estudiante_id'])),
        )
        .toList();
    final quotaIds = quotaRows
        .map((q) => studentText(q, ['id']))
        .where((id) => id.isNotEmpty)
        .toList();
    final conceptIds = quotaRows
        .map((q) => studentText(q, ['concepto_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final t1 = sw.elapsedMilliseconds;

    // Ola 2: las cuatro cargas arrancan a la vez (ya están en vuelo al hacer
    // await de la primera) y solo dependen de los IDs de la ola 1.
    final conceptsFuture = _loadConcepts(conceptIds);
    final balancesFuture = _loadBalances(studentIds);
    final applicationsFuture = _loadApplications(colegioId, quotaIds);
    final representativesFuture = _loadRepresentatives(colegioId, studentIds);

    final concepts = await conceptsFuture;
    final balanceRows = await balancesFuture;
    final applicationsData = await applicationsFuture;
    final representativesData = await representativesFuture;

    // Ensamblado local (sin red).
    final quotaById = <String, StudentQuota>{};
    for (final row in quotaRows) {
      final student = studentById[studentText(row, ['estudiante_id'])];
      if (student == null) continue;
      final quota = StudentQuota(
        row,
        concepts[studentText(row, ['concepto_id'])] ?? 'Concepto no disponible',
      );
      quotaById[quota.id] = quota;
      student.quotas.add(quota);
    }

    // Si la vista no se puede leer, nunca etiquetamos alumnos como solventes.
    final balancesAvailable = balanceRows != null;
    for (final row in balanceRows ?? const <Map<String, dynamic>>[]) {
      final quota = quotaById[studentText(row, ['cuota_id'])];
      if (quota != null) quota.balanceRow = row;
    }

    final applicationsAvailable = applicationsData != null;
    final paymentsById = <String, Map<String, dynamic>>{};
    if (applicationsData != null) {
      for (final app in applicationsData.applications) {
        quotaById[studentText(app, ['cuota_id'])]?.applications.add(app);
      }
      for (final pay in applicationsData.payments) {
        paymentsById[studentText(pay, ['id'])] = pay;
      }
    }

    if (representativesData != null) {
      final repsById = {
        for (final r in representativesData.representatives)
          studentText(r, ['id']): r,
      };
      for (final relation in representativesData.relations) {
        final s = studentById[studentText(relation, ['estudiante_id'])];
        final r = repsById[studentText(relation, ['representante_id'])];
        if (s != null && r != null) s.representatives.add(r);
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

    debugPrint(
      '[fetchDirectory] ${students.length} estudiantes, ${quotaRows.length} '
      'cuotas | ola1: ${t1}ms | total: ${sw.elapsedMilliseconds}ms',
    );
    return StudentDirectorySnapshot(
      students: students,
      paymentsById: paymentsById,
      balancesAvailable: balancesAvailable,
      applicationsAvailable: applicationsAvailable,
    );
  }

  @override
  Future<bool> studentExists({
    required String colegioId,
    required String cedula,
  }) async {
    final row = await _client
        .from('estudiantes')
        .select('id')
        .eq('colegio_id', colegioId)
        .eq('cedula', cedula)
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<bool> representativeExists({
    required String colegioId,
    required String cedula,
  }) async {
    final row = await _client
        .from('representantes')
        .select('id')
        .eq('colegio_id', colegioId)
        .eq('cedula', cedula)
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<Map<String, dynamic>?> findRepresentative({
    required String colegioId,
    required String cedula,
  }) async {
    final row = await _client
        .from('representantes')
        .select('id, nombres, apellidos, telefono_whatsapp, email, direccion')
        .eq('colegio_id', colegioId)
        .eq('cedula', cedula)
        .limit(1)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<Map<String, dynamic>?> importStudents({
    required String colegioId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final response = await _client.functions.invoke(
      'import-students',
      body: {'colegio_id': colegioId, 'rows': rows},
    );
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }
}
