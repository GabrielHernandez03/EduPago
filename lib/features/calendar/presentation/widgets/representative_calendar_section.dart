import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../data/calendar_repository.dart';
import '../../data/supabase_calendar_repository.dart';
import '../../domain/calendar_event.dart';

import '../../../../core/theme/app_colors.dart';

/// Calendario de movimientos y cuotas del representante.
/// Ruta: lib/features/calendar/presentation/widgets/representative_calendar_section.dart
///
/// Nunca genera movimientos ficticios. Los permisos deben estar protegidos
/// por políticas RLS configuradas en la base de datos.
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
  // Reportar un pago no equivale a que el banco lo haya confirmado.
  // Indigo diferencia el reporte del azul de una cuota nueva.
  static const _indigo = Color(0xFF4355A5);

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

  // Las listas laterales cuentan con scroll propio; sus encabezados no se mueven.
  final ScrollController _dueScrollController = ScrollController();
  final ScrollController _recentScrollController = ScrollController();
  final ScrollController _infoScrollController = ScrollController();
  String _agendaView = 'Todo';

  late DateTime _month;
  late DateTime _selected;
  String _filter = 'Todos';
  String _studentFilter = '';
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<String> _warnings = [];
  List<CalendarEvent> _events = [];
  int _loadSerial = 0;
  Timer? _reloadDelay;
  late final CalendarRepository _repository;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _month = DateTime(today.year, today.month);
    _selected = today;
    _repository = SupabaseCalendarRepository(
      channelKey: 'full-${identityHashCode(this)}',
    );
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
    _dueScrollController.dispose();
    _recentScrollController.dispose();
    _infoScrollController.dispose();
    super.dispose();
  }

  void _stopListening() => _repository.stopListening();

  void _scheduleReload() {
    _reloadDelay?.cancel();
    _reloadDelay = Timer(const Duration(milliseconds: 550), () {
      if (mounted) {
        _load(silent: true);
      }
    });
  }

  void _listen() => _repository.startListening(
    representativeId: widget.representativeId.trim(),
    onChanged: _scheduleReload,
  );

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _formatTime(DateTime d) =>
      d.hour == 0 && d.minute == 0 && d.second == 0
      ? 'Fecha'
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) => DateUtils.isSameDay(a, b);

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
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _error = 'No se encontró el representante autenticado.';
        });
      }
      return;
    }

    try {
      final result = await _repository.loadEvents(
        representativeId: representativeId,
        students: widget.students.map(CalendarStudent.fromMap).toList(),
      );
      if (!mounted || serial != _loadSerial) {
        return;
      }
      setState(() {
        _events = result.events;
        _warnings = result.warnings;
        _loading = false;
        _refreshing = false;
        _error = result.hasSuccessfulSource
            ? null
            : 'No pudimos cargar el calendario. Comprueba tu conexión o inténtalo de nuevo.';
      });
    } catch (error) {
      if (!mounted || serial != _loadSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = 'No pudimos cargar el calendario. Inténtalo de nuevo.';
      });
      debugPrint('Calendario: error de carga: $error');
    }
  }

  Color _tone(CalendarEventKind kind) => switch (kind) {
    CalendarEventKind.generated => _blue,
    CalendarEventKind.due => _orange,
    CalendarEventKind.paid => _violet,
    CalendarEventKind.reported => _indigo,
    CalendarEventKind.approved => _green,
    CalendarEventKind.rejected => _red,
  };

  IconData _icon(CalendarEventKind kind) => switch (kind) {
    CalendarEventKind.generated => Icons.add_circle_outline_rounded,
    CalendarEventKind.due => Icons.event_busy_outlined,
    CalendarEventKind.paid => Icons.payments_outlined,
    CalendarEventKind.reported => Icons.receipt_long_outlined,
    CalendarEventKind.approved => Icons.check_circle_outline_rounded,
    CalendarEventKind.rejected => Icons.cancel_outlined,
  };

  bool _matches(CalendarEvent e) {
    // Un pago familiar sin estudiante identificable NO se atribuye a un hijo.
    if (_studentFilter.isNotEmpty && e.studentId != _studentFilter) {
      return false;
    }
    if (_filter == 'Cuotas') {
      return e.kind == CalendarEventKind.generated ||
          e.kind == CalendarEventKind.due;
    }
    if (_filter == 'Pagos') {
      return e.kind != CalendarEventKind.generated &&
          e.kind != CalendarEventKind.due;
    }
    if (_filter == 'Aprobados') {
      return e.kind == CalendarEventKind.approved;
    }
    if (_filter == 'Rechazados') {
      return e.kind == CalendarEventKind.rejected;
    }
    if (_filter == 'En revisión') {
      return e.kind == CalendarEventKind.reported && e.pending;
    }
    return true;
  }

  List<CalendarEvent> get _filtered => _events.where(_matches).toList();

  // Seleccionar una fecha abre el historial de ese día en un diálogo,
  // sin desplazar la página ni modificar los paneles laterales.
  void _openDayMovements(DateTime date) {
    final selectedDate = DateUtils.dateOnly(date);
    setState(() => _selected = selectedDate);
    final dayEvents =
        _filtered.where((event) => _sameDay(event.date, selectedDate)).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final weekdays = <String>[
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    final when =
        '${weekdays[selectedDate.weekday - 1]}, '
        '${selectedDate.day} de ${_months[selectedDate.month - 1]} '
        'de ${selectedDate.year}';

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xAA0F2445),
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final maxWidth = screen.width < 560 ? screen.width - 30 : 530.0;
        final maxHeight = screen.height * 0.82;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 20,
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 16, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFECF3FF),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.event_note_rounded,
                          color: _blue,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Movimientos del día',
                              style: TextStyle(
                                fontSize: 17,
                                color: _navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              when,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '${dayEvents.length} '
                              '${dayEvents.length == 1 ? 'movimiento' : 'movimientos'} registrados',
                              style: const TextStyle(
                                color: _blue,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        tooltip: 'Cerrar ventana',
                        icon: const Icon(Icons.close_rounded),
                        color: _navy,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _border),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: dayEvents.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 32,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFE),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: const Color(0xFFE7EDF8),
                              ),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.event_available_outlined,
                                  size: 34,
                                  color: _blue,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Sin movimientos en esta fecha',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _navy,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Prueba con otro día o cambia los filtros.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _muted, fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final event in dayEvents) ...[
                                _popupEventRow(event, dialogContext),
                                const SizedBox(height: 9),
                              ],
                            ],
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: const BorderSide(color: _border),
                        minimumSize: const Size(98, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _eventTitle(CalendarEvent event) => switch (event.kind) {
    CalendarEventKind.paid => 'Fecha del pago',
    CalendarEventKind.reported => 'Reporte enviado',
    _ => event.title,
  };

  String _movementCategory(CalendarEvent event) => switch (event.kind) {
    CalendarEventKind.generated => 'CUOTA GENERADA',
    CalendarEventKind.due => 'FECHA DE VENCIMIENTO',
    CalendarEventKind.paid => 'FECHA DECLARADA DEL PAGO',
    CalendarEventKind.reported => 'REPORTE ENVIADO',
    CalendarEventKind.approved => 'PAGO APROBADO',
    CalendarEventKind.rejected => 'PAGO RECHAZADO',
  };

  // Una etiqueta explícita distingue el paso del proceso incluso para quienes
  // no pueden diferenciar los colores. No se deduce una fecha de aprobación.
  String _movementDescription(CalendarEvent event) => switch (event.kind) {
    CalendarEventKind.generated => 'Se generó una nueva cuota',
    CalendarEventKind.due => 'Fecha límite de la cuota',
    CalendarEventKind.paid =>
      'Fecha indicada por el representante al pagar. No implica aprobación del colegio.',
    CalendarEventKind.reported =>
      'Fecha en que se envió el comprobante a EduPago para su revisión. Puede ser distinta a la fecha del pago.',
    CalendarEventKind.approved => 'El colegio aprobó el pago',
    CalendarEventKind.rejected => 'El colegio rechazó el pago',
  };

  Widget _popupEventRow(CalendarEvent event, BuildContext dialogContext) {
    final color = _tone(event.kind);
    final canOpen = event.paymentId != null && widget.onOpenPayment != null;
    return Semantics(
      button: canOpen,
      label:
          '${_movementCategory(event)}. ${_eventTitle(event)}. '
          '${event.details}. ${event.amount ?? ''}. ${_formatTime(event.date)}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: !canOpen
              ? null
              : () {
                  Navigator.of(dialogContext).pop();
                  widget.onOpenPayment?.call(event.paymentId);
                },
          borderRadius: BorderRadius.circular(13),
          hoverColor: color.withValues(alpha: 0.06),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color.withValues(alpha: 0.37)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.11),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                _icon(event.kind),
                                color: color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      _movementCategory(event),
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.35,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    _eventTitle(event),
                                    style: const TextStyle(
                                      color: _navy,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _movementDescription(event),
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    event.details,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 11.5,
                                      height: 1.45,
                                    ),
                                  ),
                                  if (event.amount != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      event.amount!,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatTime(event.date),
                                  style: const TextStyle(
                                    color: _navy,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (canOpen) ...[
                                  const SizedBox(height: 8),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: color,
                                    size: 18,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
        padding: EdgeInsets.fromLTRB(inset, 24, inset, 32),
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 830) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _filters(constraints.maxWidth),
                            const SizedBox(height: 16),
                            _calendar(),
                            const SizedBox(height: 18),
                            _agendaSelector(),
                            const SizedBox(height: 12),
                            _agenda(),
                          ],
                        );
                      }
                      // Una única medida para ambos paneles: el mes puede
                      // tener 4, 5 o 6 semanas. No se usa IntrinsicHeight con
                      // GridView, pues RenderViewport no admite intrínsecos.
                      final first = DateTime(_month.year, _month.month, 1);
                      final days = DateUtils.getDaysInMonth(
                        _month.year,
                        _month.month,
                      );
                      final weeks = ((first.weekday - 1 + days + 6) ~/ 7);
                      final scaled =
                          MediaQuery.textScalerOf(context).scale(14) / 14;
                      final panelHeight =
                          (446.0 + (weeks - 5) * 50.0) *
                          (scaled > 1 ? scaled : 1.0);
                      // Ancho de la columna del calendario (flex 8 de 13).
                      final calendarWidth =
                          (constraints.maxWidth - 18) * 8 / 13;
                      final panels = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 8,
                            child: SizedBox(
                              height: panelHeight,
                              child: _calendar(fillHeight: true),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 5,
                            child: _agenda(height: panelHeight),
                          ),
                        ],
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 8,
                                  child: _filters(calendarWidth),
                                ),
                                const SizedBox(width: 18),
                                Expanded(flex: 5, child: _agendaSelector()),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          panels,
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

  // Vista renovada: misma fuente de datos y mismas acciones, con prioridad
  // al mes y una agenda compacta, legible y accesible.
  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 540;
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_month_rounded,
                color: _blue,
                size: narrow ? 26 : 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Mi calendario',
                  style: TextStyle(
                    color: _navy,
                    fontSize: narrow ? 25 : 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tus cuotas, vencimientos y movimientos de pago, en un solo lugar.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
          ),
        ],
      );
      final refreshButton = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _blue.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            hoverColor: const Color(0xFFF3F7FE),
            highlightColor: const Color(0xFFEAF2FF),
            onTap: _refreshing ? null : () => _load(silent: true),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEAF2FF),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _refreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: _blue,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _refreshing ? 'Actualizando...' : 'Actualizar',
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final refresh = _CalendarHover(child: refreshButton);
      if (constraints.maxWidth < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 16), refresh],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          const SizedBox(width: 16),
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
          color: isError ? _red : _orange,
          size: 20,
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
    final monthCount = _events
        .where(
          (e) => e.date.year == _month.year && e.date.month == _month.month,
        )
        .length;
    final dueCount = _events
        .where(
          (e) =>
              e.kind == CalendarEventKind.due &&
              !DateUtils.dateOnly(e.date).isBefore(today),
        )
        .length;
    final pendingCount = _events
        .where((e) => e.kind == CalendarEventKind.reported && e.pending)
        .length;

    final cards = [
      _summaryCard(
        title: 'Eventos del mes',
        value: '$monthCount',
        icon: Icons.event_note_outlined,
        accent: _blue,
        tint: const Color(0xFFEBF3FF),
      ),
      _summaryCard(
        title: 'Vencimientos programados',
        value: '$dueCount',
        icon: Icons.event_busy_outlined,
        accent: _orange,
        tint: const Color(0xFFFFF5E7),
      ),
      _summaryCard(
        title: 'Reportes en revisión',
        value: '$pendingCount',
        icon: Icons.hourglass_top_rounded,
        accent: _violet,
        tint: const Color(0xFFF3EDFF),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 570) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                cards[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 13),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    required Color tint,
  }) => _CalendarHover(
    child: Container(
      constraints: const BoxConstraints(minHeight: 100),
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Círculo decorativo en la esquina superior derecha; crece al hover.
          Positioned.fill(child: _CornerCircle(color: accent)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 23),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // --- Selectores con el mismo diseño del selector de estudiantes del inicio ---
  bool _isStudentActive(Map<String, dynamic> st) {
    final v = st['activo'];
    if (v == null) return true;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final t = v.toString().trim().toLowerCase();
    return !(t == 'false' ||
        t == 'f' ||
        t == '0' ||
        t == 'no' ||
        t == 'inactivo' ||
        t == 'retirado');
  }

  String _studentName(Map<String, dynamic> st) =>
      '${st['nombres'] ?? ''} ${st['apellidos'] ?? ''}'.trim();

  String _initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  /// Avatar circular con degradado suave, igual al del selector del inicio.
  Widget _selectorAvatar({
    IconData? icon,
    String? text,
    Color color = _blue,
    double size = 38,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Colors.white, color, 0.08)!,
            Color.lerp(Colors.white, color, 0.20)!,
          ],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.5, color: color)
          : Text(
              text ?? '',
              style: TextStyle(
                color: color,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  /// Botón de selección: avatar, título pequeño, valor y flecha circular.
  Widget _selectorButton({
    required double width,
    required Widget avatar,
    String? caption,
    required String value,
    required String detail,
    String? badge,
    required Future<void> Function(BuildContext ctx) onOpen,
  }) => _CalendarHover(
    child: _selectorButtonRaw(
      width: width,
      avatar: avatar,
      caption: caption,
      value: value,
      detail: detail,
      badge: badge,
      onOpen: onOpen,
    ),
  );

  Widget _selectorButtonRaw({
    required double width,
    required Widget avatar,
    String? caption,
    required String value,
    required String detail,
    String? badge,
    required Future<void> Function(BuildContext ctx) onOpen,
  }) {
    return SizedBox(
      width: width,
      child: Builder(
        builder: (ctx) => Semantics(
          button: true,
          label: caption == null ? value : '$caption: $value',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: _blue.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                hoverColor: const Color(0xFFF3F7FE),
                highlightColor: const Color(0xFFEAF2FF),
                onTap: () => onOpen(ctx),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                  child: Row(
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (caption != null) ...[
                              Text(
                                caption,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 9.5,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                            ],
                            Text(
                              value,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (badge != null) ...[
                        Container(
                          constraints: const BoxConstraints(minWidth: 28),
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: const Color(0xFFEAF2FF),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF0F5FF),
                          border: Border.all(color: const Color(0xFFDCE7FB)),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 19,
                          color: _blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuRow<T>(
    _MenuOption<T> option, {
    required bool selected,
    required bool isLast,
  }) {
    var hovered = false;
    return StatefulBuilder(
      builder: (context, setLocal) => MouseRegion(
        onEnter: (_) => setLocal(() => hovered = true),
        onExit: (_) => setLocal(() => hovered = false),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: (hovered && option.enabled)
                ? const Color(0xFFEAF2FF)
                : (selected
                      ? const Color(0xFFEAF2FF).withValues(alpha: 0.65)
                      : Colors.transparent),
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: _border)),
          ),
          child: Opacity(
            opacity: option.enabled ? 1 : 0.5,
            child: Row(
              children: [
                option.avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        option.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: _muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!option.enabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF1F7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'INACTIVO',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: _muted,
                      ),
                    ),
                  )
                else if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: _blue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Menú desplegable bajo el botón, con su mismo ancho (como en el inicio).
  Future<T?> _showSelectMenu<T>(
    BuildContext ctx, {
    required String header,
    required T selected,
    required List<_MenuOption<T>> options,
  }) {
    final box = ctx.findRenderObject();
    final overlayBox = Overlay.of(ctx).context.findRenderObject();
    if (box is! RenderBox || overlayBox is! RenderBox || !box.hasSize) {
      return Future<T?>.value(null);
    }
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy + box.size.height + 8,
      box.size.width,
      0,
    );
    return showMenu<T>(
      context: ctx,
      position: RelativeRect.fromRect(rect, Offset.zero & overlayBox.size),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0xFF1B4785).withValues(alpha: 0.22),
      clipBehavior: Clip.antiAlias,
      menuPadding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: box.size.width),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _border),
      ),
      items: [
        PopupMenuItem<T>(
          enabled: false,
          padding: EdgeInsets.zero,
          height: 40,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE8EEF8))),
            ),
            child: Text(
              header,
              style: const TextStyle(
                fontSize: 11,
                color: _muted,
                letterSpacing: 0.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        for (final entry in options.indexed)
          PopupMenuItem<T>(
            value: entry.$2.value,
            enabled: entry.$2.enabled,
            padding: EdgeInsets.zero,
            height: 56,
            child: _menuRow<T>(
              entry.$2,
              selected: entry.$2.enabled && entry.$2.value == selected,
              isLast: entry.$1 == options.length - 1,
            ),
          ),
      ],
    );
  }

  Widget _filters(double width) {
    final filters = <Map<String, dynamic>>[
      {
        'label': 'Todos',
        'sub': 'Todos los movimientos',
        'icon': Icons.dashboard_customize_rounded,
        'color': _blue,
      },
      {
        'label': 'Cuotas',
        'sub': 'Cuotas nuevas y vencimientos',
        'icon': Icons.calendar_month_rounded,
        'color': _blue,
      },
      {
        'label': 'Pagos',
        'sub': 'Fechas de pago, reportes y revisiones',
        'icon': Icons.receipt_long_rounded,
        'color': _blue,
      },
      {
        'label': 'Aprobados',
        'sub': 'Pagos confirmados por el colegio',
        'icon': Icons.check_circle_outline_rounded,
        'color': _green,
      },
      {
        'label': 'Rechazados',
        'sub': 'Pagos que no fueron validados',
        'icon': Icons.highlight_off_rounded,
        'color': _red,
      },
      {
        'label': 'En revisión',
        'sub': 'Pagos pendientes de aprobación',
        'icon': Icons.schedule_rounded,
        'color': _orange,
      },
    ];
    final current = filters.firstWhere(
      (f) => f['label'] == _filter,
      orElse: () => filters.first,
    );

    Widget filterButton(double w) => _selectorButton(
      width: w,
      avatar: _selectorAvatar(
        icon: current['icon'] as IconData,
        color: current['color'] as Color,
      ),
      caption: 'MOVIMIENTOS',
      value: current['label'] as String,
      detail: current['sub'] as String,
      onOpen: (ctx) async {
        final choice = await _showSelectMenu<String>(
          ctx,
          header: 'FILTRAR MOVIMIENTOS',
          selected: _filter,
          options: [
            for (final f in filters)
              _MenuOption<String>(
                value: f['label'] as String,
                title: f['label'] as String,
                subtitle: f['sub'] as String,
                avatar: _selectorAvatar(
                  icon: f['icon'] as IconData,
                  color: f['color'] as Color,
                  size: 36,
                ),
              ),
          ],
        );
        if (choice != null && mounted) setState(() => _filter = choice);
      },
    );

    Widget studentButton(double w) {
      Map<String, dynamic>? selectedStudent;
      for (final st in widget.students) {
        if ((st['id']?.toString() ?? '') == _studentFilter &&
            _studentFilter.isNotEmpty) {
          selectedStudent = st;
        }
      }
      final family = selectedStudent == null;
      final name = selectedStudent == null
          ? 'Toda mi familia'
          : _studentName(selectedStudent);
      return _selectorButton(
        width: w,
        avatar: family
            ? _selectorAvatar(icon: Icons.people_alt_rounded)
            : _selectorAvatar(text: _initialsOf(name)),
        caption: 'ESTUDIANTE',
        value: name,
        detail: selectedStudent == null
            ? '${widget.students.length} estudiantes vinculados'
            : ((selectedStudent['grado_seccion'] ??
                          selectedStudent['grado'] ??
                          '')
                      .toString()
                      .trim()
                      .isEmpty
                  ? 'Estudiante'
                  : (selectedStudent['grado_seccion'] ??
                            selectedStudent['grado'])
                        .toString()),
        badge: selectedStudent == null ? '${widget.students.length}' : '1',
        onOpen: (ctx) async {
          final ordered = [
            ...widget.students.where(_isStudentActive),
            ...widget.students.where((st) => !_isStudentActive(st)),
          ];
          final choice = await _showSelectMenu<String>(
            ctx,
            header: 'SELECCIONAR ESTUDIANTE',
            selected: _studentFilter,
            options: [
              _MenuOption<String>(
                value: '',
                title: 'Toda mi familia',
                subtitle: '${widget.students.length} estudiantes vinculados',
                avatar: _selectorAvatar(
                  icon: Icons.people_alt_rounded,
                  size: 36,
                ),
              ),
              for (final st in ordered)
                _MenuOption<String>(
                  value: st['id']?.toString() ?? '',
                  title: _studentName(st),
                  subtitle: _isStudentActive(st)
                      ? ((st['grado_seccion'] ?? st['grado'] ?? '')
                                .toString()
                                .trim()
                                .isEmpty
                            ? 'Estudiante'
                            : (st['grado_seccion'] ?? st['grado']).toString())
                      : 'Estudiante inactivo o retirado',
                  enabled: _isStudentActive(st),
                  avatar: _selectorAvatar(
                    text: _initialsOf(_studentName(st)),
                    size: 36,
                  ),
                ),
            ],
          );
          if (choice != null && mounted) {
            setState(() => _studentFilter = choice);
          }
        },
      );
    }

    // Los dos selectores se reparten el ancho disponible (el del calendario).
    final single = widget.students.length < 2;
    if (width < 560 && !single) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterButton(double.infinity),
          const SizedBox(height: 12),
          studentButton(double.infinity),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: filterButton(double.infinity)),
        if (!single) ...[
          const SizedBox(width: 14),
          Expanded(child: studentButton(double.infinity)),
        ],
      ],
    );
  }

  Widget _calendar({bool fillHeight = false}) {
    final day1 = DateTime(_month.year, _month.month, 1);
    final offset = day1.weekday - 1;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final totalCells = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final events = _filtered;
    final today = DateUtils.dateOnly(DateTime.now());
    final name = _months[_month.month - 1];
    final monthLabel =
        '${name[0].toUpperCase()}${name.substring(1)} ${_month.year}';

    return _CalendarHover(
      child: Container(
        decoration: _cardDecoration(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final monthInfo = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VISTA MENSUAL',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      monthLabel,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                );
                final controls = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: _goToday,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(58, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: _blue,
                        side: const BorderSide(color: _border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Hoy',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    _monthArrow(Icons.chevron_left_rounded, 'Mes anterior', -1),
                    const SizedBox(width: 5),
                    _monthArrow(
                      Icons.chevron_right_rounded,
                      'Mes siguiente',
                      1,
                    ),
                  ],
                );
                if (c.maxWidth < 365) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [monthInfo, const SizedBox(height: 12), controls],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: monthInfo),
                    controls,
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFE),
                borderRadius: BorderRadius.circular(13),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  for (final label in _weekdays)
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: Center(
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: _muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 420;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: compact ? 38 : 40,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: compact ? 2 : 4,
                  ),
                  itemCount: totalCells,
                  itemBuilder: (context, i) {
                    final number = i - offset + 1;
                    if (number < 1 || number > daysInMonth) {
                      return const SizedBox();
                    }
                    final date = DateTime(_month.year, _month.month, number);
                    final dayEvents = events
                        .where((e) => _sameDay(e.date, date))
                        .toList();
                    final isSelected = _sameDay(date, _selected);
                    final isToday = _sameDay(date, today);
                    final hasDue = dayEvents.any(
                      (e) => e.kind == CalendarEventKind.due,
                    );
                    final kindPriority = {
                      CalendarEventKind.due: 0,
                      CalendarEventKind.approved: 1,
                      CalendarEventKind.rejected: 2,
                      CalendarEventKind.reported: 3,
                      CalendarEventKind.paid: 4,
                      CalendarEventKind.generated: 5,
                    };
                    final kinds = dayEvents.map((e) => e.kind).toSet().toList()
                      ..sort(
                        (a, b) => (kindPriority[a] ?? 99).compareTo(
                          kindPriority[b] ?? 99,
                        ),
                      );
                    final accessibleLabel =
                        '${_formatDate(date)}. '
                        '${dayEvents.length} ${dayEvents.length == 1 ? 'movimiento' : 'movimientos'}. '
                        'Pulsa para ver el detalle';
                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label: accessibleLabel,
                      child: Tooltip(
                        message: accessibleLabel,
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            hoverColor: const Color(0xFFECF3FF),
                            onTap: () => _openDayMovements(date),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFEBF2FF)
                                    : hasDue
                                    ? const Color(0xFFFFF7EA)
                                    : isToday
                                    ? const Color(0xFFF6F9FF)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  width: isSelected || hasDue ? 1.4 : 1,
                                  color: isSelected
                                      ? const Color(0xFF7FAAFF)
                                      : hasDue
                                      ? const Color(0xFFF1C27D)
                                      : isToday
                                      ? const Color(0xFFD3E1F8)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: compact ? 22 : 24,
                                    height: compact ? 22 : 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? _blue
                                          : hasDue
                                          ? const Color(0xFFFFE0B2)
                                          : Colors.transparent,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '$number',
                                        style: TextStyle(
                                          fontSize: compact ? 11.5 : 12.5,
                                          color: isSelected
                                              ? Colors.white
                                              : hasDue
                                              ? _orange
                                              : _navy,
                                          fontWeight:
                                              isSelected || isToday || hasDue
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  // Altura fija: el número de movimientos nunca
                                  // aumenta la altura ni desborda la celda.
                                  SizedBox(
                                    height: 8,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (final kind in kinds.take(3))
                                              Container(
                                                width: 5,
                                                height: 5,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: _tone(kind),
                                                ),
                                              ),
                                            if (dayEvents.length > 1) ...[
                                              const SizedBox(width: 3),
                                              Text(
                                                '${dayEvents.length}',
                                                style: const TextStyle(
                                                  color: _navy,
                                                  fontSize: 8,
                                                  height: 1,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            if (fillHeight) const Spacer(),
            const SizedBox(height: 8),
            const Divider(height: 1, color: _border),
            const SizedBox(height: 9),
            // Leyenda en una sola línea; si no cabe, se reduce en vez de saltar.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _legend('Cuota nueva', _blue),
                  const SizedBox(width: 14),
                  _legend('Vencimiento', _orange),
                  const SizedBox(width: 14),
                  Tooltip(
                    message: 'Día en que se envió el comprobante a EduPago.',
                    child: _legend('Reporte enviado', _indigo),
                  ),
                  const SizedBox(width: 14),
                  Tooltip(
                    message:
                        'Fecha de pago declarada por el representante; no significa aprobado.',
                    child: _legend('Fecha del pago', _violet),
                  ),
                  const SizedBox(width: 14),
                  _legend('Aprobado', _green),
                  const SizedBox(width: 14),
                  _legend('Rechazado', _red),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'El contador indica movimientos, no pagos distintos. '
              'Pulsa un día para ver todos sus detalles.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthArrow(IconData icon, String tooltip, int offset) => Tooltip(
    message: tooltip,
    child: Material(
      color: const Color(0xFFF3F7FE),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _moveMonth(offset),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: _navy, size: 20),
        ),
      ),
    ),
  );

  Widget _legend(String name, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: 6),
      Text(
        name,
        style: const TextStyle(
          color: _muted,
          fontSize: 11.3,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  // La columna lateral muestra solamente próximos vencimientos y actividad
  // reciente. El detalle del día vive en un diálogo al pulsar una fecha.
  List<Map<String, dynamic>> get _agendaViews => [
    {
      'label': 'Todo',
      'sub': 'Vencimientos y movimientos',
      'icon': Icons.dashboard_customize_rounded,
      'color': _blue,
    },
    {
      'label': 'Próximos vencimientos',
      'sub': 'Cuotas que están por vencer',
      'icon': Icons.event_busy_outlined,
      'color': _orange,
    },
    {
      'label': 'Movimientos recientes',
      'sub': 'Tu actividad más reciente',
      'icon': Icons.history_rounded,
      'color': _indigo,
    },
    {
      'label': 'Pagos en revisión',
      'sub': 'Esperando aprobación del colegio',
      'icon': Icons.schedule_rounded,
      'color': _orange,
    },
    {
      'label': 'Información de pagos',
      'sub': 'Resumen de tus pagos reportados',
      'icon': Icons.payments_outlined,
      'color': _violet,
    },
  ];

  /// Selector del panel derecho: vive arriba, junto a los demás filtros, y
  /// define lo que se muestra en la tarjeta de abajo.
  Widget _agendaSelector() {
    final views = _agendaViews;
    final current = views.firstWhere(
      (v) => v['label'] == _agendaView,
      orElse: () => views.first,
    );
    return _selectorButton(
      width: double.infinity,
      avatar: _selectorAvatar(
        icon: current['icon'] as IconData,
        color: current['color'] as Color,
      ),
      value: current['label'] as String,
      detail: current['sub'] as String,
      onOpen: (ctx) async {
        final choice = await _showSelectMenu<String>(
          ctx,
          header: 'VER EN ESTE PANEL',
          selected: _agendaView,
          options: [
            for (final v in views)
              _MenuOption<String>(
                value: v['label'] as String,
                title: v['label'] as String,
                subtitle: v['sub'] as String,
                avatar: _selectorAvatar(
                  icon: v['icon'] as IconData,
                  color: v['color'] as Color,
                  size: 36,
                ),
              ),
          ],
        );
        if (choice != null && mounted) setState(() => _agendaView = choice);
      },
    );
  }

  List<CalendarEvent> get _upcomingEvents {
    final today = DateUtils.dateOnly(DateTime.now());
    return _events
        .where(
          (event) =>
              event.kind == CalendarEventKind.due &&
              (_studentFilter.isEmpty || event.studentId == _studentFilter) &&
              !DateUtils.dateOnly(event.date).isBefore(today),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<CalendarEvent> get _recentEvents {
    final today = DateUtils.dateOnly(DateTime.now());
    return _filtered
        .where(
          (event) =>
              event.kind != CalendarEventKind.due &&
              !DateUtils.dateOnly(event.date).isAfter(today),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<CalendarEvent> get _reviewEvents =>
      _events
          .where(
            (event) =>
                event.kind == CalendarEventKind.reported &&
                event.pending &&
                (_studentFilter.isEmpty || event.studentId == _studentFilter),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// Resumen de pagos reportados por la familia (no depende del estudiante).
  Widget _paymentInfo() {
    Set<String> ids(Iterable<CalendarEvent> it) =>
        it.map((e) => e.paymentId ?? e.id).toSet();
    final reportedEvents =
        _events.where((e) => e.kind == CalendarEventKind.reported).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final reported = ids(reportedEvents);
    final approved = ids(
      _events.where((e) => e.kind == CalendarEventKind.approved),
    );
    final rejected = ids(
      _events.where((e) => e.kind == CalendarEventKind.rejected),
    );
    final review = ids(reportedEvents.where((e) => e.pending));
    final last = reportedEvents.isEmpty ? null : reportedEvents.first;

    Widget tile(String label, int value, Color color, IconData icon) =>
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$value',
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: tile(
                'Reportados',
                reported.length,
                _indigo,
                Icons.receipt_long_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: tile(
                'Aprobados',
                approved.length,
                _green,
                Icons.check_circle_outline_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: tile(
                'En revisión',
                review.length,
                _orange,
                Icons.schedule_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: tile(
                'Rechazados',
                rejected.length,
                _red,
                Icons.highlight_off_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'ÚLTIMO PAGO REPORTADO',
          style: TextStyle(
            color: _muted,
            fontSize: 10.5,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (last == null)
          _emptyList('Aún no hay pagos reportados.')
        else
          _eventRow(last, showDate: true),
      ],
    );
  }

  Widget _agenda({double? height}) {
    final upcoming = _upcomingEvents;
    final recent = _recentEvents;
    final inReview = _reviewEvents;

    final view = _agendaView;
    final showDue = view == 'Todo' || view == 'Próximos vencimientos';
    final showRecent = view == 'Todo' || view == 'Movimientos recientes';
    final showReview = view == 'Pagos en revisión';
    final showInfo = view == 'Información de pagos';

    final historyButton = widget.onOpenPayment == null
        ? null
        : Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => widget.onOpenPayment?.call(null),
              label: const Text('Ver historial de pagos'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 15),
              style: TextButton.styleFrom(
                foregroundColor: _blue,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          );

    // Móvil: usa el scroll único de la página, evitando listas anidadas.
    if (height == null) {
      Widget block(
        String title,
        IconData icon,
        Color color,
        List<CalendarEvent> events,
        int take,
        String empty,
      ) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(title, icon, color),
          const SizedBox(height: 12),
          if (events.isEmpty)
            _emptyList(empty)
          else
            for (final event in events.take(take))
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _eventRow(event, showDate: true),
              ),
        ],
      );
      return _CalendarHover(
        child: Container(
          decoration: _cardDecoration(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDue)
                block(
                  'Próximos vencimientos',
                  Icons.event_busy_outlined,
                  _orange,
                  upcoming,
                  3,
                  'No hay vencimientos futuros registrados.',
                ),
              if (showDue && showRecent) ...[
                const SizedBox(height: 5),
                const Divider(height: 1, color: _border),
                const SizedBox(height: 16),
              ],
              if (showRecent)
                block(
                  'Movimientos recientes',
                  Icons.history_rounded,
                  _indigo,
                  recent,
                  4,
                  'No hay movimientos registrados con estos filtros.',
                ),
              if (showReview)
                block(
                  'Pagos en revisión',
                  Icons.schedule_rounded,
                  _orange,
                  inReview,
                  6,
                  'No tienes pagos en revisión.',
                ),
              if (showInfo) _paymentInfo(),
              if (historyButton != null) historyButton,
            ],
          ),
        ),
      );
    }

    // Escritorio: títulos siempre visibles y listas independientes.
    // El scrollbar tiene su propio controller para poder arrastrarlo.
    Widget section(
      String title,
      IconData icon,
      Color color,
      List<CalendarEvent> events,
      ScrollController controller,
      String empty, {
      int flex = 1,
    }) => Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(title, icon, color),
          const SizedBox(height: 10),
          Expanded(
            child: _scrollableEvents(
              events: events,
              controller: controller,
              emptyMessage: empty,
            ),
          ),
        ],
      ),
    );

    final dueSection = section(
      'Próximos vencimientos',
      Icons.event_busy_outlined,
      _orange,
      upcoming.take(20).toList(),
      _dueScrollController,
      'No hay vencimientos futuros registrados.',
      flex: 5,
    );
    final recentSection = section(
      'Movimientos recientes',
      Icons.history_rounded,
      _indigo,
      recent.take(30).toList(),
      _recentScrollController,
      'No hay movimientos con estos filtros.',
      flex: 4,
    );

    final List<Widget> body;
    if (view == 'Todo') {
      // Una sola lista continua: cada bloque ocupa solo lo que necesita.
      final dueList = upcoming.take(20).toList();
      final recentList = recent.take(30).toList();
      body = [
        Expanded(
          child: Scrollbar(
            controller: _dueScrollController,
            thumbVisibility: true,
            interactive: true,
            thickness: 4,
            radius: const Radius.circular(8),
            child: ListView(
              controller: _dueScrollController,
              primary: false,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(right: 10, bottom: 22),
              children: [
                _sectionHeading(
                  'Próximos vencimientos',
                  Icons.event_busy_outlined,
                  _orange,
                  count: upcoming.length,
                ),
                const SizedBox(height: 10),
                if (dueList.isEmpty)
                  _emptyList('No hay vencimientos futuros registrados.')
                else
                  for (final event in dueList)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _eventRow(event, showDate: true),
                    ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: _border),
                const SizedBox(height: 16),
                _sectionHeading(
                  'Movimientos recientes',
                  Icons.history_rounded,
                  _indigo,
                  count: recent.length,
                ),
                const SizedBox(height: 10),
                if (recentList.isEmpty)
                  _emptyList('No hay movimientos con estos filtros.')
                else
                  for (final event in recentList)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _eventRow(event, showDate: true),
                    ),
              ],
            ),
          ),
        ),
      ];
    } else if (showDue) {
      body = [dueSection];
    } else if (showRecent) {
      body = [recentSection];
    } else if (showReview) {
      body = [
        section(
          'Pagos en revisión',
          Icons.schedule_rounded,
          _orange,
          inReview.take(30).toList(),
          _recentScrollController,
          'No tienes pagos en revisión.',
        ),
      ];
    } else {
      body = [
        Expanded(
          child: SingleChildScrollView(
            controller: _infoScrollController,
            primary: false,
            padding: const EdgeInsets.only(right: 4, bottom: 8),
            child: _paymentInfo(),
          ),
        ),
      ];
    }

    return Listener(
      // Mantiene el gesto de rueda dentro del panel: cuando una de las listas
      // llega a su primer o último elemento no desplaza la página de fondo.
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            (_) {}, // Consume solo el scroll que las listas no utilizaron.
          );
        }
      },
      child: _CalendarHover(
        child: Container(
          height: height,
          decoration: _cardDecoration(),
          padding: const EdgeInsets.fromLTRB(17, 17, 13, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...body,
              if (historyButton != null) ...[
                const SizedBox(height: 2),
                historyButton,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _scrollableEvents({
    required List<CalendarEvent> events,
    required ScrollController controller,
    required String emptyMessage,
  }) {
    if (events.isEmpty) {
      return Center(child: _emptyList(emptyMessage));
    }
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      interactive: true,
      thickness: 4,
      radius: const Radius.circular(8),
      child: ListView.separated(
        controller: controller,
        primary: false,
        physics: const ClampingScrollPhysics(),
        // Espacio después del último movimiento, visible al llegar al final.
        // La tarjeta ya no queda pegada al borde ni a «Ver historial».
        padding: const EdgeInsets.only(right: 10, bottom: 22),
        itemCount: events.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) =>
            _eventRow(events[index], showDate: true),
      ),
    );
  }

  Widget _sectionHeading(
    String title,
    IconData icon,
    Color color, {
    int? count,
  }) => Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: _navy,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      if (count != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
    ],
  );

  Widget _emptyList(String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      label,
      style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.45),
    ),
  );

  Widget _eventRow(CalendarEvent event, {bool showDate = false}) {
    final color = _tone(event.kind);
    final isPayment = event.paymentId != null && widget.onOpenPayment != null;
    final labelDate = showDate
        ? _formatDate(event.date)
        : _formatTime(event.date);
    void openEvent() {
      if (isPayment) {
        widget.onOpenPayment?.call(event.paymentId);
      } else {
        setState(() {
          _month = DateTime(event.date.year, event.date.month);
        });
        _openDayMovements(event.date);
      }
    }

    return Material(
      color: color.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: openEvent,
        borderRadius: BorderRadius.circular(12),
        hoverColor: color.withValues(alpha: 0.09),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.17)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon(event.kind), size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _eventTitle(event),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    if (event.amount != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        event.amount!,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    labelDate,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: color),
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
  late final CalendarRepository _repository;
  Timer? _reloadTimer;

  @override
  void initState() {
    super.initState();
    _repository = SupabaseCalendarRepository(
      channelKey: 'preview-${identityHashCode(this)}',
    );
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
    _repository.stopListening();
  }

  void _listenPayments() => _repository.startListening(
    representativeId: widget.representativeId.trim(),
    onChanged: () {
      _reloadTimer?.cancel();
      _reloadTimer = Timer(const Duration(milliseconds: 450), _load);
    },
  );

  Future<void> _load() async {
    final representativeId = widget.representativeId.trim();
    final request = ++_request;
    if (representativeId.isEmpty) {
      if (mounted) {
        setState(() {
          _events = [];
          _loading = false;
          _failed = true;
        });
      }
      return;
    }

    try {
      final result = await _repository.loadEvents(
        representativeId: representativeId,
        students: widget.students.map(CalendarStudent.fromMap).toList(),
      );
      if (!mounted || request != _request) {
        return;
      }
      setState(() {
        _events = result.events.map((event) {
          final color = switch (event.kind) {
            CalendarEventKind.generated => _blue,
            CalendarEventKind.due => _orange,
            CalendarEventKind.paid => _violet,
            CalendarEventKind.reported => _blue,
            CalendarEventKind.approved => _green,
            CalendarEventKind.rejected => _red,
          };
          return _PreviewEvent(
            event.date,
            color,
            event.kind == CalendarEventKind.due,
          );
        }).toList();
        _loading = false;
        _failed = !result.hasSuccessfulSource;
      });
    } catch (error) {
      if (!mounted || request != _request) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
      debugPrint('Resumen calendario: error de carga: $error');
    }
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
      if (!uniqueColors.contains(e.color)) {
        uniqueColors.add(e.color);
      }
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

/// Opción de un menú desplegable de selección.
class _MenuOption<T> {
  const _MenuOption({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.avatar,
    this.enabled = true,
  });

  final T value;
  final String title;
  final String subtitle;
  final Widget avatar;
  final bool enabled;
}

/// Hover de tarjetas igual al del dashboard: sombra suave y borde azul tenue.
class _CalendarHover extends StatefulWidget {
  const _CalendarHover({required this.child, this.radius = 16});

  final Widget child;
  final double radius;

  @override
  State<_CalendarHover> createState() => _CalendarHoverState();
}

class _CalendarHoverState extends State<_CalendarHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final color = AppColors.primaryBlue;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 155),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.065),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _hovered
                ? color.withValues(alpha: 0.30)
                : Colors.transparent,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Círculo decorativo anclado a la esquina superior derecha de una tarjeta.
/// Crece un 25 % cuando el cursor pasa por encima, sin mover el contenido.
class _CornerCircle extends StatefulWidget {
  const _CornerCircle({required this.color});

  final Color color;

  @override
  State<_CornerCircle> createState() => _CornerCircleState();
}

class _CornerCircleState extends State<_CornerCircle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _hovered ? 1.25 : 1.0),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 330),
          curve: Curves.easeOutCubic,
          builder: (context, scale, _) =>
              CustomPaint(painter: _CornerCirclePainter(widget.color, scale)),
        ),
      ),
    );
  }
}

class _CornerCirclePainter extends CustomPainter {
  const _CornerCirclePainter(this.color, this.scale);

  final Color color;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    // Radio proporcional a la altura de la tarjeta; el centro se ancla a la
    // esquina superior derecha en proporción al radio, así el círculo se ve
    // igual de equilibrado en tarjetas bajas y altas.
    final radius = (h * 0.5).clamp(34.0, 75.0).toDouble();
    canvas.save();
    // Escala anclada en la esquina superior derecha.
    canvas.translate(w, 0);
    canvas.scale(scale, scale);
    canvas.translate(-w, 0);
    canvas.drawCircle(
      Offset(w - radius * 0.45, radius * 0.2),
      radius,
      Paint()..color = color.withValues(alpha: 0.10),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CornerCirclePainter old) =>
      old.color != color || old.scale != scale;
}
