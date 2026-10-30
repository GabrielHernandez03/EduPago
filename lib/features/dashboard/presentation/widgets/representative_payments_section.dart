import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/account_status_service.dart';
import '../../../../core/widgets/skeleton_loader.dart';

/// Historial de los pagos reportados por el representante autenticado.
/// Vista revisada 2026-10-30: concepto mensual por periodo y desglose USD
/// por estudiante basado en pago_aplicaciones. Sin fecha del pago en detalle.
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

  final AccountStatusService _accountStatusService = AccountStatusService();
  EstadoCuenta? _currentAccount;
  bool _accountLoading = true;

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

  // Agrupación del historial por fecha real del reporte, no por la cuota.
  // Los grupos se muestran abiertos por defecto; el usuario puede cerrarlos.
  final Set<String> _collapsedMonths = <String>{};
  final Set<String> _collapsedDays = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _listenToPayments();
    _loadPayments();
    _loadCurrentAccount();
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
      _loadCurrentAccount();
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
    if (!mounted) return;
    final query = _searchController.text.trim().toLowerCase();
    if (query == _search) return;
    setState(() {
      _search = query;
      // Los resultados de cada búsqueda se muestran inicialmente abiertos;
      // luego el usuario puede plegar meses y días libremente.
      _collapsedMonths.clear();
      _collapsedDays.clear();
    });
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

  Future<void> _loadCurrentAccount() async {
    final repId = widget.representativeId;
    if (repId.isEmpty) {
      if (mounted)
        setState(() {
          _currentAccount = null;
          _accountLoading = false;
        });
      return;
    }
    if (mounted) setState(() => _accountLoading = _currentAccount == null);
    EstadoCuenta? result;
    try {
      result = await _accountStatusService.getEstadoCuenta(
        representanteId: repId,
      );
    } catch (e) {
      debugPrint('No se pudo consultar el estado de cuenta en Mis pagos: $e');
    }
    if (!mounted || widget.representativeId != repId) return;
    setState(() {
      _currentAccount = result;
      _accountLoading = false;
    });
  }

  Widget _buildAccountSnapshot() {
    if (_accountLoading) {
      return const SkeletonScope(
        child: SkeletonCard(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              SkeletonBox(width: 42, height: 42, radius: 12),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 160, height: 15),
                    SizedBox(height: 10),
                    SkeletonBox(width: 240, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final account = _currentAccount;
    if (account == null) {
      return _PaymentHoverSurface(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: _muted, size: 21),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Estado de cuenta no disponible por el momento.',
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final pending = account.totalPendienteUsd;
    final reviewing = account.enRevisionUsd;
    final solvent = account.esSolvente;
    final tone = solvent ? _green : _orange;
    String money(double value) =>
        '\$${value.toStringAsFixed(2).replaceAll('.', ',')} USD';
    return _PaymentHoverSurface(
      hoverColor: tone,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        decoration: _cardDecoration(),
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 560;
            final heading = Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    solvent
                        ? Icons.verified_outlined
                        : Icons.account_balance_wallet_outlined,
                    color: tone,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estado de cuenta actual',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        solvent
                            ? 'Tu familia está solvente'
                            : 'Saldo familiar pendiente',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final amount = Column(
              crossAxisAlignment: narrow
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  solvent ? 'SOLVENTE' : money(pending),
                  style: TextStyle(
                    color: solvent ? _green : _navy,
                    fontWeight: FontWeight.w800,
                    fontSize: solvent ? 15 : 19,
                  ),
                ),
                if (reviewing > 0.01) ...[
                  const SizedBox(height: 5),
                  Text(
                    '${money(reviewing)} en revisión',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ],
            );
            return narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [heading, const SizedBox(height: 12), amount],
                  )
                : Row(
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: 16),
                      amount,
                    ],
                  );
          },
        ),
      ),
    );
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
          // Si el reporte proviene de una notificación, se expande su mes y
          // su día para que Scrollable.ensureVisible encuentre la tarjeta.
          final localDate = focus.createdAt?.toLocal();
          if (localDate != null) {
            _collapsedMonths.remove(_monthGroupKey(localDate));
            _collapsedDays.remove(_dayGroupKey(localDate));
          } else {
            _collapsedMonths.remove('sin-fecha');
            _collapsedDays.remove('sin-fecha');
          }
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

  /// Obtiene concepto y período de las cuotas realmente aplicadas.
  /// Para pagos aún en revisión (que no tienen pago_aplicaciones), calcula
  /// una PREVISIÓN de FIFO, sin confundirla con una aplicación contabilizada.
  /// Una transacción puede cubrir varias cuotas y varios estudiantes.
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
        if (values is! List) continue;
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
        if (paymentId.isEmpty || quotaId.isEmpty) continue;
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
            .eq('representante_id', widget.representativeId);
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
    if (allQuotaIds.isEmpty) return;

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
            if (id.isNotEmpty && name.isNotEmpty) conceptById[id] = name;
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
            if (id.isNotEmpty && name.isNotEmpty) studentById[id] = name;
          }
        } catch (e) {
          debugPrint('No se pudieron consultar nombres de estudiantes: $e');
        }
      }

      String conceptFor(Map<String, dynamic> quota) {
        final direct = _firstField(quota, ['concepto', 'nombre_concepto']);
        if (direct.isNotEmpty) return direct;
        return conceptById[quota['concepto_id']?.toString() ?? ''] ?? '';
      }

      // Los conceptos se agrupan por mensualidad (no por estudiante).
      // El importe de cada estudiante se calcula EXCLUSIVAMENTE a partir de
      // pago_aplicaciones: no se divide el pago entre hijos por aproximación.
      void assign(
        _ReportedPayment payment,
        List<String> quotaIds, {
        required bool estimated,
      }) {
        final lines = <String>[];
        final periods = <String>[];
        final concepts = <String>[];
        for (final id in quotaIds) {
          final quota = quotaById[id];
          if (quota == null) continue;
          final concept = conceptFor(quota);
          final period = _firstField(quota, ['periodo', 'mes_periodo']);
          final label = _quotaDescription(concept, period);
          if (label.isEmpty) continue;
          if (!lines.contains(label)) lines.add(label);
          if (concept.isNotEmpty && !concepts.contains(concept)) {
            concepts.add(concept);
          }
          if (period.isNotEmpty && !periods.contains(period)) {
            periods.add(period);
          }
        }
        if (lines.isEmpty) return;
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
        if (explicit == null || explicit.isEmpty) continue;
        assign(
          payment,
          explicit.toList(),
          estimated: payment.normalizedStatus == 'pendiente',
        );

        final apps = applicationsByPayment[payment.id];
        if (apps == null ||
            apps.isEmpty ||
            payment.normalizedStatus != 'aprobado')
          continue;

        // Agrupar el importe aplicado por estudiante, sumando las distintas
        // mensualidades que cubra este pago para una misma persona.
        final grouped = <String, _StudentPaymentAllocation>{};
        for (final app in apps) {
          final quotaId = app['cuota_id']?.toString().trim() ?? '';
          final quota = quotaById[quotaId];
          if (quota == null) continue;
          final studentId = quota['estudiante_id']?.toString().trim() ?? '';
          if (studentId.isEmpty) continue;
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
          grouped[studentId] = _StudentPaymentAllocation(
            name: name,
            amountUsd: total,
            quotaCount: (previous?.quotaCount ?? 0) + 1,
          );
        }
        if (grouped.isNotEmpty) {
          payment.setStudentAllocations(grouped.values.toList());
        }
      }

      if (pendingBalances.isEmpty) return;
      // Esta vista previa replica el orden FIFO esperado, NO una distribución
      // confirmada. Se descuentan las vistas previas de otros pagos pendientes
      // para evitar mostrar la misma cuota dos veces por simple acumulación.
      final available = <String, double>{};
      for (final row in pendingBalances) {
        final id = row['cuota_id']?.toString() ?? '';
        final saldo = _asAmount(row['saldo_usd']);
        if (quotaById.containsKey(id) && saldo > 0.01) available[id] = saldo;
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
        if (remaining <= 0.01) continue;
        final targetIds = <String>[];
        for (final id in sortedIds) {
          final due = available[id] ?? 0;
          if (due <= 0.01 || remaining <= 0.01) continue;
          final applied = remaining < due ? remaining : due;
          remaining -= applied;
          available[id] = due - applied;
          targetIds.add(id);
        }
        if (targetIds.isNotEmpty) assign(payment, targetIds, estimated: true);
      }
    } catch (e) {
      debugPrint('No se pudo leer la información de cuotas: $e');
    }
  }

  static double _asAmount(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static double? _firstNumeric(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final raw = row[key];
      if (raw == null) continue;
      final value = raw is num
          ? raw.toDouble()
          : double.tryParse(raw.toString());
      if (value != null && value.isFinite && value >= 0) return value;
    }
    return null;
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
        ...p.quotaDetails,
        p.method,
        p.id,
        p.statusLabel,
      ].any((s) => s.toLowerCase().contains(_search));
    }).toList();
  }

  String _monthGroupKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  String _dayGroupKey(DateTime date) =>
      '${_monthGroupKey(date)}-${date.day.toString().padLeft(2, '0')}';

  static const _reportMonths = <String>[
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
  static const _reportWeekdays = <String>[
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  String _monthTitle(DateTime? date) {
    if (date == null) return 'Sin fecha de reporte';
    final month = _reportMonths[date.month - 1];
    return '${month[0].toUpperCase()}${month.substring(1)} ${date.year}';
  }

  String _dayTitle(DateTime? date) {
    if (date == null) return 'Fecha no disponible';
    final weekday = _reportWeekdays[date.weekday - 1];
    final name = '${weekday[0].toUpperCase()}${weekday.substring(1)}';
    return '$name ${date.day} de ${_reportMonths[date.month - 1]}';
  }

  // Orden descendente por fecha de reporte y, dentro de cada fecha, por hora.
  // Las fechas ausentes van al final, sin usar fecha_pago como sustituto.
  List<_ReportMonthGroup> _groupByReportDate(List<_ReportedPayment> items) {
    final sorted = List<_ReportedPayment>.of(items)
      ..sort((a, b) {
        final left = a.createdAt?.toLocal();
        final right = b.createdAt?.toLocal();
        if (left == null && right == null) return a.id.compareTo(b.id);
        if (left == null) return 1;
        if (right == null) return -1;
        final result = right.compareTo(left);
        return result != 0 ? result : a.id.compareTo(b.id);
      });
    final buckets = <String, Map<String, List<_ReportedPayment>>>{};
    final monthDates = <String, DateTime?>{};
    final dayDates = <String, DateTime?>{};

    for (final payment in sorted) {
      final date = payment.createdAt?.toLocal();
      final monthKey = date == null ? 'sin-fecha' : _monthGroupKey(date);
      final dayKey = date == null ? 'sin-fecha' : _dayGroupKey(date);
      monthDates[monthKey] = date == null
          ? null
          : DateTime(date.year, date.month);
      dayDates[dayKey] = date == null
          ? null
          : DateTime(date.year, date.month, date.day);
      final days = buckets.putIfAbsent(
        monthKey,
        () => <String, List<_ReportedPayment>>{},
      );
      days.putIfAbsent(dayKey, () => <_ReportedPayment>[]).add(payment);
    }

    return [
      for (final month in buckets.entries)
        _ReportMonthGroup(
          key: month.key,
          date: monthDates[month.key],
          days: [
            for (final day in month.value.entries)
              _ReportDayGroup(
                key: day.key,
                date: dayDates[day.key],
                payments: day.value,
              ),
          ],
        ),
    ];
  }

  // El estado plegado siempre se respeta, incluso con filtros y búsqueda.
  // Los cambios de criterio abren los resultados una sola vez, no en cada build.

  Widget _monthGroup(_ReportMonthGroup group) {
    final collapsed = _collapsedMonths.contains(group.key);
    final amount = group.days.fold<int>(
      0,
      (sum, day) => sum + day.payments.length,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() {
                if (!_collapsedMonths.add(group.key)) {
                  _collapsedMonths.remove(group.key);
                }
              }),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD7E4FC)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      color: _blue,
                      size: 21,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        _monthTitle(group.date),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                    ),
                    Text(
                      '$amount ${amount == 1 ? 'pago' : 'pagos'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _blue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      color: _blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(height: 13),
            for (final day in group.days) _dayGroup(day),
          ],
        ],
      ),
    );
  }

  Widget _dayGroup(_ReportDayGroup group) {
    final collapsed = _collapsedDays.contains(group.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() {
                if (!_collapsedDays.add(group.key)) {
                  _collapsedDays.remove(group.key);
                }
              }),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined, color: _muted, size: 18),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _dayTitle(group.date),
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${group.payments.length} ${group.payments.length == 1 ? 'pago' : 'pagos'}',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 20,
                      color: _muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed)
            for (final payment in group.payments)
              Container(
                key: payment.id == _focusedId ? _focusedCardKey : null,
                margin: const EdgeInsets.only(bottom: 12),
                child: _paymentCard(payment),
              ),
        ],
      ),
    );
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
        onRefresh: () async {
          await Future.wait([
            _loadPayments(silent: true, userInitiated: true),
            _loadCurrentAccount(),
          ]);
        },
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
                                : () async {
                                    await Future.wait([
                                      _loadPayments(
                                        silent: true,
                                        userInitiated: true,
                                      ),
                                      _loadCurrentAccount(),
                                    ]);
                                  },
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
                  const SizedBox(height: 20),
                  _buildAccountSnapshot(),
                  const SizedBox(height: 22),
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
                    _buildPaymentsLoadingSkeleton(),
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
                    _PaymentHoverSurface(
                      child: Container(
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
                                  'Historial por fecha de reporte',
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
                                    color: AppColors.textMuted,
                                    fontSize: 14,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 23,
                                    color: Color(0xFF6381B5),
                                  ),
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
                                      color: AppColors.primaryBlue,
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
                    ),
                    const SizedBox(height: 14),
                    if (_visible.isEmpty)
                      _PaymentHoverSurface(
                        child: Container(
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
                        ),
                      )
                    else
                      for (final month in _groupByReportDate(_visible))
                        _monthGroup(month),
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

  // Skeleton de Mis pagos: comparte el shimmer y las tarjetas del dashboard.
  // Solo se muestra mientras no haya información cargada; al actualizar en
  // segundo plano mantenemos el historial visible, sin saltos ni parpadeos.
  Widget _buildPaymentsLoadingSkeleton() {
    const statCard = SkeletonCard(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          SkeletonBox(width: 44, height: 44, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 32, height: 22, radius: 6),
                SizedBox(height: 8),
                SkeletonBox(width: 84, height: 11, radius: 5),
              ],
            ),
          ),
        ],
      ),
    );

    const filtersCard = SkeletonCard(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 245, height: 19, radius: 6),
          SizedBox(height: 18),
          SkeletonBox(height: 49, radius: 15),
          SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SkeletonBox(width: 78, height: 32, radius: 9),
              SkeletonBox(width: 105, height: 32, radius: 9),
              SkeletonBox(width: 106, height: 32, radius: 9),
              SkeletonBox(width: 112, height: 32, radius: 9),
            ],
          ),
        ],
      ),
    );

    const monthHeader = SkeletonCard(
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          SkeletonBox(width: 22, height: 22, radius: 5),
          SizedBox(width: 12),
          Expanded(child: SkeletonBox(width: 130, height: 15, radius: 6)),
          SizedBox(width: 12),
          SkeletonBox(width: 68, height: 12, radius: 5),
        ],
      ),
    );

    const reportCard = SkeletonCard(
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Row(
        children: [
          SkeletonBox(width: 42, height: 42, radius: 11),
          SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14, radius: 6),
                SizedBox(height: 10),
                SkeletonBox(width: 115, height: 10, radius: 5),
              ],
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 11, radius: 5),
                SizedBox(height: 9),
                SkeletonBox(height: 13, radius: 6),
              ],
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SkeletonBox(height: 19, radius: 6),
                SizedBox(height: 9),
                SkeletonBox(width: 85, height: 21, radius: 11),
              ],
            ),
          ),
        ],
      ),
    );

    return SkeletonScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 590;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                for (var i = 0; i < 3; i++) ...[
                  statCard,
                  if (i < 2) const SizedBox(height: 10),
                ],
              ] else
                Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Expanded(child: statCard),
                    ],
                  ],
                ),
              const SizedBox(height: 24),
              filtersCard,
              const SizedBox(height: 14),
              monthHeader,
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    SkeletonBox(width: 18, height: 18, radius: 4),
                    SizedBox(width: 10),
                    SkeletonBox(width: 165, height: 13, radius: 6),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (compact) ...[
                for (var i = 0; i < 2; i++) ...[
                  const SkeletonCard(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 46, height: 40, radius: 10),
                        SizedBox(height: 14),
                        SkeletonBox(height: 14, radius: 6),
                        SizedBox(height: 10),
                        SkeletonBox(width: 145, height: 11, radius: 5),
                        SizedBox(height: 14),
                        SkeletonBox(width: 104, height: 23, radius: 11),
                      ],
                    ),
                  ),
                  if (i == 0) const SizedBox(height: 12),
                ],
              ] else ...[
                reportCard,
                const SizedBox(height: 12),
                reportCard,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _summary(String label, int count, IconData icon, Color color) {
    return _PaymentHoverSurface(
      hoverColor: color,
      child: Container(
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
                Text(
                  label,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    // Cada estado tiene identidad propia, tanto activo como en hover.
    final color = switch (value) {
      'pendiente' => _orange,
      'aprobado' => _green,
      'rechazado' => _red,
      _ => _blue,
    };
    final icon = switch (value) {
      'pendiente' => Icons.schedule_rounded,
      'aprobado' => Icons.check_circle_outline_rounded,
      'rechazado' => Icons.highlight_off_rounded,
      _ => Icons.grid_view_rounded,
    };
    return _PaymentStatusFilter(
      label: label,
      icon: icon,
      color: color,
      selected: _filter == value,
      onTap: () {
        if (_filter == value) return;
        setState(() {
          _filter = value;
          // Mostrar primero los resultados del nuevo filtro. Después de eso
          // sus meses y días permanecen plegables sin importar el estado.
          _collapsedMonths.clear();
          _collapsedDays.clear();
        });
      },
    );
  }

  // La fecha del reporte vive fuera de la tarjeta completa: una sola vez.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (payment.createdAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 2, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.schedule_outlined, size: 15, color: _muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Reporte a las ${_reportTime(payment.createdAt!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: _muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _PaymentHoverSurface(
          child: AnimatedContainer(
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
                                    _statusBadge(
                                      payment.statusLabel,
                                      icon,
                                      color,
                                    ),
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
                                      child: _paymentIdentity(
                                        payment,
                                        icon,
                                        color,
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Container(
                                      width: 1,
                                      height: 48,
                                      color: _border,
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      flex: 4,
                                      child: _paymentInstallment(payment),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
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
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _red,
                                    ),
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
          ),
        ),
      ],
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
          child: Text(
            'Pago ${payment.displayReference}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: _navy,
              fontWeight: FontWeight.w800,
            ),
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
            Icon(
              payment.quotaEstimate
                  ? Icons.pending_actions_outlined
                  : Icons.calendar_month_outlined,
              color: _blue,
              size: 18,
            ),
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
        if (payment.quotaEstimate) ...[
          const SizedBox(height: 5),
          const Text(
            'Estimación FIFO; se confirma al aprobar el pago',
            style: TextStyle(fontSize: 11, color: _muted),
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

  String _usdAmount(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '\$$whole,${parts[1]} USD';
  }

  // Una distribución única, con campos relevantes para cada medio de pago.
  // No se muestran datos bancarios inventados ni la fecha de pago eliminada.
  String _paymentMethodKind(_ReportedPayment payment) {
    final method = payment.method.toLowerCase();
    if (method.contains('móvil') ||
        method.contains('movil') ||
        method.contains('pago_movil')) {
      return 'movil';
    }
    if (method.contains('transferencia')) return 'transferencia';
    if (method.contains('zelle')) return 'zelle';
    if (method.contains('efectivo')) return 'efectivo';
    return 'otro';
  }

  String _paymentMethodName(_ReportedPayment payment) {
    return switch (_paymentMethodKind(payment)) {
      'movil' => 'PAGO MÓVIL',
      'transferencia' => 'TRANSFERENCIA BANCARIA',
      'zelle' => 'ZELLE',
      'efectivo' => 'EFECTIVO USD',
      _ =>
        payment.method.isEmpty
            ? 'NO ESPECIFICADO'
            : payment.method.toUpperCase(),
    };
  }

  Color _paymentMethodColor(String kind) => switch (kind) {
    'movil' => _blue,
    'transferencia' => const Color(0xFF087C91),
    'zelle' => const Color(0xFF683BC1),
    'efectivo' => const Color(0xFF087F5B),
    _ => _blue,
  };

  IconData _paymentMethodIcon(String kind) => switch (kind) {
    'movil' => Icons.smartphone_rounded,
    'transferencia' => Icons.account_balance_rounded,
    'zelle' => Icons.alternate_email_rounded,
    'efectivo' => Icons.payments_outlined,
    _ => Icons.account_balance_wallet_outlined,
  };

  // Los logos pertenecen al proyecto Flutter (assets/images) y se cargan
  // localmente. En caso de que falte un recurso se muestra un icono de respaldo.
  String? _paymentMethodAsset(String kind) => switch (kind) {
    'movil' => 'assets/images/logo_pago_movil.png',
    'transferencia' => 'assets/images/logo_transferencia_bancaria.png',
    'zelle' => 'assets/images/logo_zelle.png',
    'efectivo' => 'assets/images/logo_efectivo.png',
    _ => null,
  };

  Widget _paymentMethodLogo(String kind, Color accent) {
    final asset = _paymentMethodAsset(kind);
    final fallback = Icon(_paymentMethodIcon(kind), color: accent, size: 25);
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: asset == null
          ? Center(child: fallback)
          : Image.asset(
              asset,
              fit: BoxFit.contain,
              semanticLabel: _paymentMethodNameFromKind(kind),
              errorBuilder: (context, error, stackTrace) =>
                  Center(child: fallback),
            ),
    );
  }

  String _paymentMethodNameFromKind(String kind) => switch (kind) {
    'movil' => 'Pago móvil',
    'transferencia' => 'Transferencia bancaria',
    'zelle' => 'Zelle',
    'efectivo' => 'Efectivo',
    _ => 'Método de pago',
  };

  // La fecha aparece en el encabezado del día; cada tarjeta muestra su hora.
  String _reportTime(DateTime date) {
    final local = date.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _paymentMethodHint(String kind) => switch (kind) {
    'movil' => 'Pago bancario por teléfono',
    'transferencia' => 'Operación entre cuentas bancarias',
    'zelle' => 'Transferencia mediante Zelle',
    'efectivo' => 'Pago registrado en caja',
    _ => 'Información de la operación',
  };

  Widget _details(_ReportedPayment payment) {
    final status = payment.normalizedStatus;
    final kind = _paymentMethodKind(payment);
    final accent = _paymentMethodColor(kind);
    final isBankPayment = kind == 'movil' || kind == 'transferencia';
    final referenceLabel = switch (kind) {
      'zelle' => 'Confirmación Zelle',
      'efectivo' => 'Número de recibo',
      _ => 'Referencia bancaria',
    };

    // Campos específicos del método. La revisión comparte la misma cuadrícula
    // y la misma altura visual; nunca se muestra fecha de pago.
    final fields = <(String, String, IconData)>[
      if (isBankPayment && payment.bank.isNotEmpty)
        ('Banco de origen', payment.bank, Icons.account_balance_outlined),
      if (payment.reference.isNotEmpty)
        (
          referenceLabel,
          payment.reference,
          kind == 'efectivo' ? Icons.receipt_long_outlined : Icons.tag_rounded,
        ),
      if (!isBankPayment && kind == 'otro' && payment.bank.isNotEmpty)
        ('Banco de origen', payment.bank, Icons.account_balance_outlined),
      if (payment.confirmedAt != null)
        (
          'Fecha de revisión',
          _date(payment.confirmedAt),
          Icons.fact_check_outlined,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.receipt_long_outlined, color: _blue, size: 19),
            SizedBox(width: 9),
            Text(
              'Detalle del pago',
              style: TextStyle(
                color: _navy,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _paymentMethodLogo(kind, accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _paymentMethodName(payment),
                          style: const TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 0.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _paymentMethodHint(kind),
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 15),
                const Divider(height: 1, color: _border),
                const SizedBox(height: 15),
                _operationDetailsGrid(fields, accent: accent),
              ] else ...[
                const SizedBox(height: 12),
                const Text(
                  'No hay información adicional registrada para esta operación.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _paymentConceptAndAllocations(payment),
        if (status == 'rechazado') ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withValues(alpha: 0.20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: _red, size: 18),
                    SizedBox(width: 9),
                    Text(
                      'Motivo del rechazo',
                      style: TextStyle(
                        color: _red,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                if (payment.rejectionReasons.isEmpty)
                  const Text(
                    'El colegio no registró un motivo visible. Contacta a administración para solicitar más información.',
                    style: TextStyle(color: _navy, fontSize: 12.5, height: 1.4),
                  )
                else
                  for (final reason in payment.rejectionReasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        '• $reason',
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ] else if (status == 'pendiente') ...[
          const SizedBox(height: 14),
          _alert(
            'En revisión. Los descuentos por estudiante aparecerán cuando se apruebe el pago.',
            _orange,
            Icons.schedule_outlined,
          ),
        ] else if (status == 'aprobado' &&
            payment.studentAllocations.isEmpty) ...[
          const SizedBox(height: 14),
          _alert(
            'Pago aprobado. No hay desglose por estudiante disponible.',
            _green,
            Icons.verified_outlined,
          ),
        ],
        if (payment.otherNotes.isNotEmpty) ...[
          const SizedBox(height: 14),
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
        if (payment.id.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.fingerprint_rounded, size: 15, color: _muted),
              const SizedBox(width: 8),
              const Text(
                'ID del pago',
                style: TextStyle(color: _muted, fontSize: 11.5),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  payment.id,
                  maxLines: 1,
                  style: const TextStyle(color: _muted, fontSize: 11.5),
                ),
              ),
              IconButton(
                tooltip: 'Copiar identificador',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 17, color: _blue),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: payment.id));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Identificador del pago copiado'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  // Columnas idénticas para todos los métodos: 3 datos bancarios (banco,
  // referencia, revisión) o 2 datos para Zelle/Efectivo (referencia, revisión).
  // Se apilan únicamente cuando la anchura disponible no permite alinearlas.
  Widget _operationDetailsGrid(
    List<(String, String, IconData)> fields, {
    required Color accent,
  }) {
    return LayoutBuilder(
      builder: (context, bounds) {
        final columnsFit = fields.length == 3
            ? bounds.maxWidth >= 580
            : fields.length == 2 && bounds.maxWidth >= 390;
        final items = [
          for (final field in fields) _operationDataTile(field, accent: accent),
        ];
        if (!columnsFit) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                items[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: items[i]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _operationDataTile(
    (String, String, IconData) field, {
    required Color accent,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _border.withValues(alpha: 0.72)),
      ),
      child: _operationDetail(field.$1, field.$2, field.$3, accent: accent),
    );
  }

  // Etiqueta y valor con icono pequeño: todos los métodos comparten alturas.
  Widget _operationDetail(
    String label,
    String value,
    IconData icon, {
    Color accent = _blue,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
              const SizedBox(height: 4),
              SelectableText(
                value,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentDetailPanel({
    required Widget child,
    Color background = Colors.white,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 126),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _paymentConceptAndAllocations(_ReportedPayment payment) {
    final concepts = payment.quotaDetails;
    final allocations = payment.studentAllocations;
    final approved = payment.normalizedStatus == 'aprobado';
    final estimated = payment.quotaEstimate;

    final conceptPanel = _paymentDetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_month_outlined, size: 18, color: _blue),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Concepto',
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (concepts.isEmpty)
            Text(
              payment.installmentCardValue,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
            )
          else
            for (var i = 0; i < concepts.length; i++) ...[
              if (i > 0) const Divider(height: 18, color: _border),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: const BoxDecoration(
                      color: _blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      concepts[i],
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          if (estimated) ...[
            const SizedBox(height: 11),
            const Text(
              'Asignación estimada, pendiente de aprobación.',
              style: TextStyle(color: _orange, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );

    if (!approved) return conceptPanel;

    final allocationPanel = _paymentDetailPanel(
      background: const Color(0xFFF8FAFD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.people_outline_rounded, size: 18, color: _blue),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Aplicado por estudiante',
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (allocations.isEmpty)
            const Text(
              'Desglose no disponible.',
              style: TextStyle(color: _muted, fontSize: 12.5),
            )
          else
            for (var i = 0; i < allocations.length; i++) ...[
              if (i > 0) const Divider(height: 16, color: _border),
              LayoutBuilder(
                builder: (context, bounds) {
                  final student = allocations[i];
                  final name = Text(
                    student.name,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                  final amount = Text(
                    student.amountUsd == null
                        ? 'Importe no disponible'
                        : _usdAmount(student.amountUsd!),
                    style: TextStyle(
                      color: student.amountUsd == null ? _muted : _green,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                  if (bounds.maxWidth < 360) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [name, const SizedBox(height: 5), amount],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 10),
                      amount,
                    ],
                  );
                },
              ),
            ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 740) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              conceptPanel,
              const SizedBox(height: 14),
              allocationPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: conceptPanel),
            const SizedBox(width: 14),
            Expanded(child: allocationPanel),
          ],
        );
      },
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

// Grupos de presentación; no alteran ni duplican la información de Supabase.
class _ReportMonthGroup {
  const _ReportMonthGroup({
    required this.key,
    required this.date,
    required this.days,
  });
  final String key;
  final DateTime? date;
  final List<_ReportDayGroup> days;
}

class _ReportDayGroup {
  const _ReportDayGroup({
    required this.key,
    required this.date,
    required this.payments,
  });
  final String key;
  final DateTime? date;
  final List<_ReportedPayment> payments;
}

/// Mismo hover que las tarjetas del dashboard: contorno azul tenue y sombra
/// ligera sin escalado, salto de contenido ni reconstruir la lista completa.
class _PaymentHoverSurface extends StatefulWidget {
  const _PaymentHoverSurface({required this.child, this.hoverColor});

  final Widget child;
  final Color? hoverColor;

  @override
  State<_PaymentHoverSurface> createState() => _PaymentHoverSurfaceState();
}

class _PaymentHoverSurfaceState extends State<_PaymentHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final hoverColor = widget.hoverColor ?? AppColors.primaryBlue;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 155),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: hoverColor.withValues(alpha: 0.065),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: _hovered
                ? hoverColor.withValues(
                    alpha: widget.hoverColor == null ? 0.30 : 0.65,
                  )
                : Colors.transparent,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Filtro visual por estado: colores consistentes con los KPI y el hover
/// de las tarjetas, sin intervenir en la consulta ni en la agrupación.
class _PaymentStatusFilter extends StatefulWidget {
  const _PaymentStatusFilter({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PaymentStatusFilter> createState() => _PaymentStatusFilterState();
}

class _PaymentStatusFilterState extends State<_PaymentStatusFilter> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final selected = widget.selected;
    final highlighted = selected || _hovered;
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Filtrar pagos: ${widget.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 155),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 38),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.105)
                : _hovered
                ? color.withValues(alpha: 0.045)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted
                  ? color.withValues(alpha: selected ? 0.74 : 0.55)
                  : AppColors.cardBorder,
              width: 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.075),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              hoverColor: Colors.transparent,
              splashColor: color.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 15, color: color),
                    const SizedBox(width: 7),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: highlighted ? color : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
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
}

/// Suma real aplicada a las cuotas de un estudiante por un pago aprobado.
class _StudentPaymentAllocation {
  const _StudentPaymentAllocation({
    required this.name,
    required this.amountUsd,
    required this.quotaCount,
  });

  final String name;
  final double? amountUsd;
  final int quotaCount;
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
  bool _quotaEstimate = false;
  List<_StudentPaymentAllocation> _studentAllocations = const [];

  _ReportedPayment(this.raw);

  void setStudentAllocations(List<_StudentPaymentAllocation> allocations) {
    _studentAllocations = allocations;
  }

  List<_StudentPaymentAllocation> get studentAllocations =>
      List.unmodifiable(_studentAllocations);

  void setAppliedQuotaLabels(
    List<String> labels,
    int quotaCount, {
    List<String> concepts = const [],
    List<String> periods = const [],
    bool estimated = false,
  }) {
    _appliedQuotaLabels = labels;
    _quotaEstimate = estimated;
    _appliedQuotaCount = quotaCount;
    _appliedConcepts = concepts;
    _appliedPeriods = periods;
  }

  bool get hasQuotaDetails => _appliedQuotaLabels.isNotEmpty;
  bool get quotaEstimate => _quotaEstimate;
  List<String> get quotaDetails => List.unmodifiable(_appliedQuotaLabels);

  String get installmentHeading {
    return 'CONCEPTO';
  }

  String get installmentCardValue {
    if (_appliedQuotaLabels.isEmpty) {
      return normalizedStatus == 'pendiente'
          ? 'Se asignará al aprobar'
          : installmentLabel;
    }
    final first = _appliedQuotaLabels.first;
    if (_appliedQuotaLabels.length == 1) return first;
    final extra = _appliedQuotaLabels.length - 1;
    return '$first (+$extra ${extra == 1 ? 'concepto' : 'conceptos'})';
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

  String get bank =>
      _get(['banco_origen', 'banco', 'banco_emisor', 'entidad_bancaria']);
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
    return normalizedStatus == 'pendiente'
        ? 'Se asignará al aprobar'
        : 'Cuotas sin detalle disponible';
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

  /// Valor contable estimado en USD, solo para previsualizar FIFO.
  /// La aplicación definitiva del pago la determina la base de datos.
  double get amountUsdEquivalent {
    final converted = raw['monto_usd_equivalente'];
    if (converted != null) {
      return converted is num
          ? converted.toDouble()
          : (double.tryParse(converted.toString()) ?? 0);
    }
    final rawAmount = raw['monto'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : (double.tryParse(rawAmount?.toString() ?? '') ?? 0);
    final currency = _get(['moneda']).toUpperCase();
    if (currency == 'USD') return amount;
    final tasa = raw['tasa_aplicada'];
    final rate = tasa is num
        ? tasa.toDouble()
        : (double.tryParse(tasa?.toString() ?? '') ?? 0);
    return rate > 0 ? amount / rate : 0;
  }

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
