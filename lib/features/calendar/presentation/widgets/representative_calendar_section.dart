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
    _repository = SupabaseCalendarRepository(channelKey: 'full-${identityHashCode(this)}');
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
      return e.kind == CalendarEventKind.generated || e.kind == CalendarEventKind.due;
    }
    if (_filter == 'Pagos') {
      return e.kind != CalendarEventKind.generated && e.kind != CalendarEventKind.due;
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

  String _movementCategory(CalendarEvent event) => switch (event.kind) {
    CalendarEventKind.generated => 'CUOTA GENERADA',
    CalendarEventKind.due => 'FECHA DE VENCIMIENTO',
    CalendarEventKind.paid => 'PAGO REALIZADO',
    CalendarEventKind.reported => 'REPORTE ENVIADO',
    CalendarEventKind.approved => 'PAGO APROBADO',
    CalendarEventKind.rejected => 'PAGO RECHAZADO',
  };

  // Una etiqueta explícita distingue el paso del proceso incluso para quienes
  // no pueden diferenciar los colores. No se deduce una fecha de aprobación.
  String _movementDescription(CalendarEvent event) => switch (event.kind) {
    CalendarEventKind.generated => 'Se generó una nueva cuota',
    CalendarEventKind.due => 'Fecha límite de la cuota',
    CalendarEventKind.paid => 'Fecha del pago registrado',
    CalendarEventKind.reported => 'El representante envió el reporte',
    CalendarEventKind.approved => 'El colegio aprobó el pago',
    CalendarEventKind.rejected => 'El colegio rechazó el pago',
  };

  Widget _popupEventRow(CalendarEvent event, BuildContext dialogContext) {
    final color = _tone(event.kind);
    final canOpen = event.paymentId != null && widget.onOpenPayment != null;
    return Semantics(
      button: canOpen,
      label:
          '${_movementCategory(event)}. ${event.title}. '
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
                                    event.title,
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
                  _filters(),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 830) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _calendar(),
                            const SizedBox(height: 18),
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
                          (536.0 + (weeks - 5) * 52.0) *
                          (scaled > 1 ? scaled : 1.0);
                      return Row(
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
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mi calendario',
            style: TextStyle(
              color: _navy,
              fontSize: constraints.maxWidth < 540 ? 25 : 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tus cuotas, vencimientos y movimientos de pago, en un solo lugar.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
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
          minimumSize: const Size(126, 46),
          foregroundColor: _navy,
          backgroundColor: Colors.white,
          side: const BorderSide(color: _border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
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
  }) => Container(
    constraints: const BoxConstraints(minHeight: 100),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
    decoration: _cardDecoration(),
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
  );

  Widget _filters() {
    final filters = <Map<String, dynamic>>[
      {
        'label': 'Todos',
        'icon': Icons.dashboard_customize_rounded,
        'color': _blue,
      },
      {'label': 'Cuotas', 'icon': Icons.calendar_month_rounded, 'color': _blue},
      {'label': 'Pagos', 'icon': Icons.receipt_long_rounded, 'color': _blue},
      {
        'label': 'Aprobados',
        'icon': Icons.check_circle_outline_rounded,
        'color': _green,
      },
      {
        'label': 'Rechazados',
        'icon': Icons.highlight_off_rounded,
        'color': _red,
      },
      {
        'label': 'En revisión',
        'icon': Icons.schedule_rounded,
        'color': _orange,
      },
    ];

    final chips = Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final item in filters)
          _filterChip(
            label: item['label'] as String,
            icon: item['icon'] as IconData,
            color: item['color'] as Color,
            selected: item['label'] == _filter,
            onTap: () => setState(() => _filter = item['label'] as String),
          ),
      ],
    );

    final studentSelector = widget.students.length < 2
        ? null
        : Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                const Icon(Icons.people_alt_outlined, color: _blue, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _studentFilter,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      menuMaxHeight: 290,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _muted,
                        size: 20,
                      ),
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Toda mi familia'),
                        ),
                        for (final s in widget.students)
                          DropdownMenuItem(
                            value: s['id']?.toString() ?? '',
                            child: Text(
                              '${s['nombres'] ?? ''} ${s['apellidos'] ?? ''}'
                                  .trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _studentFilter = value ?? ''),
                    ),
                  ),
                ),
              ],
            ),
          );

    return LayoutBuilder(
      builder: (context, c) {
        if (studentSelector == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FILTRAR MOVIMIENTOS',
                style: TextStyle(
                  color: _muted,
                  fontSize: 10.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              chips,
            ],
          );
        }
        if (c.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FILTRAR MOVIMIENTOS',
                style: TextStyle(
                  color: _muted,
                  fontSize: 10.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              chips,
              const SizedBox(height: 13),
              SizedBox(
                width: c.maxWidth < 320 ? c.maxWidth : 270,
                child: studentSelector,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FILTRAR MOVIMIENTOS',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  chips,
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(width: 235, child: studentSelector),
          ],
        );
      },
    );
  }

  Widget _filterChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : _border),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : _muted,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
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

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
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
                      fontSize: 20,
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
                      minimumSize: const Size(63, 42),
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
                  _monthArrow(Icons.chevron_right_rounded, 'Mes siguiente', 1),
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
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFE),
              borderRadius: BorderRadius.circular(13),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                for (final label in _weekdays)
                  Expanded(
                    child: SizedBox(
                      height: 30,
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
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxWidth < 420;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: compact ? 46 : 49,
                  mainAxisSpacing: compact ? 2 : 3,
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
                  final hasDue = dayEvents.any((e) => e.kind == CalendarEventKind.due);
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
                      '${dayEvents.length} ${dayEvents.length == 1 ? 'evento' : 'eventos'}';
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
                                  width: compact ? 25 : 30,
                                  height: compact ? 25 : 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? _blue
                                        : hasDue
                                        ? const Color(0xFFFFE0B2)
                                        : Colors.transparent,
                                  ),
                                  child: Text(
                                    '$number',
                                    style: TextStyle(
                                      fontSize: compact ? 12 : 13,
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
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (final kind in kinds.take(3))
                                      Container(
                                        width: kind == CalendarEventKind.due
                                            ? 12
                                            : 5.5,
                                        height: 5.5,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 1.2,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          color: _tone(kind),
                                        ),
                                      ),
                                    if (kinds.length > 3)
                                      const Text(
                                        '+',
                                        style: TextStyle(
                                          color: _muted,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
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
              );
            },
          ),
          if (fillHeight) const Spacer(),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 11),
          Wrap(
            spacing: 14,
            runSpacing: 11,
            children: [
              _legend('Cuota nueva', _blue),
              _legend('Vencimiento destacado', _orange),
              _legend('Pago reportado', _indigo),
              _legend('Pago realizado', _violet),
              _legend('Aprobado', _green),
              _legend('Rechazado', _red),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Las fechas corresponden a movimientos registrados. '
            'Consulta el estado de cuenta para confirmar los saldos.',
            style: TextStyle(color: _muted, fontSize: 11, height: 1.45),
          ),
        ],
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
          width: 44,
          height: 44,
          child: Icon(icon, color: _navy, size: 21),
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
  Widget _agenda({double? height}) {
    final today = DateUtils.dateOnly(DateTime.now());
    final upcoming =
        _events
            .where(
              (event) =>
                  event.kind == CalendarEventKind.due &&
                  (_studentFilter.isEmpty ||
                      event.studentId == _studentFilter) &&
                  !DateUtils.dateOnly(event.date).isBefore(today),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final recent =
        _filtered
            .where(
              (event) =>
                  event.kind != CalendarEventKind.due &&
                  !DateUtils.dateOnly(event.date).isAfter(today),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    // Móvil: usa el scroll único de la página, evitando listas anidadas.
    if (height == null) {
      return Container(
        decoration: _cardDecoration(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeading(
              'Próximos vencimientos',
              Icons.event_busy_outlined,
              _orange,
            ),
            const SizedBox(height: 12),
            if (upcoming.isEmpty)
              _emptyList('No hay vencimientos futuros registrados.')
            else
              for (final event in upcoming.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _eventRow(event, showDate: true),
                ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: _border),
            const SizedBox(height: 16),
            _sectionHeading(
              'Movimientos recientes',
              Icons.history_rounded,
              _indigo,
            ),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              _emptyList('No hay movimientos registrados con estos filtros.')
            else
              for (final event in recent.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _eventRow(event, showDate: true),
                ),
            if (widget.onOpenPayment != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => widget.onOpenPayment?.call(null),
                  label: const Text('Ver historial de pagos'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                ),
              ),
          ],
        ),
      );
    }

    // Escritorio: títulos siempre visibles y dos listas independientes.
    // El scrollbar tiene su propio controller para poder arrastrarlo.
    return Listener(
      // Mantiene el gesto de rueda dentro del panel: cuando una de las listas
      // llega a su primer o último elemento no desplaza la página de fondo.
      // Si la lista todavía puede desplazarse, Scrollable tiene prioridad
      // en el PointerSignalResolver y el movimiento funciona normalmente.
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            (_) {}, // Consume solo el scroll que las listas no utilizaron.
          );
        }
      },
      child: Container(
        height: height,
        decoration: _cardDecoration(),
        padding: const EdgeInsets.fromLTRB(17, 17, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeading(
              'Próximos vencimientos',
              Icons.event_busy_outlined,
              _orange,
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 5,
              child: _scrollableEvents(
                events: upcoming.take(20).toList(),
                controller: _dueScrollController,
                emptyMessage: 'No hay vencimientos futuros registrados.',
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: _border),
            const SizedBox(height: 14),
            _sectionHeading(
              'Movimientos recientes',
              Icons.history_rounded,
              _indigo,
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 4,
              child: _scrollableEvents(
                events: recent.take(30).toList(),
                controller: _recentScrollController,
                emptyMessage: 'No hay movimientos con estos filtros.',
              ),
            ),
            if (widget.onOpenPayment != null) ...[
              const SizedBox(height: 4),
              Align(
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
              ),
            ],
          ],
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

  Widget _sectionHeading(String title, IconData icon, Color color) => Row(
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
                      event.title,
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
    _repository = SupabaseCalendarRepository(channelKey: 'preview-${identityHashCode(this)}');
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
