import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/calendar_event.dart';
import 'calendar_repository.dart';

/// Implementación de acceso a datos. Solo esta capa conoce Supabase.
/// RLS debe autorizar la lectura en el servidor; los filtros del cliente
/// NO sustituyen políticas de seguridad por colegio y representante.
class SupabaseCalendarRepository implements CalendarRepository {
  SupabaseCalendarRepository({SupabaseClient? client, required this.channelKey})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final String channelKey;
  RealtimeChannel? _paymentsChannel;
  RealtimeChannel? _notificationsChannel;

  @override
  void startListening({
    required String representativeId,
    required void Function() onChanged,
  }) {
    stopListening();
    if (representativeId.trim().isEmpty) {
      return;
    }

    _paymentsChannel = _client
        .channel('edupago-cal-$channelKey-pagos-$representativeId')
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

    final profileId = _client.auth.currentUser?.id;
    if (profileId != null) {
      // notificaciones_app incluye cuota_nueva, pago_aprobado y pago_rechazado.
      _notificationsChannel = _client
          .channel('edupago-cal-$channelKey-notas-$profileId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notificaciones_app',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'perfil_id',
              value: profileId,
            ),
            callback: (_) => onChanged(),
          )
          .subscribe();
    }
  }

  @override
  void stopListening() {
    final payments = _paymentsChannel;
    final notes = _notificationsChannel;
    _paymentsChannel = null;
    _notificationsChannel = null;
    if (payments != null) {
      _client.removeChannel(payments);
    }
    if (notes != null) {
      _client.removeChannel(notes);
    }
  }

  @override
  Future<CalendarLoadResult> loadEvents({
    required String representativeId,
    required List<CalendarStudent> students,
  }) async {
    final repId = representativeId.trim();
    if (repId.isEmpty) {
      return const CalendarLoadResult(
        events: [],
        warnings: ['No se encontró el representante autenticado.'],
        hasSuccessfulSource: false,
      );
    }

    final events = <CalendarEvent>[];
    final warnings = <String>[];
    var successfulSources = 0;

    final studentsById = <String, String>{
      for (final student in students)
        if (student.id.isNotEmpty) student.id: student.name,
    };
    final studentIds = studentsById.keys.toList();

    if (studentIds.isNotEmpty) {
      try {
        final quotas = <Map<String, dynamic>>[];
        for (var i = 0; i < studentIds.length; i += 80) {
          final rows = await _client
              .from('cuotas')
              .select('id,estudiante_id,concepto_id,concepto,periodo,monto_usd,creado_at,fecha_vencimiento')
              .inFilter('estudiante_id', studentIds.skip(i).take(80).toList())
              .limit(3000);
          quotas.addAll(rows.map((row) => Map<String, dynamic>.from(row)));
        }

        final conceptIds = quotas
            .map((quota) => (quota['concepto_id'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        final conceptNames = <String, String>{};
        for (var i = 0; i < conceptIds.length; i += 80) {
          try {
            final rows = await _client
                .from('conceptos_cobro')
                .select('id,nombre')
                .inFilter('id', conceptIds.skip(i).take(80).toList());
            for (final row in rows) {
              conceptNames[(row['id'] ?? '').toString()] =
                  (row['nombre'] ?? '').toString();
            }
          } catch (error) {
            // La descripción es opcional: las fechas siguen disponibles.
            debugPrint('Calendario: concepto no disponible: $error');
          }
        }

        for (final quota in quotas) {
          final id = (quota['id'] ?? '').toString();
          final studentId = (quota['estudiante_id'] ?? '').toString();
          final student = studentsById[studentId] ?? 'Estudiante';
          final period = (quota['periodo'] ?? '').toString().trim();
          final direct = (quota['concepto'] ?? '').toString().trim();
          final concept = direct.isNotEmpty
              ? direct
              : (conceptNames[(quota['concepto_id'] ?? '').toString()] ?? 'Cuota escolar');
          final description = period.isEmpty ? concept : '$concept · $period';
          final amount = _currency(quota['monto_usd'], 'USD');
          final created = _readDate(quota['creado_at']);
          final due = _readDate(quota['fecha_vencimiento']);

          if (created != null) {
            events.add(CalendarEvent(
              id: 'quota-$id-generated',
              date: created,
              kind: CalendarEventKind.generated,
              title: 'Nueva cuota generada',
              details: '$description · $student',
              amount: amount,
              studentId: studentId,
            ));
          }
          if (due != null) {
            events.add(CalendarEvent(
              id: 'quota-$id-due',
              date: due,
              kind: CalendarEventKind.due,
              title: 'Vencimiento de cuota',
              details: '$description · $student',
              amount: amount,
              studentId: studentId,
            ));
          }
        }
        successfulSources++;
      } catch (error) {
        warnings.add('No se pudieron consultar las cuotas. Revisa la conexión y los permisos.');
        debugPrint('Calendario: error consultando cuotas: $error');
      }
    } else {
      warnings.add('Todavía no hay estudiantes vinculados para consultar cuotas.');
    }

    try {
      final rows = await _client
          .from('pagos')
          .select('id,representante_id,monto,moneda,referencia,fecha_pago,estado,revisado_at,creado_at')
          .eq('representante_id', repId)
          .order('creado_at', ascending: false)
          .limit(1000);
      final payments = rows.map((row) => Map<String, dynamic>.from(row)).toList();
      final notificationsByPayment = <String, List<Map<String, dynamic>>>{};
      final profileId = _client.auth.currentUser?.id;
      if (profileId != null) {
        try {
          final notifications = await _client
              .from('notificaciones_app')
              .select('tipo,datos,creada_at')
              .eq('perfil_id', profileId)
              .order('creada_at', ascending: false)
              .limit(1000);
          for (final raw in notifications) {
            final note = Map<String, dynamic>.from(raw);
            final data = note['datos'];
            if (data is! Map) {
              continue;
            }
            final metadata = Map<String, dynamic>.from(data);
            final paymentId = _paymentIdFromNotification(metadata);
            if (paymentId == null) {
              continue;
            }
            notificationsByPayment.putIfAbsent(paymentId, () => []).add(note);
          }
        } catch (error) {
          debugPrint('Calendario: notificaciones no disponibles: $error');
        }
      }

      for (final payment in payments) {
        final id = (payment['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        final status = _status((payment['estado'] ?? '').toString());
        final reference = (payment['referencia'] ?? '').toString().trim();
        final description = reference.isEmpty ? 'Pago escolar' : 'Referencia $reference';
        final amount = _currency(payment['monto'], (payment['moneda'] ?? '').toString().toUpperCase());
        final paid = _readDate(payment['fecha_pago']);
        final reported = _readDate(payment['creado_at']);
        final reviewed = _readDate(payment['revisado_at']);

        if (paid != null) {
          events.add(CalendarEvent(
            id: 'payment-$id-paid',
            date: paid,
            kind: CalendarEventKind.paid,
            title: 'Pago realizado',
            details: description,
            amount: amount,
            paymentId: id,
            pending: status == 'pendiente',
          ));
        }
        if (reported != null) {
          events.add(CalendarEvent(
            id: 'payment-$id-reported',
            date: reported,
            kind: CalendarEventKind.reported,
            title: 'Pago reportado',
            details: '$description · ${_statusLabel(status)}',
            amount: amount,
            paymentId: id,
            pending: status == 'pendiente',
          ));
        }

        if (status == 'aprobado' || status == 'rechazado') {
          final kind = status == 'aprobado'
              ? CalendarEventKind.approved
              : CalendarEventKind.rejected;
          DateTime? effectiveDate = reviewed;
          var fromNotification = false;
          if (effectiveDate == null) {
            final matchingType = status == 'aprobado' ? 'pago_aprobado' : 'pago_rechazado';
            for (final notification in notificationsByPayment[id] ?? const <Map<String, dynamic>>[]) {
              if (notification['tipo']?.toString() != matchingType) {
                continue;
              }
              effectiveDate = _readDate(notification['creada_at']);
              fromNotification = effectiveDate != null;
              if (effectiveDate != null) {
                break;
              }
            }
          }
          if (effectiveDate != null) {
            events.add(CalendarEvent(
              id: 'payment-$id-${fromNotification ? 'notification-' : ''}review',
              date: effectiveDate,
              kind: kind,
              title: status == 'aprobado' ? 'Pago aprobado' : 'Pago rechazado',
              details: description,
              amount: amount,
              paymentId: id,
            ));
          }
        }
      }
      successfulSources++;
    } catch (error) {
      warnings.add('No se pudieron cargar los pagos. Revisa la conexión y los permisos.');
      debugPrint('Calendario: error consultando pagos: $error');
    }

    events.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      return cmp != 0 ? cmp : a.title.compareTo(b.title);
    });
    return CalendarLoadResult(
      events: List.unmodifiable(events),
      warnings: List.unmodifiable(warnings),
      hasSuccessfulSource: successfulSources > 0,
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return null;
    }
    // DATE en PostgreSQL es fecha civil sin zona horaria.
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return parsed.toLocal();
  }

  static String? _currency(Object? amount, String currency) {
    if (amount == null) {
      return null;
    }
    final value = amount is num ? amount.toDouble() : double.tryParse(amount.toString());
    if (value == null) {
      return null;
    }
    final number = value.toStringAsFixed(2).replaceAll('.', ',');
    return currency.isEmpty ? number : '$number $currency';
  }

  static String _status(String raw) {
    final status = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (['aprobado', 'aprobada', 'validado', 'confirmado'].contains(status)) {
      return 'aprobado';
    }
    if (['rechazado', 'rechazada', 'denegado', 'invalidado'].contains(status)) {
      return 'rechazado';
    }
    if (['pendiente', 'reportado', 'en_revision', 'en_espera', 'espera'].contains(status)) {
      return 'pendiente';
    }
    return status;
  }

  static String _statusLabel(String status) => switch (status) {
        'aprobado' => 'Aprobado',
        'rechazado' => 'Rechazado',
        'pendiente' => 'En revisión',
        _ => 'Estado no disponible',
      };

  static String? _paymentIdFromNotification(Map<String, dynamic> metadata) {
    final id = metadata['pago_id'] ?? metadata['id_pago'] ?? metadata['payment_id'];
    if (id != null && id.toString().trim().isNotEmpty) {
      return id.toString();
    }
    final nested = metadata['pago'];
    if (nested is Map && nested['id'] != null) {
      return nested['id'].toString();
    }
    return null;
  }
}
