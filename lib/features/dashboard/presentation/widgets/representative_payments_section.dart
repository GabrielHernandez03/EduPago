import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';

/// Historial de los pagos reportados por el representante autenticado.
///
/// Ubicación: lib/features/dashboard/presentation/widgets/representative_payments_section.dart
/// Lee el estado y los motivos reales de Supabase; nunca simula pagos.
class RepresentativePaymentsSection extends StatefulWidget {
  const RepresentativePaymentsSection({
    super.key,
    required this.representativeId,
    this.focusPaymentId,
    this.focusReference,
    this.notificationSequence = 0,
    this.onReportPayment,
  });

  final String representativeId;

  /// ID de `pagos.id` incluido en `notificaciones_app.datos`.
  final String? focusPaymentId;

  /// Se utiliza únicamente si la notificación no trae el ID del pago.
  final String? focusReference;

  /// Aumenta con cada clic para que un clic repetido abra el mismo pago.
  final int notificationSequence;
  final Future<void> Function()? onReportPayment;

  @override
  State<RepresentativePaymentsSection> createState() =>
      _RepresentativePaymentsSectionState();
}

class _RepresentativePaymentsSectionState
    extends State<RepresentativePaymentsSection> {
  static const _blue = AppColors.primaryBlue;
  static const _navy = AppColors.darkNavy;
  static const _muted = AppColors.textMuted;
  static const _border = AppColors.cardBorder;
  static const _green = Color(0xFF16845A);
  static const _orange = Color(0xFFAF6600);
  static const _red = Color(0xFFCA3545);

  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _focusedCardKey = GlobalKey();
  RealtimeChannel? _realtime;
  Timer? _reloadDelay;
  List<_ReportedPayment> _payments = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _focusedId;
  String? _notice;
  String _filter = 'todos';
  String _search = '';
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _listenToPayments();
    _loadPayments();
  }

  @override
  void didUpdateWidget(covariant RepresentativePaymentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.representativeId != widget.representativeId) {
      if (_realtime != null) {
        Supabase.instance.client.removeChannel(_realtime!);
        _realtime = null;
      }
      _listenToPayments();
      _loadPayments();
    } else if (oldWidget.focusPaymentId != widget.focusPaymentId ||
        oldWidget.focusReference != widget.focusReference ||
        oldWidget.notificationSequence != widget.notificationSequence) {
      // Un segundo clic en una notificación también lleva al nuevo pago.
      _loadPayments();
    }
  }

  @override
  void dispose() {
    _reloadDelay?.cancel();
    if (_realtime != null) {
      Supabase.instance.client.removeChannel(_realtime!);
    }
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted)
      setState(() => _search = _searchController.text.trim().toLowerCase());
  }

  void _listenToPayments() {
    if (widget.representativeId.isEmpty) return;
    _realtime = Supabase.instance.client
        .channel('historial-pagos-${widget.representativeId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pagos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'representante_id',
            value: widget.representativeId,
          ),
          callback: (_) {
            _reloadDelay?.cancel();
            _reloadDelay = Timer(const Duration(milliseconds: 450), () {
              if (mounted) _loadPayments(silent: true);
            });
          },
        )
        .subscribe();
  }

  Future<void> _loadPayments({
    bool silent = false,
    bool userInitiated = false,
  }) async {
    // La espera mínima permite percibir el feedback de carga si la respuesta
    // de Supabase llega casi instantáneamente. Solo aplica al botón/gesto.
    final minimumFeedback = userInitiated
        ? Future<void>.delayed(const Duration(milliseconds: 450))
        : null;
    final request = ++_loadVersion;
    final repId = widget.representativeId;
    if (repId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _error =
              'No encontramos el perfil del representante asociado a esta cuenta.';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = !silent && _payments.isEmpty;
        _refreshing = userInitiated;
        _error = null;
      });
    }

    try {
      final client = Supabase.instance.client;
      // El filtro por representante y la RLS protegen la privacidad de cada familia.
      final rows = await client
          .from('pagos')
          .select('*')
          .eq('representante_id', repId)
          .order('creado_at', ascending: false)
          .limit(100);

      final payments = (rows as List)
          .whereType<Map>()
          .map((v) => _ReportedPayment(Map<String, dynamic>.from(v)))
          .toList();

      // Si la notificación apunta a uno más antiguo que los 100 últimos,
      // se consulta ese registro concreto, siempre limitado al representante.
      final target = widget.focusPaymentId?.trim();
      if (target != null &&
          target.isNotEmpty &&
          !payments.any((p) => p.id == target)) {
        try {
          final extra = await client
              .from('pagos')
              .select('*')
              .eq('representante_id', repId)
              .eq('id', target)
              .maybeSingle();
          if (extra != null) payments.insert(0, _ReportedPayment(extra));
        } catch (e) {
          debugPrint('No fue posible recuperar el pago de la notificación: $e');
        }
      }

      // Relacionar cada pago con las cuotas que realmente cubre:
      // pagos.id -> pago_aplicaciones.pago_id -> cuotas.id
      // -> conceptos_cobro.id. Nunca adivinamos el mes desde la fecha del pago.
      await _loadAppliedQuotaConcepts(client, payments);

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
                ? <_ReportedPayment>[]
                : payments.where((p) => p.id == notificationId).toList();
            final matchedByReference =
                notificationId != null || reference == null
                ? <_ReportedPayment>[]
                : payments
                      .where(
                        (p) =>
                            p.reference.isNotEmpty &&
                            p.reference.toLowerCase() ==
                                reference.toLowerCase(),
                      )
                      .toList();
            // Una misma referencia puede repetirse: nunca atribuimos un
            // rechazo a varios pagos por una coincidencia ambigua.
            final matches = matchedById.isNotEmpty
                ? matchedById
                : (notificationId == null && matchedByReference.length == 1
                      ? matchedByReference
                      : <_ReportedPayment>[]);
            for (final p in matches) {
              p.addNotification(note);
            }
          }
        } catch (e) {
          debugPrint('No se pudieron recuperar las notas de notificación: $e');
        }
      }

      if (minimumFeedback != null) await minimumFeedback;
      if (!mounted ||
          widget.representativeId != repId ||
          request != _loadVersion)
        return;
      final requestedId = widget.focusPaymentId?.trim();
      final requestedReference = widget.focusReference?.trim();
      _ReportedPayment? focus;
      if (requestedId != null && requestedId.isNotEmpty) {
        for (final p in payments) {
          if (p.id == requestedId) {
            focus = p;
            break;
          }
        }
      } else if (requestedReference != null && requestedReference.isNotEmpty) {
        final matching = payments
            .where(
              (p) =>
                  p.reference.toLowerCase() == requestedReference.toLowerCase(),
            )
            .toList();
        if (matching.length == 1) focus = matching.single;
      }

      if (focus != null && _searchController.text.isNotEmpty) {
        _searchController.clear();
      }
      setState(() {
        _payments = payments;
        _loading = false;
        _refreshing = false;
        if (focus != null) {
          _focusedId = focus!.id;
          _filter = 'todos';
          _notice = null;
        } else if (requestedId != null || requestedReference != null) {
          _notice =
              'No encontramos el pago indicado por la notificación entre tus reportes.';
        } else if (widget.notificationSequence > 0) {
          _notice =
              'Esta notificación no contiene el identificador del pago. Selecciona el reporte correspondiente en el historial.';
        } else {
          _notice = null;
        }
      });
      if (focus != null) _scrollToFocused();
    } catch (e) {
      debugPrint('Error al consultar el historial de pagos: $e');
      if (minimumFeedback != null) await minimumFeedback;
      if (!mounted || request != _loadVersion) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error =
            'No se pudo cargar el historial de pagos. Comprueba tu conexión e inténtalo de nuevo.';
      });
    }
  }

  /// Lee los conceptos y períodos directamente de las cuotas aplicadas.
  /// Una asignación puede abarcar varias cuotas, conceptos o estudiantes.
  /// Los fallos de permisos/RLS o de relaciones no bloquean el historial;
  /// en ese caso se conserva la información que ya tenga `pagos`.
  Future<void> _loadAppliedQuotaConcepts(
    SupabaseClient client,
    List<_ReportedPayment> payments,
  ) async {
    final paymentIds = payments
        .map((p) => p.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (paymentIds.isEmpty) return;

    // Si un reporte conserva una cuota_id directa, también funciona cuando
    // la aplicación contable aún no se ha registrado (pago en revisión).
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
        if (values is! List) continue;
        for (final value in values) {
          final id = value?.toString().trim() ?? '';
          if (id.isNotEmpty) {
            quotaIdsByPayment.putIfAbsent(payment.id, () => <String>{}).add(id);
          }
        }
      }
    }

    try {
      final applicationRows = await client
          .from('pago_aplicaciones')
          .select('pago_id, cuota_id')
          .inFilter('pago_id', paymentIds);

      // Se preservan las aplicaciones por pago y se eliminan duplicados.
      for (final row in applicationRows) {
        final paymentId = row['pago_id']?.toString().trim() ?? '';
        final quotaId = row['cuota_id']?.toString().trim() ?? '';
        if (paymentId.isEmpty || quotaId.isEmpty) continue;
        quotaIdsByPayment.putIfAbsent(paymentId, () => <String>{}).add(quotaId);
      }
    } catch (e) {
      // El historial sigue funcionando si faltan permisos de lectura (RLS).
      debugPrint('No se pudieron consultar las aplicaciones de pagos: $e');
    }

    try {
      final quotaIds = quotaIdsByPayment.values
          .expand((ids) => ids)
          .toSet()
          .toList();
      if (quotaIds.isEmpty) return;
      final quotaRows = await client
          .from('cuotas')
          .select('id, periodo, concepto_id')
          .inFilter('id', quotaIds);
      final quotaById = <String, Map<String, dynamic>>{
        for (final row in quotaRows)
          row['id'].toString(): Map<String, dynamic>.from(row),
      };

      final conceptIds = quotaRows
          .map((q) => q['concepto_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final conceptById = <String, String>{};
      if (conceptIds.isNotEmpty) {
        try {
          // `select('*')` permite leer el nombre aunque la instalación use
          // nombre, descripcion, titulo o tipo para el concepto.
          final concepts = await client
              .from('conceptos_cobro')
              .select('*')
              .inFilter('id', conceptIds);
          for (final concept in concepts) {
            final id = concept['id']?.toString() ?? '';
            final name = _firstField(concept, [
              'nombre',
              'nombre_concepto',
              'titulo',
              'descripcion',
              'concepto',
              'tipo',
            ]);
            if (id.isNotEmpty && name.isNotEmpty) conceptById[id] = name;
          }
        } catch (e) {
          debugPrint('No se pudieron consultar los conceptos de cobro: $e');
        }
      }

      for (final payment in payments) {
        final ids = quotaIdsByPayment[payment.id];
        if (ids == null || ids.isEmpty) continue;
        final labels = <String>[];
        final periods = <String>[];
        final concepts = <String>[];
        for (final id in ids) {
          final quota = quotaById[id];
          if (quota == null) continue;
          final period = _firstField(quota, ['periodo']);
          final concept =
              conceptById[quota['concepto_id']?.toString() ?? ''] ?? '';
          final label = _quotaDescription(concept, period);
          if (label.isNotEmpty && !labels.contains(label)) labels.add(label);
          if (period.isNotEmpty && !periods.contains(period))
            periods.add(period);
          if (concept.isNotEmpty && !concepts.contains(concept)) {
            concepts.add(concept);
          }
        }
        payment.setAppliedQuotaLabels(
          labels,
          ids.length,
          concepts: concepts,
          periods: periods,
        );
      }
    } catch (e) {
      debugPrint('No se pudo consultar la relación pago-cuota: $e');
    }
  }

  static String _firstField(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  static String _quotaDescription(String concept, String period) {
    if (concept.isEmpty) return period;
    if (period.isEmpty) return concept;
    // Ej.: «Mensualidad de Octubre 2026». Otros conceptos conservan su
    // denominación real, como «Inscripción · Septiembre 2026».
    if (concept.toLowerCase() == 'mensualidad') return '$concept de $period';
    return '$concept · $period';
  }

  static String? _paymentIdFromMetadata(Map<String, dynamic> data) {
    for (final key in ['pago_id', 'id_pago', 'payment_id']) {
      final id = data[key]?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }
    final nested = data['pago'];
    if (nested is Map) {
      for (final key in ['id', 'pago_id']) {
        final id = nested[key]?.toString().trim();
        if (id != null && id.isNotEmpty) return id;
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
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  void _scrollToFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _focusedCardKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
        alignment: 0.14,
      );
    });
  }

  Future<void> _report() async {
    final callback = widget.onReportPayment;
    if (callback == null) return;
    await callback();
    if (mounted) await _loadPayments(silent: true);
  }

  List<_ReportedPayment> get _visible {
    return _payments.where((p) {
      if (_filter != 'todos' && p.normalizedStatus != _filter) return false;
      if (_search.isEmpty) return true;
      return [
        p.reference,
        p.concept,
        p.installmentLabel,
        p.method,
        p.id,
        p.statusLabel,
      ].any((s) => s.toLowerCase().contains(_search));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final noReports = !_loading && _payments.isEmpty;
    return ScrollConfiguration(
      // Flutter web dibuja una barra automática incluso en recorridos
      // mínimos. Sin reportes no mostramos barra ni forzamos el gesto.
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(scrollbars: !noReports),
      child: RefreshIndicator(
        onRefresh: () => _loadPayments(silent: true, userInitiated: true),
        color: _blue,
        child: SingleChildScrollView(
          physics: noReports
              ? const ClampingScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            width < 640 ? 18 : (width < 900 ? 28 : 48),
            26,
            width < 640 ? 18 : (width < 900 ? 28 : 48),
            noReports ? 16 : 38,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mis pagos',
                            style: TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            'Consulta tus reportes, su revisión y las respuestas del colegio.',
                            style: TextStyle(color: _muted, fontSize: 14),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _refreshing
                                ? null
                                : () => _loadPayments(
                                    silent: true,
                                    userInitiated: true,
                                  ),
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _refreshing
                                  ? const SizedBox(
                                      key: ValueKey('updating-payments'),
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: _blue,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.refresh_rounded,
                                      key: ValueKey('idle-payments'),
                                      size: 18,
                                    ),
                            ),
                            label: Text(
                              _refreshing ? 'Actualizando...' : 'Actualizar',
                            ),
                          ),
                          if (widget.onReportPayment != null)
                            FilledButton.icon(
                              onPressed: _report,
                              style: FilledButton.styleFrom(
                                backgroundColor: _blue,
                              ),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Reportar pago'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  if (_notice != null) ...[
                    _alert(
                      _notice!,
                      const Color(0xFF9A6600),
                      Icons.info_outline,
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_error != null) ...[
                    _alert(_error!, _red, Icons.error_outline),
                    const SizedBox(height: 14),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 100),
                    const Center(
                      child: CircularProgressIndicator(color: _blue),
                    ),
                  ] else ...[
                    LayoutBuilder(
                      builder: (context, box) {
                        final compact = box.maxWidth < 590;
                        final stats = [
                          _summary(
                            'En espera',
                            _payments
                                .where((p) => p.normalizedStatus == 'pendiente')
                                .length,
                            Icons.schedule_rounded,
                            _orange,
                          ),
                          _summary(
                            'Aprobados',
                            _payments
                                .where((p) => p.normalizedStatus == 'aprobado')
                                .length,
                            Icons.check_circle_outline_rounded,
                            _green,
                          ),
                          _summary(
                            'Rechazados',
                            _payments
                                .where((p) => p.normalizedStatus == 'rechazado')
                                .length,
                            Icons.highlight_off_rounded,
                            _red,
                          ),
                        ];
                        return compact
                            ? Column(
                                children: [
                                  for (final card in stats) ...[
                                    card,
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              )
                            : Row(
                                children: [
                                  for (var i = 0; i < stats.length; i++) ...[
                                    Expanded(child: stats[i]),
                                    if (i < stats.length - 1)
                                      const SizedBox(width: 14),
                                  ],
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              Text(
                                'Últimos pagos reportados',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                '${_visible.length} de ${_payments.length} reportes',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          // No tiene sentido mostrar búsqueda y filtros si no
                          // existe ningún reporte; además evita scroll residual.
                          if (_payments.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: width < 640
                                    ? 'Buscar un pago...'
                                    : 'Buscar por referencia, concepto o período...',
                                hintStyle: const TextStyle(
                                  color: _muted,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  size: 23,
                                  color: Color(0xFF6381B5),
                                ),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'Limpiar búsqueda',
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: _searchController.clear,
                                      )
                                    : null,
                                filled: true,
                                fillColor: const Color(0xFFF2F6FC),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 15,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFEDF1F9),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: const BorderSide(
                                    color: _blue,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _filterChip('todos', 'Todos'),
                                  const SizedBox(width: 8),
                                  _filterChip('pendiente', 'En espera'),
                                  const SizedBox(width: 8),
                                  _filterChip('aprobado', 'Aprobados'),
                                  const SizedBox(width: 8),
                                  _filterChip('rechazado', 'Rechazados'),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_visible.isEmpty)
                      Container(
                        decoration: _cardDecoration(),
                        padding: EdgeInsets.symmetric(
                          vertical: _payments.isEmpty ? 28 : 40,
                          horizontal: 16,
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              color: _blue,
                              size: 38,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _payments.isEmpty
                                  ? 'Aún no has reportado ningún pago.'
                                  : 'No hay pagos que coincidan con estos filtros.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: _muted),
                            ),
                            if (_payments.isEmpty) ...[
                              const SizedBox(height: 7),
                              const Text(
                                'Los pagos que reportes aparecerán aquí.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      for (final payment in _visible) ...[
                        Container(
                          key: payment.id == _focusedId
                              ? _focusedCardKey
                              : null,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: _paymentCard(payment),
                        ),
                      ],
                    if (_payments.length >= 100)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Se muestran los 100 reportes más recientes.',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(String label, int count, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      decoration: _cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFE7F0FF),
      side: BorderSide(color: selected ? _blue : _border),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selected ? _blue : _muted,
        fontSize: 12,
      ),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _paymentCard(_ReportedPayment payment) {
    final open = payment.id == _focusedId;
    final status = payment.normalizedStatus;
    final color = status == 'aprobado'
        ? _green
        : (status == 'rechazado' ? _red : _orange);
    final icon = status == 'aprobado'
        ? Icons.check_circle_rounded
        : (status == 'rechazado'
              ? Icons.cancel_rounded
              : Icons.schedule_rounded);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      decoration: _cardDecoration(highlight: open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () =>
                  setState(() => _focusedId = open ? null : payment.id),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    // Escritorio: referencia | cuota | monto y estado.
                    // Móvil/tablet: las mismas áreas apiladas con equilibrio.
                    final compact = bounds.maxWidth < 740;
                    final arrow = Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _muted,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (compact) ...[
                          _paymentIdentity(payment, icon, color),
                          const SizedBox(height: 14),
                          _paymentInstallment(payment),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _paymentAmount(payment),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _statusBadge(payment.statusLabel, icon, color),
                              const SizedBox(width: 5),
                              arrow,
                            ],
                          ),
                        ] else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 4,
                                child: _paymentIdentity(payment, icon, color),
                              ),
                              const SizedBox(width: 18),
                              Container(width: 1, height: 48, color: _border),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 4,
                                child: _paymentInstallment(payment),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _paymentAmount(payment),
                                    const SizedBox(height: 7),
                                    _statusBadge(
                                      payment.statusLabel,
                                      icon,
                                      color,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              arrow,
                            ],
                          ),
                        ],
                        if (status == 'rechazado') ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF2F2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              payment.rejectionReasons.isEmpty
                                  ? 'Rechazado. Toca para consultar los detalles.'
                                  : 'Motivo: ${payment.rejectionReasons.first}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: _red),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 230),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1, color: _border),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: _details(payment),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _paymentIdentity(
    _ReportedPayment payment,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
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
                'Pago ${payment.displayReference}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: _navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _date(payment.createdAt),
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentInstallment(_ReportedPayment payment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          payment.installmentHeading,
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: _blue, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                payment.installmentCardValue,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (!payment.installmentLabel.toLowerCase().contains(
              payment.concept.toLowerCase(),
            ) &&
            payment.concept.toLowerCase() != 'pago escolar') ...[
          const SizedBox(height: 4),
          Text(
            payment.concept,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _paymentAmount(_ReportedPayment payment) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        payment.displayAmount,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: _navy,
        ),
      ),
    );
  }

  Widget _details(_ReportedPayment payment) {
    final status = payment.normalizedStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detalle del pago',
          style: TextStyle(
            color: _navy,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 26,
          runSpacing: 16,
          children: [
            _detail('Estado', payment.statusLabel),
            _detail('Fecha del reporte', _date(payment.createdAt)),
            if (payment.paymentDate != null)
              _detail('Fecha del pago', _date(payment.paymentDate)),
            _detail('Monto reportado', payment.displayAmount),
            _detail('Concepto y período', payment.installmentLabel),
            if (!payment.installmentLabel.toLowerCase().contains(
                  payment.concept.toLowerCase(),
                ) &&
                payment.concept.toLowerCase() != 'pago escolar')
              _detail('Concepto', payment.concept),
            if (payment.method.isNotEmpty)
              _detail('Método de pago', payment.method),
            if (payment.reference.isNotEmpty)
              _detail('Referencia', payment.reference),
            if (payment.bank.isNotEmpty) _detail('Banco', payment.bank),
            if (payment.confirmedAt != null)
              _detail('Fecha de revisión', _date(payment.confirmedAt)),
            _detail('Identificador', payment.id),
          ],
        ),
        const SizedBox(height: 18),
        if (status == 'rechazado') ...[
          const Text(
            'Motivos del rechazo',
            style: TextStyle(
              color: _red,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (payment.rejectionReasons.isEmpty)
            const Text(
              'El colegio no registró un motivo de rechazo visible en este reporte. Comunícate con administración para solicitar la explicación.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
            )
          else
            for (final reason in payment.rejectionReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: _red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reason,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ] else if (status == 'pendiente')
          _alert(
            'Tu pago fue reportado y está esperando la revisión de la administración. Todavía no se ha aplicado como aprobado.',
            _orange,
            Icons.schedule_outlined,
          )
        else if (status == 'aprobado')
          _alert(
            'Tu pago fue aprobado por la administración del colegio.',
            _green,
            Icons.verified_outlined,
          ),
        if (payment.otherNotes.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Observaciones',
            style: TextStyle(
              color: _navy,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 7),
          for (final note in payment.otherNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '• $note',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ),
        ],
      ],
    );
  }

  Widget _detail(String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 330),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(
              color: _navy,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _alert(String message, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration({bool highlight = false}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    border: Border.all(
      color: highlight ? _blue : _border,
      width: highlight ? 1.5 : 1,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(
          0xFF1B4785,
        ).withValues(alpha: highlight ? 0.09 : 0.035),
        blurRadius: 20,
        offset: const Offset(0, 5),
      ),
    ],
  );

  static String _date(DateTime? d) {
    if (d == null) return 'No disponible';
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} · ${two(local.hour)}:${two(local.minute)}';
  }
}

/// Modelo flexible: el backend puede incluir columnas adicionales o distintas
/// versiones de nombres sin bloquear la pantalla.
class _ReportedPayment {
  final Map<String, dynamic> raw;
  final List<Map<String, dynamic>> _notifications = [];
  List<String> _appliedQuotaLabels = const [];
  List<String> _appliedConcepts = const [];
  List<String> _appliedPeriods = const [];
  int _appliedQuotaCount = 0;

  _ReportedPayment(this.raw);

  void setAppliedQuotaLabels(
    List<String> labels,
    int quotaCount, {
    List<String> concepts = const [],
    List<String> periods = const [],
  }) {
    _appliedQuotaLabels = labels;
    _appliedQuotaCount = quotaCount;
    _appliedConcepts = concepts;
    _appliedPeriods = periods;
  }

  /// Muestra el tipo real del concepto (por ejemplo, MENSUALIDAD).
  String get installmentHeading {
    if (_appliedConcepts.length == 1) {
      return _appliedConcepts.single.toUpperCase();
    }
    if (_appliedConcepts.length > 1) return 'CONCEPTOS DEL PAGO';
    if (_appliedPeriods.isNotEmpty) return 'PERÍODO DE LA CUOTA';
    return 'CONCEPTO DEL PAGO';
  }

  /// Cuando existe un concepto único, dejamos el mes en la segunda línea,
  /// evitando repetir «Mensualidad» tanto en el encabezado como en el valor.
  String get installmentCardValue {
    if (_appliedConcepts.length == 1 && _appliedPeriods.isNotEmpty) {
      final label = _appliedPeriods.join(' · ');
      return _appliedQuotaCount > _appliedPeriods.length
          ? '$label (${_appliedQuotaCount} cuotas)'
          : label;
    }
    return installmentLabel;
  }

  String _get(List<String> keys) {
    for (final k in keys) {
      final str = raw[k]?.toString().trim() ?? '';
      if (str.isNotEmpty && str.toLowerCase() != 'null') return str;
    }
    return '';
  }

  String get id => _get(['id']);
  String get shortId => id.length > 8 ? id.substring(0, 8) : id;
  String get displayReference =>
      reference.isEmpty ? '#$shortId' : '· $reference';
  String get reference => _get([
    'referencia',
    'referencia_pago',
    'referencia_bancaria',
    'numero_referencia',
    'nro_referencia',
    'numero_operacion',
  ]);
  String get method {
    final rawMethod = _get([
      'metodo_pago',
      'metodo',
      'medio_pago',
      'tipo_pago',
    ]);
    return switch (rawMethod.toLowerCase()) {
      'pago_movil' || 'pago móvil' || 'pago movil' => 'Pago móvil',
      'transferencia_bancaria' => 'Transferencia bancaria',
      'efectivo_usd' => 'Efectivo USD',
      _ => rawMethod,
    };
  }

  String get bank => _get(['banco', 'banco_emisor', 'entidad_bancaria']);
  String get concept =>
      _get([
        'concepto',
        'descripcion',
        'periodo',
        'observacion_concepto',
      ]).isEmpty
      ? 'Pago escolar'
      : _get(['concepto', 'descripcion', 'periodo', 'observacion_concepto']);

  /// Prioriza los conceptos reales de pago_aplicaciones -> cuotas y
  /// conceptos_cobro. Si no hay aplicaciones, usa campos explícitos de pagos.
  /// Nunca infiere la mensualidad según la fecha o el monto depositado.
  String get installmentLabel {
    if (_appliedQuotaLabels.isNotEmpty) {
      final label = _appliedQuotaLabels.join(' · ');
      // Una familia puede pagar la misma mensualidad de varios estudiantes.
      return _appliedQuotaCount > _appliedQuotaLabels.length
          ? '$label (${_appliedQuotaCount} cuotas)'
          : label;
    }

    final named = _get([
      'nombre_cuota',
      'cuota_nombre',
      'nombre_mensualidad',
      'mensualidad',
      'concepto_cuota',
      'periodo_cuota',
      'cuota_periodo',
      'periodo_pagado',
      'mes_correspondiente',
    ]);
    if (named.isNotEmpty) return named;

    // Si el backend conserva las cuotas en un JSON o arreglo, mostramos los
    // nombres disponibles; nunca mostramos UUIDs como si fueran cuotas.
    final assigned = <String>[];
    for (final key in ['cuotas', 'mensualidades', 'detalle_cuotas']) {
      final data = raw[key];
      if (data is! List) continue;
      for (final entry in data) {
        if (entry is! Map) continue;
        final detail = Map<String, dynamic>.from(entry);
        for (final candidate in [
          'nombre_cuota',
          'concepto',
          'periodo',
          'nombre',
          'mes',
        ]) {
          final value = detail[candidate]?.toString().trim() ?? '';
          if (value.isNotEmpty && !assigned.contains(value)) {
            assigned.add(value);
            break;
          }
        }
      }
    }
    if (assigned.isNotEmpty) return assigned.join(' · ');

    final month = _get(['mes_cuota', 'mes_mensualidad', 'mes_pagado', 'mes']);
    final year = _get(['anio_cuota', 'ano_cuota', 'anio', 'ano', 'año']);
    if (month.isNotEmpty) {
      const months = [
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
      final n = int.tryParse(month);
      final name = n != null && n >= 1 && n <= 12 ? months[n - 1] : month;
      return year.isEmpty ? name : '$name $year';
    }

    final number = _get(['numero_cuota', 'nro_cuota', 'cuota_numero']);
    if (number.isNotEmpty) return 'Cuota $number';

    final period = _get(['periodo']);
    if (period.isNotEmpty) return period;

    // Algunas instalaciones solo guardan la cuota dentro del concepto.
    final description = _get([
      'concepto',
      'descripcion',
      'observacion_concepto',
    ]);
    if (RegExp(
      r'\b(mensualidad|cuota|inscripci[oó]n|matr[ií]cula|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\b',
      caseSensitive: false,
    ).hasMatch(description)) {
      return description;
    }
    return 'Cuota no especificada';
  }

  DateTime? _date(List<String> keys) {
    for (final k in keys) {
      final result = DateTime.tryParse(raw[k]?.toString() ?? '');
      if (result != null) return result;
    }
    return null;
  }

  DateTime? get createdAt => _date(['creado_at', 'created_at']);
  DateTime? get paymentDate => _date(['fecha_pago']);
  DateTime? get confirmedAt =>
      _date(['revisado_at', 'fecha_revision', 'aprobado_at', 'actualizado_at']);

  String get normalizedStatus {
    final status = _get(['estado', 'status']).toLowerCase().trim();
    if (['aprobado', 'aprobada', 'validado', 'confirmado'].contains(status))
      return 'aprobado';
    if (['rechazado', 'rechazada', 'denegado', 'invalidado'].contains(status))
      return 'rechazado';
    if ([
      'pendiente',
      'en_revision',
      'en revisión',
      'en_espera',
      'reportado',
      'espera',
      'en espera',
    ].contains(status))
      return 'pendiente';
    return status.isEmpty ? 'pendiente' : status;
  }

  String get statusLabel => switch (normalizedStatus) {
    'pendiente' => 'En espera',
    'aprobado' => 'Aprobado',
    'rechazado' => 'Rechazado',
    final other => other,
  };

  String get displayAmount {
    final rawAmount = raw['monto'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse('$rawAmount') ?? 0;
    final fixed = amount.abs().toStringAsFixed(2).split('.');
    final n = fixed[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final text = '${amount < 0 ? '-' : ''}$n,${fixed[1]}';
    final currency = _get(['moneda']).toUpperCase();
    return currency == 'VES' || currency == 'BS' || currency == 'BS.'
        ? 'Bs. $text'
        : '\$$text ${currency.isEmpty ? 'USD' : currency}';
  }

  void addNotification(Map<String, dynamic> item) => _notifications.add(item);

  static void _append(List<String> output, Set<String> seen, dynamic value) {
    if (value == null) return;
    if (value is List) {
      for (final sub in value) {
        _append(output, seen, sub);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        _append(output, seen, entry.value);
      }
      return;
    }
    final text = value.toString().trim();
    if (text.isEmpty || ['null', 'false', 'true'].contains(text.toLowerCase()))
      return;
    if (seen.add(text.toLowerCase())) output.add(text);
  }

  List<String> get rejectionReasons {
    final values = <String>[];
    final seen = <String>{};
    for (final entry in raw.entries) {
      final k = entry.key.toLowerCase();
      if (k.contains('motivo') ||
          k.contains('razon_rechazo') ||
          k.contains('razón') ||
          k.contains('justificacion') ||
          k.contains('causa_rechazo') ||
          k.contains('detalle_rechazo') ||
          (normalizedStatus == 'rechazado' &&
              (k.contains('observ') ||
                  k.contains('comentario') ||
                  k.contains('nota_rechazo') ||
                  k.contains('nota_admin')))) {
        _append(values, seen, entry.value);
      }
    }
    if (normalizedStatus == 'rechazado') {
      for (final k in [
        'observaciones',
        'observacion',
        'observacion_admin',
        'observaciones_admin',
        'comentario_admin',
        'comentarios_admin',
        'nota_admin',
      ]) {
        _append(values, seen, raw[k]);
      }
    }
    for (final note in _notifications) {
      if (note['tipo']?.toString() != 'pago_rechazado') continue;
      final data = note['datos'];
      if (data is Map) {
        for (final item in data.entries) {
          final name = item.key.toString().toLowerCase();
          if (name.contains('motivo') ||
              name.contains('razon') ||
              name.contains('observacion') ||
              name.contains('comentario')) {
            _append(values, seen, item.value);
          }
        }
      }
      // Solo tratamos el mensaje como motivo si explicita alguna causa.
      // Una notificación genérica «Pago rechazado» NO es un motivo.
      final message = note['mensaje']?.toString() ?? '';
      if (RegExp(
        r'motivo|raz[oó]n|debido|porque|causa|inconsisten|incorrect|inv[aá]lid',
        caseSensitive: false,
      ).hasMatch(message)) {
        _append(values, seen, message);
      }
    }
    return values;
  }

  List<String> get otherNotes {
    final result = <String>[];
    final seen = <String>{};
    if (normalizedStatus != 'rechazado') {
      for (final key in [
        'observaciones',
        'observacion',
        'comentario_admin',
        'nota_admin',
      ]) {
        _append(result, seen, raw[key]);
      }
    } else {
      for (final note in _notifications) {
        if (note['tipo']?.toString() == 'pago_rechazado') {
          final message = note['mensaje']?.toString().trim() ?? '';
          if (message.isNotEmpty && !rejectionReasons.contains(message)) {
            _append(result, seen, 'Mensaje de notificación: $message');
          }
        }
      }
    }
    return result;
  }
}
