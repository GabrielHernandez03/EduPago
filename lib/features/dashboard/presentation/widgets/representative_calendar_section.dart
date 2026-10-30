import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';

/// Calendario de movimientos y cuotas del representante.
/// Ruta: lib/features/dashboard/presentation/widgets/representative_calendar_section.dart
///
/// Nunca genera movimientos ficticios. Lee exclusivamente los registros a los
/// que el representante tiene acceso en Supabase (incluyendo las políticas RLS).
class RepresentativeCalendarSection extends StatefulWidget {
  const RepresentativeCalendarSection({
    super.key,
    required this.representativeId,
    required this.students,
    this.onOpenPayment,
  });

  final String representativeId;
  final List<Map<String, dynamic>> students;
  final ValueChanged<String?>? onOpenPayment;

  @override
  State<RepresentativeCalendarSection> createState() =>
      _RepresentativeCalendarSectionState();
}

enum _EventKind { generated, due, paid, reported, approved, rejected }

class _CalendarEvent {
  const _CalendarEvent({
    required this.id,
    required this.date,
    required this.kind,
    required this.title,
    required this.details,
    this.amount,
    this.studentId,
    this.paymentId,
    this.pending = false,
  });

  final String id;
  final DateTime date;
  final _EventKind kind;
  final String title;
  final String details;
  final String? amount;
  final String? studentId;
  final String? paymentId;
  final bool pending;
}

class _RepresentativeCalendarSectionState
    extends State<RepresentativeCalendarSection> {
  static const _navy = AppColors.darkNavy;
  static const _muted = AppColors.textMuted;
  static const _blue = AppColors.primaryBlue;
  static const _border = AppColors.cardBorder;
  static const _green = Color(0xFF087C59);
  static const _orange = Color(0xFF9C5A05);
  static const _red = Color(0xFFC32D43);
  static const _violet = Color(0xFF6C46C5);
  static const _bg = Color(0xFFF8FAFC);

  static const _months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  static const _weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  late DateTime _month;
  late DateTime _selected;
  String _filter = 'Todos';
  String _studentFilter = '';
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<String> _warnings = [];
  List<_CalendarEvent> _events = [];
  int _loadSerial = 0;
  Timer? _reloadDelay;
  RealtimeChannel? _paymentsChannel;
  RealtimeChannel? _noticesChannel;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _month = DateTime(today.year, today.month);
    _selected = today;
    _listen();
    _load();
  }

  @override
  void didUpdateWidget(covariant RepresentativeCalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousIds = oldWidget.students.map((s) => '${s['id']}').join('|');
    final nextIds = widget.students.map((s) => '${s['id']}').join('|');
    if (oldWidget.representativeId != widget.representativeId ||
        previousIds != nextIds) {
      _stopListening();
      _studentFilter = '';
      _events = [];
      _listen();
      _load();
    }
  }

  @override
  void dispose() {
    _reloadDelay?.cancel();
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    final client = Supabase.instance.client;
    if (_paymentsChannel != null) client.removeChannel(_paymentsChannel!);
    if (_noticesChannel != null) client.removeChannel(_noticesChannel!);
    _paymentsChannel = null;
    _noticesChannel = null;
  }

  void _scheduleReload() {
    _reloadDelay?.cancel();
    _reloadDelay = Timer(const Duration(milliseconds: 550), () {
      if (mounted) _load(silent: true);
    });
  }

  void _listen() {
    final rep = widget.representativeId.trim();
    if (rep.isEmpty) return;
    final client = Supabase.instance.client;
    _paymentsChannel = client
        .channel('calendario-pagos-$rep')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pagos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'representante_id',
            value: rep,
          ),
          callback: (_) => _scheduleReload(),
        )
        .subscribe();
    final uid = client.auth.currentUser?.id;
    if (uid != null) {
      _noticesChannel = client
          .channel('calendario-notificaciones-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notificaciones_app',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'perfil_id',
              value: uid,
            ),
            callback: (_) => _scheduleReload(),
          )
          .subscribe();
    }
  }

  static String _first(Map<String, dynamic> row, List<String> names) {
    for (final name in names) {
      final value = row[name]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  static DateTime? _date(Map<String, dynamic> row, List<String> names) {
    for (final name in names) {
      final value = row[name]?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      // Los campos SQL DATE representan un día local, no un instante UTC.
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        final d = DateTime.tryParse(value);
        if (d != null) return DateTime(d.year, d.month, d.day);
      } else {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toLocal();
      }
    }
    return null;
  }

  static String _normalStatus(String value) {
    final v = value.trim().toLowerCase().replaceAll(' ', '_');
    if (['aprobado', 'aprobada', 'validado', 'confirmado'].contains(v)) {
      return 'aprobado';
    }
    if (['rechazado', 'rechazada', 'denegado', 'invalidado'].contains(v)) {
      return 'rechazado';
    }
    if ([
      'pendiente',
      'reportado',
      'en_revision',
      'en_espera',
      'espera',
    ].contains(v))
      return 'pendiente';
    return v;
  }

  static String _statusLabel(String value) => switch (value) {
    'aprobado' => 'Aprobado',
    'rechazado' => 'Rechazado',
    'pendiente' => 'En revisión',
    _ => 'Estado no disponible',
  };

  static String? _amount(Map<String, dynamic> row, {bool cuota = false}) {
    final raw = cuota
        ? _first(row, ['monto_usd', 'monto', 'importe_usd', 'total_usd'])
        : _first(row, ['monto', 'monto_usd_equivalente']);
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null) return null;
    final currency = cuota
        ? (_first(row, ['monto_usd', 'importe_usd', 'total_usd']).isNotEmpty
              ? 'USD'
              : _first(row, ['moneda']).toUpperCase())
        : _first(row, ['moneda']).toUpperCase();
    final number = value.toStringAsFixed(2).replaceAll('.', ',');
    return currency.isEmpty ? number : '$number $currency';
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _formatTime(DateTime d) =>
      d.hour == 0 && d.minute == 0 && d.second == 0
      ? 'Fecha'
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) => DateUtils.isSameDay(a, b);

  static String? _notificationPaymentId(Map<String, dynamic> data) {
    final raw = _first(data, ['pago_id', 'id_pago', 'payment_id']);
    if (raw.isNotEmpty) return raw;
    final nested = data['pago'];
    if (nested is Map) {
      final v = nested['id']?.toString().trim() ?? '';
      return v.isNotEmpty ? v : null;
    }
    return null;
  }

  Future<void> _load({bool silent = false}) async {
    final serial = ++_loadSerial;
    final representativeId = widget.representativeId.trim();
    if (mounted) {
      setState(() {
        _loading = !silent && _events.isEmpty;
        _refreshing = silent;
        _error = null;
      });
    }
    if (representativeId.isEmpty) {
      if (mounted)
        setState(() {
          _loading = false;
          _refreshing = false;
          _error = 'No se encontró el representante autenticado.';
        });
      return;
    }

    final client = Supabase.instance.client;
    final events = <_CalendarEvent>[];
    final warnings = <String>[];
    var successfulSources = 0;

    final studentNames = <String, String>{};
    final studentIds = <String>[];
    for (final row in widget.students) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      studentIds.add(id);
      studentNames[id] = '${row['nombres'] ?? ''} ${row['apellidos'] ?? ''}'
          .trim();
    }

    // Cuotas: fechas de generación y vencimiento. No se confunden con pagos.
    if (studentIds.isNotEmpty) {
      try {
        final quotas = <Map<String, dynamic>>[];
        for (var i = 0; i < studentIds.length; i += 80) {
          final slice = studentIds.skip(i).take(80).toList();
          final rows = await client
              .from('cuotas')
              .select('*')
              .inFilter('estudiante_id', slice)
              .limit(3000);
          quotas.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
        }
        final conceptIds = quotas
            .map((q) => q['concepto_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        final conceptNames = <String, String>{};
        for (var i = 0; i < conceptIds.length; i += 80) {
          try {
            final rows = await client
                .from('conceptos_cobro')
                .select('*')
                .inFilter('id', conceptIds.skip(i).take(80).toList());
            for (final raw in rows) {
              final row = Map<String, dynamic>.from(raw);
              final id = row['id']?.toString() ?? '';
              conceptNames[id] = _first(row, [
                'nombre',
                'nombre_concepto',
                'titulo',
                'descripcion',
                'concepto',
              ]);
            }
          } catch (_) {
            // Los nombres opcionales no impiden mostrar las fechas de cuotas.
          }
        }
        for (final quota in quotas) {
          final id = quota['id']?.toString() ?? '';
          final studentId = quota['estudiante_id']?.toString() ?? '';
          final student = studentNames[studentId] ?? 'Estudiante';
          final period = _first(quota, ['periodo', 'mes', 'nombre_cuota']);
          final direct = _first(quota, ['concepto', 'nombre_concepto']);
          final concept = direct.isNotEmpty
              ? direct
              : (conceptNames[quota['concepto_id']?.toString() ?? ''] ??
                    'Cuota escolar');
          final title = period.isEmpty ? concept : '$concept · $period';
          final amount = _amount(quota, cuota: true);
          final created = _date(quota, [
            'creado_at',
            'created_at',
            'fecha_creacion',
            'fecha_generacion',
          ]);
          final due = _date(quota, [
            'fecha_vencimiento',
            'vence_at',
            'vencimiento',
          ]);
          if (created != null) {
            events.add(
              _CalendarEvent(
                id: 'quota-$id-generated',
                date: created,
                kind: _EventKind.generated,
                title: 'Nueva cuota generada',
                details: '$title · $student',
                amount: amount,
                studentId: studentId,
              ),
            );
          }
          if (due != null) {
            events.add(
              _CalendarEvent(
                id: 'quota-$id-due',
                date: due,
                kind: _EventKind.due,
                title: 'Vencimiento de cuota',
                details: '$title · $student',
                amount: amount,
                studentId: studentId,
              ),
            );
          }
        }
        successfulSources++;
      } catch (e) {
        warnings.add(
          'No se pudieron consultar las cuotas. Revisa los permisos de lectura de la tabla cuotas.',
        );
        debugPrint('Calendario: error consultando cuotas: $e');
      }
    } else {
      warnings.add(
        'Todavía no hay estudiantes vinculados para consultar cuotas.',
      );
    }

    // Pagos y movimientos. El estado actual nunca implica una fecha histórica.
    try {
      final rows = await client
          .from('pagos')
          .select('*')
          .eq('representante_id', representativeId)
          .order('creado_at', ascending: false)
          .limit(1000);
      final payments = rows.map((r) => Map<String, dynamic>.from(r)).toList();

      // Notificaciones son evidencia alternativa de la fecha de aprobación o
      // rechazo cuando no existe una marca temporal de revisión en pagos.
      final notificationDates = <String, List<Map<String, dynamic>>>{};
      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        try {
          final notes = await client
              .from('notificaciones_app')
              .select('tipo, datos, creada_at')
              .eq('perfil_id', uid)
              .order('creada_at', ascending: false)
              .limit(1000);
          for (final raw in notes) {
            final note = Map<String, dynamic>.from(raw);
            final data = note['datos'];
            if (data is! Map) continue;
            final id = _notificationPaymentId(Map<String, dynamic>.from(data));
            if (id == null) continue;
            notificationDates.putIfAbsent(id, () => []).add(note);
          }
        } catch (e) {
          debugPrint('Calendario: notificaciones no disponibles: $e');
        }
      }

      for (final p in payments) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final status = _normalStatus(_first(p, ['estado', 'status']));
        final reference = _first(p, [
          'referencia',
          'referencia_pago',
          'referencia_bancaria',
          'numero_referencia',
          'nro_referencia',
        ]);
        final amount = _amount(p);
        final details = reference.isNotEmpty
            ? 'Referencia $reference'
            : 'Pago escolar';
        final paid = _date(p, ['fecha_pago']);
        final reported = _date(p, ['creado_at', 'created_at']);
        final reviewed = _date(p, [
          'revisado_at',
          'fecha_revision',
          'aprobado_at',
          'rechazado_at',
        ]);

        if (paid != null) {
          events.add(
            _CalendarEvent(
              id: 'payment-$id-paid',
              date: paid,
              kind: _EventKind.paid,
              title: 'Pago realizado',
              details: details,
              amount: amount,
              paymentId: id,
              pending: status == 'pendiente',
            ),
          );
        }
        if (reported != null) {
          events.add(
            _CalendarEvent(
              id: 'payment-$id-reported',
              date: reported,
              kind: _EventKind.reported,
              title: 'Pago reportado',
              details: '$details · ${_statusLabel(status)}',
              amount: amount,
              paymentId: id,
              pending: status == 'pendiente',
            ),
          );
        }

        // Si la tabla de pagos tiene fecha de revisión, se prioriza para el
        // estado actual. Nunca se usa actualizado_at: puede ser otro cambio.
        if (status == 'aprobado' || status == 'rechazado') {
          final kind = status == 'aprobado'
              ? _EventKind.approved
              : _EventKind.rejected;
          if (reviewed != null) {
            events.add(
              _CalendarEvent(
                id: 'payment-$id-review',
                date: reviewed,
                kind: kind,
                title: status == 'aprobado'
                    ? 'Pago aprobado'
                    : 'Pago rechazado',
                details: details,
                amount: amount,
                paymentId: id,
              ),
            );
          } else {
            // Se usa la notificación solo si coincide por ID y por estado.
            final expectedType = status == 'aprobado'
                ? 'pago_aprobado'
                : 'pago_rechazado';
            final note = (notificationDates[id] ?? [])
                .where((n) => n['tipo']?.toString() == expectedType)
                .toList();
            if (note.isNotEmpty) {
              final date = _date(note.first, ['creada_at']);
              if (date != null) {
                events.add(
                  _CalendarEvent(
                    id: 'payment-$id-notification-review',
                    date: date,
                    kind: kind,
                    title: status == 'aprobado'
                        ? 'Pago aprobado'
                        : 'Pago rechazado',
                    details: details,
                    amount: amount,
                    paymentId: id,
                  ),
                );
              }
            }
          }
        }
      }
      successfulSources++;
    } catch (e) {
      warnings.add(
        'No se pudieron cargar los pagos. Comprueba el acceso a la tabla pagos.',
      );
      debugPrint('Calendario: error consultando pagos: $e');
    }

    if (!mounted || serial != _loadSerial) return;
    events.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      return cmp != 0 ? cmp : a.title.compareTo(b.title);
    });
    setState(() {
      _events = events;
      _warnings = warnings;
      _loading = false;
      _refreshing = false;
      _error = successfulSources == 0
          ? 'No pudimos cargar el calendario. Comprueba tu conexión o inténtalo de nuevo.'
          : null;
    });
  }

  Color _tone(_EventKind kind) => switch (kind) {
    _EventKind.generated => _blue,
    _EventKind.due => _orange,
    _EventKind.paid => _violet,
    _EventKind.reported => _blue,
    _EventKind.approved => _green,
    _EventKind.rejected => _red,
  };

  IconData _icon(_EventKind kind) => switch (kind) {
    _EventKind.generated => Icons.add_circle_outline_rounded,
    _EventKind.due => Icons.event_busy_outlined,
    _EventKind.paid => Icons.payments_outlined,
    _EventKind.reported => Icons.receipt_long_outlined,
    _EventKind.approved => Icons.check_circle_outline_rounded,
    _EventKind.rejected => Icons.cancel_outlined,
  };

  bool _matches(_CalendarEvent e) {
    // Un pago familiar sin estudiante identificable NO se atribuye a un hijo.
    if (_studentFilter.isNotEmpty && e.studentId != _studentFilter)
      return false;
    if (_filter == 'Cuotas') {
      return e.kind == _EventKind.generated || e.kind == _EventKind.due;
    }
    if (_filter == 'Pagos') {
      return e.kind != _EventKind.generated && e.kind != _EventKind.due;
    }
    if (_filter == 'Aprobados') return e.kind == _EventKind.approved;
    if (_filter == 'Rechazados') return e.kind == _EventKind.rejected;
    if (_filter == 'En revisión')
      return e.kind == _EventKind.reported && e.pending;
    return true;
  }

  List<_CalendarEvent> get _filtered => _events.where(_matches).toList();

  void _moveMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _selected = DateTime(_month.year, _month.month, 1);
    });
  }

  void _goToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _month = DateTime(today.year, today.month);
      _selected = today;
    });
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    border: Border.all(color: _border),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF1B4785).withValues(alpha: 0.025),
        blurRadius: 18,
        offset: const Offset(0, 4),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final inset = width < 640
        ? 18.0
        : width < 900
        ? 28.0
        : 48.0;
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      color: _blue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(inset, 24, inset, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1250),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 20),
                if (_loading) ...[
                  const SizedBox(
                    height: 190,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ] else if (_error != null) ...[
                  _notice(_error!, isError: true, retry: true),
                ] else ...[
                  if (_warnings.isNotEmpty) ...[
                    for (final warning in _warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _notice(warning),
                      ),
                    const SizedBox(height: 8),
                  ],
                  _summary(),
                  const SizedBox(height: 22),
                  _filters(),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 830) {
                        return Column(
                          children: [
                            _calendar(),
                            const SizedBox(height: 18),
                            _agenda(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: _calendar()),
                          const SizedBox(width: 18),
                          Expanded(flex: 5, child: _agenda()),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => LayoutBuilder(
    builder: (context, c) {
      final headerText = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calendario',
            style: TextStyle(
              color: _navy,
              fontSize: 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Consulta tus cuotas, pagos y fechas importantes en un solo lugar.',
            style: TextStyle(color: _muted, fontSize: 13.5, height: 1.4),
          ),
        ],
      );
      final refresh = OutlinedButton.icon(
        onPressed: _refreshing ? null : () => _load(silent: true),
        icon: _refreshing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Actualizar'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _navy,
          side: const BorderSide(color: _border),
          minimumSize: const Size(132, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
      );
      return c.maxWidth < 570
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [headerText, const SizedBox(height: 14), refresh],
            )
          : Row(
              children: [
                Expanded(child: headerText),
                refresh,
              ],
            );
    },
  );

  Widget _notice(
    String message, {
    bool isError = false,
    bool retry = false,
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isError ? const Color(0xFFFFF1F2) : const Color(0xFFFFFAEB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isError ? const Color(0xFFFACAD0) : const Color(0xFFEAD8B5),
      ),
    ),
    child: Row(
      children: [
        Icon(
          isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          size: 20,
          color: isError ? _red : _orange,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _navy, fontSize: 12.5, height: 1.45),
          ),
        ),
        if (retry)
          TextButton(onPressed: () => _load(), child: const Text('Reintentar')),
      ],
    ),
  );

  Widget _summary() {
    final today = DateUtils.dateOnly(DateTime.now());
    final upcoming = _events
        .where(
          (e) =>
              e.kind == _EventKind.due &&
              !DateUtils.dateOnly(e.date).isBefore(today),
        )
        .length;
    final pending = _events
        .where((e) => e.kind == _EventKind.reported && e.pending)
        .length;
    final thisMonth = _events
        .where(
          (e) => e.date.month == _month.month && e.date.year == _month.year,
        )
        .length;
    return LayoutBuilder(
      builder: (context, c) {
        final cards = [
          _summaryCard(
            'Eventos del mes',
            '$thisMonth',
            Icons.calendar_month_rounded,
            _blue,
            const Color(0xFFF0F5FF),
          ),
          _summaryCard(
            'Vencimientos próximos',
            '$upcoming',
            Icons.event_rounded,
            _orange,
            const Color(0xFFFFF8ED),
          ),
          _summaryCard(
            'Pagos en revisión',
            '$pending',
            Icons.hourglass_bottom_rounded,
            _violet,
            const Color(0xFFF6F2FF),
          ),
        ];
        if (c.maxWidth < 590) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                cards[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _summaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color tint,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
    decoration: _cardDecoration(),
    child: Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 2,
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filters() => LayoutBuilder(
    builder: (context, c) {
      final typeFilters = [
        'Todos',
        'Cuotas',
        'Pagos',
        'Aprobados',
        'Rechazados',
        'En revisión',
      ];
      final types = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final filter in typeFilters)
            ChoiceChip(
              label: Text(filter),
              selected: filter == _filter,
              onSelected: (_) => setState(() => _filter = filter),
              showCheckmark: false,
              labelStyle: TextStyle(
                color: filter == _filter ? _blue : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              selectedColor: const Color(0xFFEBF3FF),
              backgroundColor: Colors.white,
              side: BorderSide(color: filter == _filter ? _blue : _border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
        ],
      );
      if (widget.students.length < 2) return types;
      final studentPicker = DropdownButtonFormField<String>(
        value: _studentFilter,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Estudiante',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Toda mi familia')),
          for (final student in widget.students)
            DropdownMenuItem(
              value: student['id']?.toString() ?? '',
              child: Text(
                '${student['nombres'] ?? ''} ${student['apellidos'] ?? ''}'
                    .trim(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) => setState(() => _studentFilter = value ?? ''),
      );
      return c.maxWidth < 930
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                types,
                const SizedBox(height: 12),
                SizedBox(height: 55, child: studentPicker),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: types),
                const SizedBox(width: 12),
                SizedBox(width: 240, height: 55, child: studentPicker),
              ],
            );
    },
  );

  Widget _calendar() {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final offset = firstDay.weekday - 1;
    final count = DateUtils.getDaysInMonth(_month.year, _month.month);
    final totalCells = ((offset + count + 6) ~/ 7) * 7;
    final shownEvents = _filtered;
    final today = DateUtils.dateOnly(DateTime.now());
    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.fromLTRB(17, 18, 17, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_months[_month.month - 1][0].toUpperCase()}${_months[_month.month - 1].substring(1)} ${_month.year}',
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(onPressed: _goToday, child: const Text('Hoy')),
              IconButton(
                onPressed: () => _moveMonth(-1),
                tooltip: 'Mes anterior',
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                onPressed: () => _moveMonth(1),
                tooltip: 'Mes siguiente',
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 40,
              crossAxisSpacing: 5,
            ),
            itemCount: 7,
            itemBuilder: (context, index) => Center(
              child: Text(
                _weekdays[index],
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 66,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
            ),
            itemCount: totalCells,
            itemBuilder: (context, i) {
              final dayNumber = i - offset + 1;
              if (dayNumber < 1 || dayNumber > count) return const SizedBox();
              final day = DateTime(_month.year, _month.month, dayNumber);
              final events = shownEvents
                  .where((e) => _sameDay(e.date, day))
                  .toList();
              final selected = _sameDay(day, _selected);
              final isToday = _sameDay(day, today);
              final kinds = events.map((e) => e.kind).toSet().take(4).toList();
              final label =
                  '${_formatDate(day)}, ${events.length} '
                  '${events.length == 1 ? 'evento' : 'eventos'}';
              return Semantics(
                button: true,
                selected: selected,
                label: label,
                child: Tooltip(
                  message: label,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    child: InkWell(
                      onTap: () => setState(() => _selected = day),
                      borderRadius: BorderRadius.circular(11),
                      hoverColor: const Color(0xFFEEF4FF),
                      child: AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        padding: const EdgeInsets.only(top: 6, bottom: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          color: selected
                              ? const Color(0xFFEAF2FF)
                              : isToday
                              ? const Color(0xFFF5F8FC)
                              : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? _blue
                                : isToday
                                ? const Color(0xFFBACBE5)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                color: selected ? _blue : _navy,
                                fontWeight: selected || isToday
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (final kind in kinds) ...[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _tone(kind),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 14),
          Wrap(
            spacing: 15,
            runSpacing: 12,
            children: [
              _legend('Cuota nueva', _blue),
              _legend('Vencimiento', _orange),
              _legend('Pago realizado', _violet),
              _legend('Aprobado', _green),
              _legend('Rechazado', _red),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'El calendario muestra las fechas registradas; para comprobar el saldo pendiente consulta Estado de cuenta.',
            style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
    ],
  );

  Widget _agenda() {
    final selected = _filtered
        .where((e) => _sameDay(e.date, _selected))
        .toList();
    final today = DateUtils.dateOnly(DateTime.now());
    final upcoming = _filtered
        .where(
          (e) =>
              e.kind == _EventKind.due &&
              !DateUtils.dateOnly(e.date).isBefore(today),
        )
        .take(4)
        .toList();
    upcoming.sort((a, b) => a.date.compareTo(b.date));
    final recent =
        _filtered
            .where(
              (e) => e.kind != _EventKind.due && e.kind != _EventKind.generated,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_note_rounded, color: _blue),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Agenda del día',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _formatDate(_selected),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '${selected.length}',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (selected.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.event_available_outlined, color: _muted, size: 28),
                  SizedBox(height: 7),
                  Text(
                    'Sin movimientos en esta fecha',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Selecciona otro día para consultar sus eventos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          for (final event in selected)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _eventRow(event),
            ),
          const SizedBox(height: 20),
          const Divider(color: _border, height: 1),
          const SizedBox(height: 17),
          const Text(
            'Próximos vencimientos',
            style: TextStyle(
              color: _navy,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          if (upcoming.isEmpty)
            const Text(
              'No hay vencimientos próximos registrados.',
              style: TextStyle(color: _muted, fontSize: 12.5),
            ),
          for (final event in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _eventRow(event, showDate: true),
            ),
          const SizedBox(height: 13),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 17),
          const Text(
            'Actividad de pagos reciente',
            style: TextStyle(
              color: _navy,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            const Text(
              'No hay movimientos de pago registrados.',
              style: TextStyle(color: _muted, fontSize: 12.5),
            ),
          for (final event in recent.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _eventRow(event, showDate: true),
            ),
          if (widget.onOpenPayment != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => widget.onOpenPayment?.call(null),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('Ver historial de pagos'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _eventRow(_CalendarEvent event, {bool showDate = false}) {
    final color = _tone(event.kind);
    final isPayment = event.paymentId != null && widget.onOpenPayment != null;
    void openEvent() {
      if (isPayment) {
        widget.onOpenPayment?.call(event.paymentId);
      } else {
        setState(() {
          _selected = DateUtils.dateOnly(event.date);
          _month = DateTime(event.date.year, event.date.month);
        });
      }
    }

    final trailing = showDate
        ? _formatDate(event.date)
        : _formatTime(event.date);
    return Material(
      color: color.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: openEvent,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: color.withValues(alpha: 0.14)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon(event.kind), size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 12.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      event.details,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.4,
                        height: 1.45,
                      ),
                    ),
                    if (event.amount != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.amount!,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.7,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailing,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vista compacta del calendario para la portada del representante.
/// Consulta solo registros existentes en Supabase; no dibuja eventos ficticios.
/// Una pulsación en cualquier punto de la tarjeta abre el calendario completo.
class RepresentativeCalendarPreview extends StatefulWidget {
  const RepresentativeCalendarPreview({
    super.key,
    required this.representativeId,
    required this.students,
    required this.onOpenCalendar,
  });

  final String representativeId;
  final List<Map<String, dynamic>> students;
  final VoidCallback onOpenCalendar;

  @override
  State<RepresentativeCalendarPreview> createState() =>
      _RepresentativeCalendarPreviewState();
}

class _PreviewEvent {
  const _PreviewEvent(this.date, this.color, this.isDue);
  final DateTime date;
  final Color color;
  final bool isDue;
}

class _RepresentativeCalendarPreviewState
    extends State<RepresentativeCalendarPreview> {
  static const _blue = AppColors.primaryBlue;
  static const _green = Color(0xFF059669);
  static const _orange = Color(0xFFB76C0A);
  static const _red = Color(0xFFDC2626);
  static const _violet = Color(0xFF6D28D9);
  // Color exclusivo del mini calendario de Inicio. Los marcadores de eventos
  // conservan sus colores de estado y tipo.
  static const _accent = AppColors.primaryBlue;
  static const _months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  List<_PreviewEvent> _events = const [];
  bool _loading = true;
  bool _failed = false;
  int _request = 0;
  RealtimeChannel? _paymentsChannel;
  Timer? _reloadTimer;

  @override
  void initState() {
    super.initState();
    _listenPayments();
    _load();
  }

  @override
  void didUpdateWidget(covariant RepresentativeCalendarPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.students.map((s) => '${s['id']}').join(',');
    final newIds = widget.students.map((s) => '${s['id']}').join(',');
    if (oldWidget.representativeId != widget.representativeId ||
        oldIds != newIds) {
      _stopListening();
      _listenPayments();
      _load();
    }
  }

  @override
  void dispose() {
    ++_request;
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    _reloadTimer?.cancel();
    final channel = _paymentsChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    _paymentsChannel = null;
  }

  void _listenPayments() {
    final id = widget.representativeId.trim();
    if (id.isEmpty) return;
    _paymentsChannel = Supabase.instance.client
        .channel('resumen-calendario-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pagos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'representante_id',
            value: id,
          ),
          callback: (_) {
            _reloadTimer?.cancel();
            _reloadTimer = Timer(const Duration(milliseconds: 450), _load);
          },
        )
        .subscribe();
  }

  static DateTime? _readDate(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      final date = DateTime.tryParse(value);
      if (date == null) continue;
      // SQL DATE: preservar el día en lugar de convertirlo a otra zona.
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        return DateTime(date.year, date.month, date.day);
      }
      return date.toLocal();
    }
    return null;
  }

  Future<void> _load() async {
    final id = widget.representativeId.trim();
    final request = ++_request;
    if (id.isEmpty) {
      if (mounted)
        setState(() {
          _events = [];
          _loading = false;
        });
      return;
    }
    final ids = widget.students
        .map((s) => s['id']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final events = <_PreviewEvent>[];
    var successful = 0;
    final client = Supabase.instance.client;

    // Fechas de creación y vencimiento de las cuotas vinculadas.
    if (ids.isNotEmpty) {
      try {
        for (var i = 0; i < ids.length; i += 80) {
          final rows = await client
              .from('cuotas')
              .select('*')
              .inFilter('estudiante_id', ids.skip(i).take(80).toList())
              .limit(3000);
          for (final raw in rows) {
            final cuota = Map<String, dynamic>.from(raw);
            final created = _readDate(cuota, [
              'creado_at',
              'created_at',
              'fecha_creacion',
              'fecha_generacion',
            ]);
            final due = _readDate(cuota, [
              'fecha_vencimiento',
              'vence_at',
              'vencimiento',
            ]);
            if (created != null)
              events.add(_PreviewEvent(created, _blue, false));
            if (due != null) events.add(_PreviewEvent(due, _orange, true));
          }
        }
        successful++;
      } catch (e) {
        debugPrint('Resumen calendario: no se pudieron cargar cuotas: $e');
      }
    }

    // Reportes, pagos realizados y decisiones con fecha de revisión.
    try {
      final rows = await client
          .from('pagos')
          .select('*')
          .eq('representante_id', id)
          .order('creado_at', ascending: false)
          .limit(1000);
      for (final raw in rows) {
        final pago = Map<String, dynamic>.from(raw);
        final state = (pago['estado'] ?? pago['status'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        final paid = _readDate(pago, ['fecha_pago']);
        final reported = _readDate(pago, ['creado_at', 'created_at']);
        final reviewed = _readDate(pago, [
          'revisado_at',
          'fecha_revision',
          'aprobado_at',
          'rechazado_at',
        ]);
        if (paid != null) events.add(_PreviewEvent(paid, _violet, false));
        if (reported != null) events.add(_PreviewEvent(reported, _blue, false));
        // El estado actual no se utiliza como fecha histórica.
        if (reviewed != null) {
          if ([
            'aprobado',
            'aprobada',
            'validado',
            'confirmado',
          ].contains(state)) {
            events.add(_PreviewEvent(reviewed, _green, false));
          } else if ([
            'rechazado',
            'rechazada',
            'denegado',
            'invalidado',
          ].contains(state)) {
            events.add(_PreviewEvent(reviewed, _red, false));
          }
        }
      }
      successful++;
    } catch (e) {
      debugPrint('Resumen calendario: no se pudieron cargar pagos: $e');
    }

    if (!mounted || request != _request) return;
    setState(() {
      _events = events;
      _loading = false;
      _failed = successful == 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final year = today.year;
    final month = today.month;
    final firstDay = DateTime(year, month, 1);
    final offset = firstDay.weekday - 1; // Semanas de lunes a domingo.
    final countDays = DateUtils.getDaysInMonth(year, month);
    final weeks = ((offset + countDays) / 7).ceil();
    final monthEvents = _events
        .where((e) => e.date.year == year && e.date.month == month)
        .toList();
    final nextDue =
        _events
            .where(
              (e) => e.isDue && !DateUtils.dateOnly(e.date).isBefore(today),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final nearestDue = nextDue.isEmpty ? null : nextDue.first.date;
    final monthLabel = _months[month - 1];
    final readableMonth =
        '${monthLabel[0].toUpperCase()}${monthLabel.substring(1)} $year';

    // Tres áreas claras y de altura contenida: encabezado, calendario y
    // aviso inferior. Esta tarjeta no modifica el tamaño de «Próximo pago».
    return _PreviewHoverCard(
      onTap: widget.onOpenCalendar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Encabezado: identificación a la izquierda y acceso a la derecha.
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    size: 19,
                    color: _accent,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mi calendario',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pagos y vencimientos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ver todo',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.arrow_forward_rounded, color: _accent, size: 16),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 2. Área del mes, con días uniformemente alineados en 7 columnas.
            Container(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    readableMonth,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  // Un poco más de aire entre el título del mes y los días.
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final label in const [
                        'L',
                        'M',
                        'M',
                        'J',
                        'V',
                        'S',
                        'D',
                      ])
                        Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  for (var week = 0; week < weeks; week++)
                    Row(
                      children: [
                        for (var weekday = 0; weekday < 7; weekday++)
                          Expanded(
                            child: _dayCell(
                              offsetDay: week * 7 + weekday - offset + 1,
                              maxDay: countDays,
                              today: today,
                              year: year,
                              month: month,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // 3. Información destacada sin competir con el calendario.
            Container(
              constraints: const BoxConstraints(minHeight: 30),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF5FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Icon(
                    nearestDue != null
                        ? Icons.event_available_outlined
                        : Icons.info_outline_rounded,
                    color: _accent,
                    size: 15,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _loading
                          ? 'Consultando movimientos…'
                          : _failed
                          ? 'No se pudieron consultar los eventos'
                          : nearestDue != null
                          ? 'Próximo vencimiento: ${nearestDue.day} de ${_months[nearestDue.month - 1]}'
                          : '${monthEvents.length} eventos registrados este mes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell({
    required int offsetDay,
    required int maxDay,
    required DateTime today,
    required int year,
    required int month,
  }) {
    if (offsetDay < 1 || offsetDay > maxDay) {
      return const SizedBox(height: 21);
    }
    final active = offsetDay == today.day;
    final dayEvents = _events
        .where(
          (e) =>
              e.date.year == year &&
              e.date.month == month &&
              e.date.day == offsetDay,
        )
        .toList();
    final uniqueColors = <Color>[];
    for (final e in dayEvents) {
      if (!uniqueColors.contains(e.color)) uniqueColors.add(e.color);
    }
    // El día ocupa exactamente 21 px. Los contenidos internos deben sumar
    // como máximo esa altura: 16 px del número + 4 px de indicadores.
    // Antes eran 18 + 4 = 22 px y Flutter mostraba
    // "BOTTOM OVERFLOWED BY 1.00 PIXELS" en cada semana.
    return SizedBox(
      height: 21,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 16,
            width: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$offsetDay',
              style: TextStyle(
                color: active ? Colors.white : AppColors.darkNavy,
                fontSize: 10,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            height: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in uniqueColors.take(3))
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    width: 3.5,
                    height: 3.5,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hover discreto como el resto de las tarjetas del dashboard.
class _PreviewHoverCard extends StatefulWidget {
  const _PreviewHoverCard({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PreviewHoverCard> createState() => _PreviewHoverCardState();
}

class _PreviewHoverCardState extends State<_PreviewHoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final noMotion = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: noMotion ? Duration.zero : const Duration(milliseconds: 170),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? AppColors.primaryBlue.withValues(alpha: 0.45)
                : AppColors.cardBorder,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            hoverColor: const Color(0xFFF6F9FF),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
