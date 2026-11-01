import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/reported_payment.dart';
import 'payment_repository.dart';

/// Único punto de acceso a Supabase para el historial de pagos.
/// Mantiene el enriquecimiento de conceptos, aplicaciones y avisos de rechazo.
class SupabasePaymentRepository implements PaymentRepository {
  SupabasePaymentRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  RealtimeChannel? _channel;

  @override
  void startListening({
    required String representativeId,
    required void Function() onChanged,
  }) {
    stopListening();
    if (representativeId.trim().isEmpty) {
      return;
    }
    _channel = _client
        .channel('historial-pagos-$representativeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pagos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'representante_id',
            value: representativeId,
          ),
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  @override
  void stopListening() {
    final current = _channel;
    _channel = null;
    if (current != null) {
      _client.removeChannel(current);
    }
  }

  @override
  Future<List<ReportedPayment>> loadPayments({
    required String representativeId,
    String? focusPaymentId,
  }) async {
    if (representativeId.trim().isEmpty) {
      return <ReportedPayment>[];
    }
    final client = _client;
    // El filtro por representante y la RLS protegen la privacidad de cada familia.
    final rows = await client
        .from('pagos')
        .select('*')
        .eq('representante_id', representativeId)
        .order('creado_at', ascending: false)
        .limit(100);

    final payments = (rows as List)
        .whereType<Map>()
        .map((v) => ReportedPayment(Map<String, dynamic>.from(v)))
        .toList();

    // Si la notificación apunta a uno más antiguo que los 100 últimos,
    // se consulta ese registro concreto, siempre limitado al representante.
    final target = focusPaymentId?.trim();
    if (target != null &&
        target.isNotEmpty &&
        !payments.any((p) => p.id == target)) {
      try {
        final extra = await client
            .from('pagos')
            .select('*')
            .eq('representante_id', representativeId)
            .eq('id', target)
            .maybeSingle();
        if (extra != null) {
          payments.insert(0, ReportedPayment(extra));
        }
      } catch (e) {
        debugPrint('No fue posible recuperar el pago de la notificación: $e');
      }
    }

    // Relacionar cada pago con las cuotas que realmente cubre:
    // pagos.id -> pago_aplicaciones.pago_id -> cuotas.id
    // -> conceptos_cobro.id. Nunca adivinamos el mes desde la fecha del pago.
    await _loadAppliedQuotaConcepts(client, payments, representativeId);

    // Algunas instalaciones guardan el motivo en la notificación emitida
    // cuando el administrador rechazó el pago. Se combina con el registro.
    // Fallar al leer notificaciones no impide visualizar los pagos.
    final uid = client.auth.currentUser?.id;
    if (uid != null) {
      try {
        final notices = await client
            .from('notificaciones_app')
            .select('tipo, mensaje, datos')
            .eq('perfil_id', uid)
            .order('creada_at', ascending: false)
            .limit(300);
        for (final obj in notices) {
          final note = Map<String, dynamic>.from(obj);
          final data = note['datos'];
          final metadata = data is Map
              ? Map<String, dynamic>.from(data)
              : <String, dynamic>{};
          final notificationId = _paymentIdFromMetadata(metadata);
          final reference = _referenceFromMetadata(metadata);
          final matchedById = notificationId == null
              ? <ReportedPayment>[]
              : payments.where((p) => p.id == notificationId).toList();
          final matchedByReference = notificationId != null || reference == null
              ? <ReportedPayment>[]
              : payments
                    .where(
                      (p) =>
                          p.reference.isNotEmpty &&
                          p.reference.toLowerCase() == reference.toLowerCase(),
                    )
                    .toList();
          // Una misma referencia puede repetirse: nunca atribuimos un
          // rechazo a varios pagos por una coincidencia ambigua.
          final matches = matchedById.isNotEmpty
              ? matchedById
              : (notificationId == null && matchedByReference.length == 1
                    ? matchedByReference
                    : <ReportedPayment>[]);
          for (final p in matches) {
            p.addNotification(note);
          }
        }
      } catch (e) {
        debugPrint('No se pudieron recuperar las notas de notificación: $e');
      }
    }

    return payments;
  }

  /// Obtiene concepto y período de las cuotas realmente aplicadas.
  /// Para pagos aún en revisión (que no tienen pago_aplicaciones), calcula
  /// una PREVISIÓN de FIFO, sin confundirla con una aplicación contabilizada.
  /// Una transacción puede cubrir varias cuotas y varios estudiantes.
  Future<void> _loadAppliedQuotaConcepts(
    SupabaseClient client,
    List<ReportedPayment> payments,
    String representativeId,
  ) async {
    final paymentIds = payments
        .map((p) => p.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (paymentIds.isEmpty) {
      return;
    }

    // Asociaciones explícitas que pudiera registrar el backend en pagos.
    final quotaIdsByPayment = <String, Set<String>>{};
    for (final payment in payments) {
      for (final field in ['cuota_id', 'id_cuota']) {
        final id = payment.raw[field]?.toString().trim() ?? '';
        if (id.isNotEmpty) {
          quotaIdsByPayment.putIfAbsent(payment.id, () => <String>{}).add(id);
        }
      }
      for (final field in ['cuota_ids', 'cuotas_ids']) {
        final values = payment.raw[field];
        if (values is! List) {
          continue;
        }
        for (final value in values) {
          final id = value?.toString().trim() ?? '';
          if (id.isNotEmpty) {
            quotaIdsByPayment.putIfAbsent(payment.id, () => <String>{}).add(id);
          }
        }
      }
    }

    final applicationsByPayment = <String, List<Map<String, dynamic>>>{};
    try {
      final applications = await client
          .from('pago_aplicaciones')
          .select('*')
          .inFilter('pago_id', paymentIds);
      for (final app in applications) {
        final paymentId = app['pago_id']?.toString().trim() ?? '';
        final quotaId = app['cuota_id']?.toString().trim() ?? '';
        if (paymentId.isEmpty || quotaId.isEmpty) {
          continue;
        }
        applicationsByPayment
            .putIfAbsent(paymentId, () => <Map<String, dynamic>>[])
            .add(Map<String, dynamic>.from(app));
        quotaIdsByPayment.putIfAbsent(paymentId, () => <String>{}).add(quotaId);
      }
    } catch (e) {
      debugPrint('No se pudieron consultar las aplicaciones de pago: $e');
    }

    // La conciliación FIFO solo ocurre al aprobar. Antes de eso se pueden
    // mostrar las cuotas que previsiblemente cubrirá el pago, con una
    // advertencia de que NO es una asignación definitiva.
    final pending = payments
        .where(
          (p) =>
              p.normalizedStatus == 'pendiente' &&
              !(quotaIdsByPayment[p.id]?.isNotEmpty ?? false),
        )
        .toList();
    final pendingBalances = <Map<String, dynamic>>[];
    if (pending.isNotEmpty) {
      try {
        final relations = await client
            .from('representante_estudiante')
            .select('estudiante_id')
            .eq('representante_id', representativeId);
        final studentIds = relations
            .map((r) => r['estudiante_id']?.toString().trim() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (studentIds.isNotEmpty) {
          final balances = await client
              .from('v_saldo_cuotas')
              .select('cuota_id, estudiante_id, saldo_usd')
              .inFilter('estudiante_id', studentIds);
          pendingBalances.addAll(
            balances.map((row) => Map<String, dynamic>.from(row)),
          );
        }
      } catch (e) {
        debugPrint('No se pudo obtener la vista previa de cuotas: $e');
      }
    }

    final allQuotaIds = <String>{
      ...quotaIdsByPayment.values.expand((ids) => ids),
      ...pendingBalances.map((b) => b['cuota_id']?.toString() ?? ''),
    }..remove('');
    if (allQuotaIds.isEmpty) {
      return;
    }

    try {
      // SELECT * es importante: algunos esquemas guardan el concepto como
      // cuotas.concepto (texto), otros como cuotas.concepto_id.
      final quotaRows = <Map<String, dynamic>>[];
      final ids = allQuotaIds.toList();
      for (var i = 0; i < ids.length; i += 100) {
        final end = (i + 100 < ids.length) ? i + 100 : ids.length;
        final rows = await client
            .from('cuotas')
            .select('*')
            .inFilter('id', ids.sublist(i, end));
        quotaRows.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
      }
      final quotaById = <String, Map<String, dynamic>>{
        for (final row in quotaRows) row['id'].toString(): row,
      };
      final conceptIds = quotaRows
          .map((q) => q['concepto_id']?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();
      final conceptById = <String, String>{};
      if (conceptIds.isNotEmpty) {
        try {
          final concepts = await client
              .from('conceptos_cobro')
              .select('*')
              .inFilter('id', conceptIds);
          for (final row in concepts) {
            final id = row['id']?.toString() ?? '';
            final name = _firstField(Map<String, dynamic>.from(row), [
              'nombre',
              'nombre_concepto',
              'titulo',
              'descripcion',
              'concepto',
              'tipo',
            ]);
            if (id.isNotEmpty && name.isNotEmpty) {
              conceptById[id] = name;
            }
          }
        } catch (e) {
          debugPrint('No se pudieron consultar conceptos_cobro: $e');
        }
      }

      // Identifica cuotas iguales de distintos estudiantes en el desglose.
      final studentIds = quotaRows
          .map((q) => q['estudiante_id']?.toString().trim() ?? '')
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();
      final studentById = <String, String>{};
      if (studentIds.isNotEmpty) {
        try {
          final students = await client
              .from('estudiantes')
              .select('id, nombres, apellidos')
              .inFilter('id', studentIds);
          for (final s in students) {
            final id = s['id']?.toString() ?? '';
            final name = '${s['nombres'] ?? ''} ${s['apellidos'] ?? ''}'.trim();
            if (id.isNotEmpty && name.isNotEmpty) {
              studentById[id] = name;
            }
          }
        } catch (e) {
          debugPrint('No se pudieron consultar nombres de estudiantes: $e');
        }
      }

      String conceptFor(Map<String, dynamic> quota) {
        final direct = _firstField(quota, ['concepto', 'nombre_concepto']);
        if (direct.isNotEmpty) {
          return direct;
        }
        return conceptById[quota['concepto_id']?.toString() ?? ''] ?? '';
      }

      // Los conceptos se agrupan por mensualidad (no por estudiante).
      // El importe de cada estudiante se calcula EXCLUSIVAMENTE a partir de
      // pago_aplicaciones: no se divide el pago entre hijos por aproximación.
      void assign(
        ReportedPayment payment,
        List<String> quotaIds, {
        required bool estimated,
      }) {
        final lines = <String>[];
        final periods = <String>[];
        final concepts = <String>[];
        for (final id in quotaIds) {
          final quota = quotaById[id];
          if (quota == null) {
            continue;
          }
          final concept = conceptFor(quota);
          final period = _firstField(quota, ['periodo', 'mes_periodo']);
          final label = _quotaDescription(concept, period);
          if (label.isEmpty) {
            continue;
          }
          if (!lines.contains(label)) {
            lines.add(label);
          }
          if (concept.isNotEmpty && !concepts.contains(concept)) {
            concepts.add(concept);
          }
          if (period.isNotEmpty && !periods.contains(period)) {
            periods.add(period);
          }
        }
        if (lines.isEmpty) {
          return;
        }
        payment.setAppliedQuotaLabels(
          lines,
          quotaIds.where(quotaById.containsKey).length,
          concepts: concepts,
          periods: periods,
          estimated: estimated,
        );
      }

      for (final payment in payments) {
        final explicit = quotaIdsByPayment[payment.id];
        if (explicit == null || explicit.isEmpty) {
          continue;
        }
        assign(
          payment,
          explicit.toList(),
          estimated: payment.normalizedStatus == 'pendiente',
        );

        final apps = applicationsByPayment[payment.id];
        if (apps == null ||
            apps.isEmpty ||
            payment.normalizedStatus != 'aprobado') {
          continue;
        }

        // Agrupar el importe aplicado por estudiante, sumando las distintas
        // mensualidades que cubra este pago para una misma persona.
        final grouped = <String, StudentPaymentAllocation>{};
        for (final app in apps) {
          final quotaId = app['cuota_id']?.toString().trim() ?? '';
          final quota = quotaById[quotaId];
          if (quota == null) {
            continue;
          }
          final studentId = quota['estudiante_id']?.toString().trim() ?? '';
          if (studentId.isEmpty) {
            continue;
          }
          final name =
              studentById[studentId] ?? 'Estudiante sin nombre disponible';
          final amount = _firstNumeric(app, [
            'monto_usd_aplicado',
            'monto_aplicado_usd',
            'monto_usd',
          ]);
          final previous = grouped[studentId];
          final total =
              amount == null || (previous != null && previous.amountUsd == null)
              ? null
              : (previous?.amountUsd ?? 0.0) + amount;
          grouped[studentId] = StudentPaymentAllocation(
            name: name,
            amountUsd: total,
            quotaCount: (previous?.quotaCount ?? 0) + 1,
          );
        }
        if (grouped.isNotEmpty) {
          payment.setStudentAllocations(grouped.values.toList());
        }
      }

      if (pendingBalances.isEmpty) {
        return;
      }
      // Esta vista previa replica el orden FIFO esperado, NO una distribución
      // confirmada. Se descuentan las vistas previas de otros pagos pendientes
      // para evitar mostrar la misma cuota dos veces por simple acumulación.
      final available = <String, double>{};
      for (final row in pendingBalances) {
        final id = row['cuota_id']?.toString() ?? '';
        final saldo = _asAmount(row['saldo_usd']);
        if (quotaById.containsKey(id) && saldo > 0.01) {
          available[id] = saldo;
        }
      }
      final sortedIds = available.keys.toList()
        ..sort((a, b) {
          final qa = quotaById[a]!;
          final qb = quotaById[b]!;
          final da = _firstField(qa, ['fecha_vencimiento']);
          final db = _firstField(qb, ['fecha_vencimiento']);
          final byDate = da.compareTo(db);
          return byDate != 0 ? byDate : a.compareTo(b);
        });
      pending.sort((a, b) {
        final left = a.createdAt ?? a.paymentDate ?? DateTime(1970);
        final right = b.createdAt ?? b.paymentDate ?? DateTime(1970);
        return left.compareTo(right);
      });
      for (final payment in pending) {
        var remaining = payment.amountUsdEquivalent;
        if (remaining <= 0.01) {
          continue;
        }
        final targetIds = <String>[];
        for (final id in sortedIds) {
          final due = available[id] ?? 0;
          if (due <= 0.01 || remaining <= 0.01) {
            continue;
          }
          final applied = remaining < due ? remaining : due;
          remaining -= applied;
          available[id] = due - applied;
          targetIds.add(id);
        }
        if (targetIds.isNotEmpty) {
          assign(payment, targetIds, estimated: true);
        }
      }
    } catch (e) {
      debugPrint('No se pudo leer la información de cuotas: $e');
    }
  }

  static double _asAmount(dynamic raw) {
    if (raw is num) {
      return raw.toDouble();
    }
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static double? _firstNumeric(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final raw = row[key];
      if (raw == null) {
        continue;
      }
      final value = raw is num
          ? raw.toDouble()
          : double.tryParse(raw.toString());
      if (value != null && value.isFinite && value >= 0) {
        return value;
      }
    }
    return null;
  }

  static String _firstField(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return '';
  }

  static String _quotaDescription(String concept, String period) {
    if (concept.isEmpty) {
      return period;
    }
    if (period.isEmpty) {
      return concept;
    }
    // Ej.: «Mensualidad de Octubre 2026». Otros conceptos conservan su
    // denominación real, como «Inscripción · Septiembre 2026».
    if (concept.toLowerCase() == 'mensualidad') {
      return '$concept de $period';
    }
    return '$concept · $period';
  }

  static String? _paymentIdFromMetadata(Map<String, dynamic> data) {
    for (final key in ['pago_id', 'id_pago', 'payment_id']) {
      final id = data[key]?.toString().trim();
      if (id != null && id.isNotEmpty) {
        return id;
      }
    }
    final nested = data['pago'];
    if (nested is Map) {
      for (final key in ['id', 'pago_id']) {
        final id = nested[key]?.toString().trim();
        if (id != null && id.isNotEmpty) {
          return id;
        }
      }
    }
    return null;
  }

  static String? _referenceFromMetadata(Map<String, dynamic> data) {
    for (final key in [
      'referencia',
      'referencia_pago',
      'referencia_bancaria',
      'numero_referencia',
    ]) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}
