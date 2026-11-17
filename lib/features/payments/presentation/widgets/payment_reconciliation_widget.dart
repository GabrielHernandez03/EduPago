// Widget público usado por admin_dashboard_screen.dart:
// PaymentReconciliationWidget(colegioId: ..., onPaymentProcessed: ...)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/reconciliation_repository.dart';
import '../../data/supabase_reconciliation_repository.dart';

class PaymentReconciliationWidget extends StatefulWidget {
  final String colegioId;
  final VoidCallback? onPaymentProcessed;

  const PaymentReconciliationWidget({
    super.key,
    required this.colegioId,
    this.onPaymentProcessed,
  });

  @override
  State<PaymentReconciliationWidget> createState() =>
      _PaymentReconciliationWidgetState();
}

class _PaymentReconciliationWidgetState
    extends State<PaymentReconciliationWidget> {
  final ReconciliationRepository _repository =
      SupabaseReconciliationRepository();
  int _loadVersion = 0;
  String? _loadError;

  List<Map<String, dynamic>> _pendingPayments = [];
  bool _isLoading = true;
  bool _refreshing = false;
  String _filterStatus = 'pendiente';
  String _search = '';
  int _visibleCount = 8;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPayments();
  }

  @override
  void didUpdateWidget(covariant PaymentReconciliationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.colegioId != widget.colegioId) {
      _pendingPayments = [];
      _studentsCache.clear();
      _proofUrlCache.clear();
      _isLoading = true;
      _search = '';
      _searchController.clear();
      _visibleCount = 8;
      _fetchPayments();
    }
  }

  @override
  void dispose() {
    _loadVersion++;
    _searchController.dispose();
    super.dispose();
  }

  // Cargar todos los estados permite filtrar y buscar sin consultas extra.
  Future<void> _fetchPayments({bool silent = false}) async {
    final version = ++_loadVersion;
    final colegioId = widget.colegioId;
    if (!mounted) return;
    setState(() {
      _isLoading = !silent || _pendingPayments.isEmpty;
      _refreshing = silent && _pendingPayments.isNotEmpty;
      _loadError = null;
    });
    try {
      final payments = await _repository.loadPayments(
        colegioId: colegioId,
        status: 'todos',
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _pendingPayments = payments;
        _isLoading = false;
        _refreshing = false;
      });
    } catch (e) {
      debugPrint('Error cargando pagos para conciliación: $e');
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _isLoading = false;
        _refreshing = false;
        _loadError = 'No se pudieron consultar los pagos. Intenta nuevamente.';
      });
    }
  }

  Future<void> _approvePayment(Map<String, dynamic> pago) async {
    final String pagoId = pago['id'].toString();

    try {
      // Solo se cambia el estado del pago. El trigger de base de datos
      // (fn_conciliar_cuota_al_aprobar_pago) aplica el monto por FIFO a las
      // cuotas de todos los hijos del representante y registra cada abono en
      // pago_aplicaciones. Si sobra dinero queda como saldo a favor.
      // El repositorio comprueba la actualización efectiva y el estado pendiente.
      await _repository.approvePayment(
        colegioId: widget.colegioId,
        paymentId: pagoId,
      );

      if (!mounted) return;

      // Quita el pago de la lista al instante y luego recarga desde la BD.
      setState(() {
        _pendingPayments.removeWhere((p) => p['id'].toString() == pagoId);
      });
      widget.onPaymentProcessed?.call(); // Recarga las métricas del Dashboard
      _fetchPayments(silent: true);

      await _showApprovedDialog(pago);
    } catch (e) {
      debugPrint('Error al aprobar el pago: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al aprobar el pago: $e'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  /// Diálogo de confirmación que se muestra tras aprobar un pago.
  Future<void> _showApprovedDialog(Map<String, dynamic> pago) {
    final rep = pago['representantes'];
    final String nombre = rep is Map
        ? '${rep['nombres'] ?? ''} ${rep['apellidos'] ?? ''}'.trim()
        : '';
    final num monto = (pago['monto'] as num?) ?? 0;
    final num usd = (pago['monto_usd_equivalente'] as num?) ?? 0;
    final String moneda = (pago['moneda'] ?? '').toString();

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Color(0xFF16A34A),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '¡Pago aprobado!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (nombre.isNotEmpty)
              Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Referencia: ${pago['referencia'] ?? '-'}'),
            Text('Monto: ${monto.toStringAsFixed(2)} $moneda'),
            Text('Equivalente: \$${usd.toStringAsFixed(2)} USD'),
            const SizedBox(height: 12),
            const Text(
              'Se aplicó a las cuotas más antiguas. Cualquier excedente '
              'queda como saldo a favor del representante.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectPaymentDialog(String pagoId) async {
    final TextEditingController motivoController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              'Rechazar Pago',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Indica el motivo por el cual rechazas este comprobante. El representante podrá ver esta observación.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: motivoController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText:
                      'Ej. Referencia no encontrada en la cuenta bancaria...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'El motivo de rechazo es obligatorio';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar Rechazo'),
          ),
        ],
      ),
    );

    final reason = motivoController.text.trim();
    motivoController.dispose();

    if (confirmed == true) {
      try {
        await _repository.rejectPayment(
          colegioId: widget.colegioId,
          paymentId: pagoId,
          reason: reason,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago marcado como rechazado.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        _fetchPayments(silent: true);
        widget.onPaymentProcessed?.call();
      } catch (e) {
        if (mounted) _showErrorSnackBar('Error al rechazar el pago: $e');
      }
    }
  }

  /// Los enlaces de comprobantes se resuelven únicamente en el repositorio.
  Future<String?> _resolveComprobanteUrl(String stored) =>
      _repository.resolveProofUrl(stored);

  // ── Cachés: abrir el detalle casi al instante ──
  static const Duration _studentsTtl = Duration(minutes: 5);
  static const Duration _proofUrlTtl = Duration(seconds: 45);
  final Map<String, (DateTime, Future<List<Map<String, dynamic>>>)>
  _studentsCache = {};
  final Map<String, (DateTime, Future<String?>)> _proofUrlCache = {};

  /// Estudiantes del representante, con caché de 5 min por representante.
  Future<List<Map<String, dynamic>>> _studentsFor(Map<String, dynamic> pago) {
    final repId = _text(pago['representante_id'], fallback: '');
    if (repId.isEmpty) return _loadLinkedStudents(pago);
    final hit = _studentsCache[repId];
    if (hit != null && DateTime.now().difference(hit.$1) < _studentsTtl) {
      return hit.$2;
    }
    final future = _loadLinkedStudents(pago);
    _studentsCache[repId] = (DateTime.now(), future);
    future.catchError((Object _) {
      _studentsCache.remove(repId);
      return <Map<String, dynamic>>[];
    });
    return future;
  }

  /// URL firmada del comprobante, con caché corta (45 s) por ruta.
  Future<String?> _proofUrlFor(String stored) {
    final hit = _proofUrlCache[stored];
    if (hit != null && DateTime.now().difference(hit.$1) < _proofUrlTtl) {
      return hit.$2;
    }
    final future = _resolveComprobanteUrl(stored);
    _proofUrlCache[stored] = (DateTime.now(), future);
    future
        .then((url) {
          if (url == null || url.isEmpty) _proofUrlCache.remove(stored);
        })
        .catchError((Object _) {
          _proofUrlCache.remove(stored);
        });
    return future;
  }

  /// Calienta estudiantes, URL firmada e imagen al pasar el cursor por la
  /// fila, para que el modal abra con todo listo.
  void _prefetchDetail(Map<String, dynamic> pago) {
    _studentsFor(pago).ignore();
    final proof = _text(pago['comprobante_path'], fallback: '');
    if (proof.isEmpty || !mounted) return;
    final isPdf = RegExp(
      r'\.pdf(?:$|\?)',
      caseSensitive: false,
    ).hasMatch(proof);
    _proofUrlFor(proof)
        .then((url) {
          if (!mounted || url == null || url.isEmpty || isPdf) return;
          precacheImage(NetworkImage(url), context, onError: (error, stack) {});
        })
        .catchError((Object _) {});
  }

  static const Color _navy = AppColors.darkNavy;
  static const Color _blue = AppColors.primaryBlue;
  static const Color _muted = AppColors.textMuted;
  static const Color _border = AppColors.cardBorder;
  static const Color _green = Color(0xFF16845A);
  static const Color _amber = Color(0xFFAD6500);
  static const Color _red = Color(0xFFCC3E50);

  final NumberFormat _number = NumberFormat('#,##0.00', 'es_VE');

  String _text(dynamic value, {String fallback = 'No registrado'}) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty || s.toLowerCase() == 'null' ? fallback : s;
  }

  String _representativeName(Map<String, dynamic> pago) {
    final person = pago['representantes'];
    if (person is! Map) return 'Representante no identificado';
    final full = [person['nombres'], person['apellidos']]
        .map((s) => _text(s, fallback: ''))
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();
    return full.isEmpty ? 'Representante no identificado' : full;
  }

  String _representativeId(Map<String, dynamic> pago) {
    final person = pago['representantes'];
    return person is Map ? _text(person['cedula']) : 'No registrada';
  }

  String _method(Map<String, dynamic> pago) {
    final raw = _text(pago['metodo'], fallback: 'No especificado');
    switch (raw.toLowerCase().replaceAll('_', ' ')) {
      case 'pago movil':
      case 'pago móvil':
        return 'Pago móvil';
      case 'transferencia bancaria':
        return 'Transferencia bancaria';
      case 'zelle':
        return 'Zelle';
      case 'efectivo usd':
        return 'Efectivo USD';
      default:
        return raw;
    }
  }

  String _date(dynamic value) {
    final raw = _text(value, fallback: '');
    if (raw.isEmpty) return 'Sin fecha';
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : DateFormat('dd/MM/yyyy').format(parsed);
  }

  /// Momento en que EduPago recibió el reporte (creado_at), no la fecha
  /// del pago que declara el representante (fecha_pago).
  String _reportedAt(Map<String, dynamic> pago) {
    final raw = _text(pago['creado_at'], fallback: '');
    if (raw.isEmpty) return 'Fecha y hora no disponibles';
    final date = DateTime.tryParse(raw);
    if (date == null) return 'Fecha y hora no disponibles';
    return DateFormat('dd/MM/yyyy · HH:mm').format(date.toLocal());
  }

  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _originalAmount(Map<String, dynamic> pago) {
    final currency = _text(pago['moneda'], fallback: 'USD').toUpperCase();
    final value = _number.format(_amount(pago['monto']));
    return currency == 'VES' || currency == 'BS' || currency == 'BOLIVARES'
        ? 'Bs. $value'
        : '$currency $value';
  }

  String _equivalent(Map<String, dynamic> pago) =>
      'USD ${_number.format(_amount(pago['monto_usd_equivalente']))}';

  String _status(Map<String, dynamic> pago) =>
      _text(pago['estado'], fallback: 'pendiente').toLowerCase();

  Color _statusColor(String status) => switch (status) {
    'aprobado' => _green,
    'rechazado' => _red,
    _ => _amber,
  };

  String _statusLabel(String status) => switch (status) {
    'aprobado' => 'Aprobado',
    'rechazado' => 'Rechazado',
    _ => 'En revisión',
  };

  IconData _statusIcon(String status) => switch (status) {
    'aprobado' => Icons.check_circle_outline_rounded,
    'rechazado' => Icons.highlight_off_rounded,
    _ => Icons.schedule_rounded,
  };

  /// Días que un pago aprobado o rechazado sigue apareciendo en la lista.
  /// Pasado ese plazo solo se oculta de la vista; el registro NO se borra.
  static const Duration _decisionRetention = Duration(days: 14);

  /// Posibles columnas con la fecha de la decisión (aprobar / rechazar).
  /// Se usa la primera que venga con valor en la fila.
  static const List<String> _decisionDateKeys = [
    'decidido_at',
    'fecha_decision',
    'aprobado_at',
    'rechazado_at',
    'fecha_aprobacion',
    'fecha_rechazo',
    'revisado_at',
    'conciliado_at',
    'procesado_at',
    'actualizado_at',
    'updated_at',
  ];

  DateTime? _decisionDate(Map<String, dynamic> pago) {
    for (final key in _decisionDateKeys) {
      final parsed = DateTime.tryParse(_text(pago[key], fallback: ''));
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// true si el pago ya fue aprobado/rechazado hace más de 14 días.
  /// Si la fila no trae fecha de decisión, nunca se oculta.
  bool _isExpiredDecision(Map<String, dynamic> pago) {
    final status = _status(pago);
    if (status != 'aprobado' && status != 'rechazado') return false;
    final decidedAt = _decisionDate(pago);
    if (decidedAt == null) return false;
    return DateTime.now().difference(decidedAt) > _decisionRetention;
  }

  /// Pagos que se pueden listar (sin los decididos hace más de 14 días).
  List<Map<String, dynamic>> get _listedPayments =>
      _pendingPayments.where((pago) => !_isExpiredDecision(pago)).toList();

  List<Map<String, dynamic>> get _visiblePayments {
    final search = _search.trim().toLowerCase();
    return _listedPayments.where((pago) {
      if (_filterStatus != 'todos' && _status(pago) != _filterStatus) {
        return false;
      }
      if (search.isEmpty) return true;
      final searchable = [
        _representativeName(pago),
        _representativeId(pago),
        _text(pago['referencia'], fallback: ''),
        _method(pago),
        _text(pago['banco_origen'], fallback: ''),
        _date(pago['fecha_pago']),
        _text(pago['fecha_pago'], fallback: ''),
        _reportedAt(pago),
        _originalAmount(pago),
      ].join(' ').toLowerCase();
      return searchable.contains(search);
    }).toList();
  }

  BoxDecoration _cardDecoration({Color border = _border}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(17),
    border: Border.all(color: border),
    boxShadow: [
      BoxShadow(
        color: _navy.withValues(alpha: 0.035),
        blurRadius: 15,
        offset: const Offset(0, 5),
      ),
    ],
  );

  Widget _statusPill(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            _statusLabel(status),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 700;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 27, color: _blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Conciliación de pagos',
                  style: TextStyle(
                    fontSize: compact ? 25 : 29,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Revisa los comprobantes y gestiona los pagos reportados por las familias.',
            style: TextStyle(fontSize: 14, color: _muted),
          ),
        ],
      );
      final refresh = OutlinedButton.icon(
        onPressed: _refreshing || _isLoading
            ? null
            : () => _fetchPayments(silent: true),
        icon: _refreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
              )
            : const Icon(Icons.refresh_rounded, size: 20),
        label: Text(_refreshing ? 'Actualizando...' : 'Actualizar'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _navy,
          backgroundColor: Colors.white,
          side: const BorderSide(color: _border),
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 14), refresh],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: heading),
          const SizedBox(width: 16),
          refresh,
        ],
      );
    },
  );

  /// Un único selector en vez de cuatro botones horizontales.
  Widget _statusDropdown() {
    final options = <(String, String, IconData, Color)>[
      ('todos', 'Todos', Icons.grid_view_rounded, _blue),
      ('pendiente', 'En espera', Icons.schedule_rounded, _amber),
      ('aprobado', 'Aprobados', Icons.check_circle_outline_rounded, _green),
      ('rechazado', 'Rechazados', Icons.highlight_off_rounded, _red),
    ];
    final current = options.firstWhere((option) => option.$1 == _filterStatus);
    return PopupMenuButton<String>(
      tooltip: 'Filtrar pagos por estado',
      initialValue: _filterStatus,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 7),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: _border),
      ),
      onSelected: (value) {
        if (value == _filterStatus) return;
        setState(() {
          _filterStatus = value;
          _visibleCount = 8;
        });
      },
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option.$1,
            height: 46,
            child: Row(
              children: [
                Icon(option.$3, color: option.$4, size: 18),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    option.$2,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_filterStatus == option.$1)
                  const Icon(Icons.check_rounded, color: _blue, size: 18),
              ],
            ),
          ),
      ],
      child: Container(
        width: 195,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_list_rounded, color: current.$4, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                current.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: _blue),
          ],
        ),
      ),
    );
  }

  Widget _paymentRow(Map<String, dynamic> pago) {
    final status = _status(pago);
    final color = _statusColor(status);
    final name = _representativeName(pago);
    final ref = _text(pago['referencia'], fallback: 'Sin referencia');
    final currency = _text(pago['moneda'], fallback: 'USD').toUpperCase();
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 720;
        final profile = Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: color.withValues(alpha: 0.095),
              ),
              child: Icon(_statusIcon(status), color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Ref. $ref  •  ${_method(pago)}',
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: _muted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Reportado: ${_reportedAt(pago)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        final amount = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _originalAmount(pago),
              maxLines: 1,
              style: const TextStyle(
                color: _navy,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (currency != 'USD') ...[
              const SizedBox(height: 4),
              Text(
                '≈ ${_equivalent(pago)}',
                style: const TextStyle(color: _muted, fontSize: 10.5),
              ),
            ],
          ],
        );
        final action = IconButton(
          tooltip: 'Ver detalles y comprobante',
          onPressed: () => _showDetailModal(pago),
          icon: const Icon(Icons.visibility_outlined, color: _blue, size: 22),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFF0F5FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        );
        return _ReconciliationHoverSurface(
          accent: color,
          onTap: () => _showDetailModal(pago),
          onHoverStart: () => _prefetchDetail(pago),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: 15,
            ),
            child: compact
                ? Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: profile),
                          const SizedBox(width: 5),
                          action,
                        ],
                      ),
                      const SizedBox(height: 13),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          amount,
                          const SizedBox(width: 10),
                          _statusPill(status),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: profile),
                      const SizedBox(width: 16),
                      SizedBox(width: 145, child: amount),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 115,
                        child: Center(child: _statusPill(status)),
                      ),
                      const SizedBox(width: 6),
                      action,
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _emptyState({required bool noMatches}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 43, horizontal: 14),
    child: Column(
      children: [
        Container(
          width: 63,
          height: 63,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            noMatches
                ? Icons.search_off_rounded
                : _filterStatus == 'pendiente'
                ? Icons.task_alt_rounded
                : Icons.receipt_long_outlined,
            size: 29,
            color: _blue,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          noMatches
              ? 'No encontramos pagos con esa búsqueda'
              : _filterStatus == 'pendiente'
              ? 'No hay pagos pendientes de revisión'
              : 'No hay pagos en esta categoría',
          style: const TextStyle(
            color: _navy,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          noMatches
              ? 'Intenta con otro nombre, referencia o método de pago.'
              : _filterStatus == 'pendiente'
              ? 'Cuando una familia reporte un pago, aparecerá aquí para su revisión.'
              : 'Los registros aparecerán cuando haya movimientos con este estado.',
          style: const TextStyle(fontSize: 12.5, color: _muted),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _paymentsPanel() {
    final visible = _visiblePayments;
    final count = visible.length;
    final page = visible.take(_visibleCount).toList();
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Wrap(
                spacing: 10,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Pagos reportados',
                    style: TextStyle(
                      fontSize: 19,
                      color: _navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$count de ${_listedPayments.length} registros',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              );
              if (constraints.maxWidth < 530) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _statusDropdown(),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 14),
                  _statusDropdown(),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() {
              _search = value;
              _visibleCount = 8;
            }),
            decoration: InputDecoration(
              hintText: 'Buscar por representante, referencia o método...',
              hintStyle: const TextStyle(color: _muted, fontSize: 13.5),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF6584B9),
              ),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _search = '';
                          _visibleCount = 8;
                        });
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: true,
              fillColor: const Color(0xFFF1F5FB),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: _blue, width: 1.4),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 17),
          if (_loadError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2F3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  Text(
                    _loadError!,
                    style: const TextStyle(color: _red, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () => _fetchPayments(),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          if (_loadError != null && _pendingPayments.isEmpty) ...[
            const SizedBox(height: 4),
          ] else if (_isLoading) ...[
            const SizedBox(height: 18),
            const Center(child: CircularProgressIndicator(color: _blue)),
            const SizedBox(height: 25),
          ] else if (visible.isEmpty) ...[
            _emptyState(noMatches: _search.trim().isNotEmpty),
          ] else ...[
            for (var i = 0; i < page.length; i++) ...[
              _paymentRow(page[i]),
              if (i < page.length - 1) const SizedBox(height: 9),
            ],
            if (count > page.length) ...[
              const SizedBox(height: 15),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _visibleCount += 8),
                  icon: const Icon(Icons.expand_more_rounded, size: 20),
                  label: Text('Mostrar más (${count - page.length} restantes)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _blue,
                    side: BorderSide(color: _blue.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // Los estudiantes se consultan por la relación real del representante.
  // Esto NO significa que el reporte se haya aplicado a todos sus estudiantes.
  Future<List<Map<String, dynamic>>> _loadLinkedStudents(
    Map<String, dynamic> pago,
  ) async {
    final representativeId = _text(pago['representante_id'], fallback: '');
    if (representativeId.isEmpty) {
      throw StateError('El pago no tiene representante asociado.');
    }
    final client = Supabase.instance.client;

    List<Map<String, dynamic>> sorted(Iterable<Map<String, dynamic>> input) {
      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final student in input) {
        final id = student['id']?.toString() ?? '';
        if (id.isNotEmpty && !seen.add(id)) continue;
        list.add(student);
      }
      list.sort((a, b) => _studentName(a).compareTo(_studentName(b)));
      return list;
    }

    // 1) Una sola consulta con la relación embebida (1 viaje a la red).
    try {
      final rows = await client
          .from('representante_estudiante')
          .select('estudiantes(*)')
          .eq('representante_id', representativeId);
      final found = <Map<String, dynamic>>[];
      for (final row in rows) {
        final e = row['estudiantes'];
        if (e is Map) {
          found.add(Map<String, dynamic>.from(e));
        } else if (e is List) {
          for (final item in e) {
            if (item is Map) found.add(Map<String, dynamic>.from(item));
          }
        }
      }
      return sorted(found);
    } catch (e) {
      debugPrint('Relación embebida no disponible, usando 2 consultas: $e');
    }

    // 2) Respaldo: dos consultas encadenadas.
    final links = await client
        .from('representante_estudiante')
        .select('estudiante_id')
        .eq('representante_id', representativeId);
    final ids = links
        .map((row) => row['estudiante_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return <Map<String, dynamic>>[];

    final rows = await client
        .from('estudiantes')
        .select('*')
        .inFilter('id', ids);
    return sorted(rows.map((row) => Map<String, dynamic>.from(row)));
  }

  String _studentName(Map<String, dynamic> student) {
    final name = [student['nombres'], student['apellidos']]
        .map((part) => _text(part, fallback: ''))
        .where((part) => part.isNotEmpty)
        .join(' ');
    return name.isEmpty ? 'Estudiante sin nombre' : name;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'E';
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.first
        .substring(0, parts.first.length > 2 ? 2 : parts.first.length)
        .toUpperCase();
  }

  Widget _detailCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(15),
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFDCE6F5)),
      borderRadius: BorderRadius.circular(15),
    ),
    child: child,
  );

  Future<void> _copyReference(String reference) async {
    if (reference.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: reference));
  }

  String _storagePath(String raw) {
    var path = raw.trim();
    final match = RegExp(
      r'/storage/v1/object/(?:public|sign|authenticated)/comprobantes/',
    ).firstMatch(path);
    if (match != null) {
      path = Uri.decodeComponent(path.substring(match.end).split('?').first);
    }
    return path;
  }

  // Descarga binaria desde Storage: el atributo "download" de un enlace a
  // otro dominio puede ignorarse en Chrome y abrir el archivo en otra pestaña.
  Future<void> _downloadComprobante(Map<String, dynamic> pago) async {
    final raw = _text(pago['comprobante_path'], fallback: '');
    if (raw.isEmpty) return;
    final path = _storagePath(raw);
    if (path.startsWith('http://') || path.startsWith('https://')) {
      _showErrorSnackBar(
        'El comprobante tiene un enlace externo. No se puede descargar directamente desde Storage.',
      );
      return;
    }
    try {
      final bytes = await Supabase.instance.client.storage
          .from('comprobantes')
          .download(path);
      final sourceFileName = path.split('/').last.split('?').first;
      final extMatch = RegExp(
        r'\.(pdf|png|jpe?g|webp|gif)$',
        caseSensitive: false,
      ).firstMatch(sourceFileName);
      final extension = extMatch?.group(0)?.toLowerCase() ?? '.bin';
      final reference = _text(
        pago['referencia'],
        fallback: 'pago',
      ).replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final blob = html.Blob([bytes]);
      final objectUrl = html.Url.createObjectUrlFromBlob(blob);
      try {
        final anchor = html.AnchorElement(href: objectUrl)
          ..download = 'comprobante_$reference$extension';
        html.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
      } finally {
        // Dar tiempo al navegador para que empiece la descarga antes de liberar
        // la URL temporal, sin conservar el comprobante en disco del servidor.
        await Future<void>.delayed(const Duration(seconds: 1));
        html.Url.revokeObjectUrl(objectUrl);
      }
    } catch (e) {
      debugPrint('Error descargando comprobante: $e');
      if (mounted) {
        _showErrorSnackBar(
          'No se pudo descargar el comprobante. Comprueba permisos y conexión.',
        );
      }
    }
  }

  void _openComprobante(
    String url, {
    required bool isPdf,
    Map<String, dynamic>? pago,
  }) {
    if (isPdf) {
      html.window.open(url, '_blank');
      return;
    }
    final ref = pago == null ? '' : _text(pago['referencia'], fallback: '');
    final subtitle = pago == null
        ? ''
        : [
            if (ref.isNotEmpty) 'Ref. $ref',
            _representativeName(pago),
            _originalAmount(pago),
          ].join('  ·  ');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ProofViewerDialog(
        url: url,
        title: 'Comprobante de pago',
        subtitle: subtitle,
        onDownload: pago == null ? null : () => _downloadComprobante(pago),
      ),
    );
  }

  // ═══════════════ DETALLE DEL REPORTE DE PAGO ═══════════════

  /// Carpeta de los logos de métodos de pago.
  /// Debe estar registrada en pubspec.yaml:
  ///   flutter:
  ///     assets:
  ///       - assets/images/
  static const String _logosDir = 'assets/images/';

  /// Devuelve el logo según el método (o null si no hay uno).
  String? _methodAsset(Map<String, dynamic> pago) {
    final m = _method(pago).toLowerCase();
    if (m.contains('móvil') || m.contains('movil')) {
      return '${_logosDir}logo_pago_movil.png';
    }
    if (m.contains('transfer')) {
      return '${_logosDir}logo_transferencia_bancaria.png';
    }
    if (m.contains('zelle')) return '${_logosDir}logo_zelle.png';
    if (m.contains('efectivo')) return '${_logosDir}logo_efectivo.png';
    return null;
  }

  IconData _methodIcon(Map<String, dynamic> pago) {
    final m = _method(pago).toLowerCase();
    if (m.contains('móvil')) return Icons.smartphone_rounded;
    if (m.contains('transfer')) return Icons.account_balance_rounded;
    if (m.contains('zelle')) return Icons.bolt_rounded;
    if (m.contains('efectivo')) return Icons.payments_outlined;
    return Icons.account_balance_wallet_outlined;
  }

  /// Cuadro con el logo del método de pago (o un ícono si no hay imagen).
  Widget _methodBadge(Map<String, dynamic> pago, {double size = 46}) {
    final asset = _methodAsset(pago);
    final fallback = Center(
      child: Icon(_methodIcon(pago), size: size * 0.5, color: _blue),
    );
    return Tooltip(
      message: _method(pago),
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(asset == null ? 0 : size * 0.15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFDCE6F5)),
        ),
        child: asset == null
            ? fallback
            : Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => fallback,
              ),
      ),
    );
  }

  // ── Fechas en español (sin depender de initializeDateFormatting) ──
  static const List<String> _monthsEs = [
    'ene.',
    'feb.',
    'mar.',
    'abr.',
    'may.',
    'jun.',
    'jul.',
    'ago.',
    'sep.',
    'oct.',
    'nov.',
    'dic.',
  ];

  String _longDate(DateTime d) =>
      '${d.day} ${_monthsEs[d.month - 1]} ${d.year}';

  String _clock(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  /// Fecha que declara el representante (solo día).
  String _declaredDate(dynamic value) {
    final raw = _text(value, fallback: '');
    if (raw.isEmpty) return 'Sin fecha';
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : _longDate(parsed);
  }

  /// Momento en que EduPago recibió el reporte (creado_at).
  String _reportedAtLong(Map<String, dynamic> pago) {
    final date = DateTime.tryParse(_text(pago['creado_at'], fallback: ''));
    if (date == null) return 'No disponible';
    final local = date.toLocal();
    return '${_longDate(local)} · ${_clock(local)}';
  }

  String _reportCode(Map<String, dynamic> pago) {
    final id = _text(pago['id'], fallback: '').replaceAll('-', '');
    if (id.isEmpty) return 'Reporte sin código';
    return 'Reporte #${(id.length > 8 ? id.substring(0, 8) : id).toUpperCase()}';
  }

  String _statusLongLabel(String status) => switch (status) {
    'aprobado' => 'Aprobado',
    'rechazado' => 'Rechazado',
    _ => 'Pendiente de validación',
  };

  /// Estado en línea: ícono + texto de color, sin recuadro.
  Widget _statusInline(String status) {
    final color = _statusColor(status);
    final icon = switch (status) {
      'aprobado' => Icons.check_circle_rounded,
      'rechazado' => Icons.cancel_rounded,
      _ => Icons.schedule_rounded,
    };
    // Text.rich (en vez de Row) para que el estado tenga línea base de texto
    // y pueda alinearse exactamente con el título.
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(icon, size: 20, color: color),
          ),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(width: 7),
          ),
          TextSpan(text: _statusLongLabel(status)),
        ],
      ),
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
    );
  }

  /// Cabecera en una sola fila: ícono | divisor | sobretítulo arriba y, en la
  /// línea del título, el estado y la fecha (alineados con el título) |
  /// cerrar. En pantallas estrechas el estado y la fecha pasan a una 2.ª línea.
  Widget _reportHeader(
    BuildContext ctx,
    Map<String, dynamic> pago,
    String status,
  ) {
    // El código del reporte queda disponible al pasar el cursor por el ícono.
    final iconBox = Tooltip(
      message: _reportCode(pago),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.description_outlined, color: _blue, size: 22),
      ),
    );
    final divider = Container(
      width: 1,
      height: 40,
      color: const Color(0xFFE3EAF5),
    );
    const eyebrow = Text(
      'CONCILIACIÓN DE PAGOS',
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w800,
        color: _blue,
      ),
    );
    const title = Text(
      'Detalle del reporte de pago',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _navy),
    );
    final date = Text.rich(
      TextSpan(
        children: [
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.calendar_month_outlined, size: 16, color: _muted),
          ),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(width: 6),
          ),
          TextSpan(text: _reportedAtLong(pago)),
        ],
      ),
      style: const TextStyle(
        fontSize: 12.5,
        color: _muted,
        fontWeight: FontWeight.w600,
      ),
    );
    final close = IconButton(
      tooltip: 'Cerrar',
      onPressed: () => Navigator.pop(ctx),
      icon: const Icon(Icons.close_rounded, size: 22, color: _muted),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3EAF5))),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 760) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    divider,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [eyebrow, const SizedBox(height: 2), title],
                      ),
                    ),
                    close,
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [_statusInline(status), date],
                ),
              ],
            );
          }
          return Row(
            children: [
              iconBox,
              const SizedBox(width: 12),
              divider,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    eyebrow,
                    const SizedBox(height: 2),
                    // Alineados por la línea base del texto: título, estado y
                    // fecha quedan exactamente a la misma altura.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        title,
                        const SizedBox(width: 28),
                        _statusInline(status),
                        const Spacer(),
                        date,
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              close,
            ],
          );
        },
      ),
    );
  }

  /// Título de sección: ícono en recuadro + texto (+ elemento a la derecha).
  Widget _panelTitle(IconData icon, String label, {Widget? trailing}) =>
      SizedBox(
        height: 24,
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: _blue),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _infoField(String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 3),
      SelectableText(
        value,
        minLines: 1,
        maxLines: 2,
        style: const TextStyle(
          color: _navy,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  /// Reparte los campos en filas de dos columnas de igual ancho.
  List<Widget> _fieldRows(List<Widget> fields) {
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: fields[i]),
            const SizedBox(width: 16),
            Expanded(
              child: i + 1 < fields.length ? fields[i + 1] : const SizedBox(),
            ),
          ],
        ),
      );
    }
    return rows;
  }

  Widget _referenceField(
    BuildContext ctx,
    String ref,
    ValueNotifier<bool> copiedReference,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Referencia bancaria',
        style: TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 3),
      Row(
        children: [
          Flexible(
            child: SelectableText(
              ref.isEmpty ? 'No registrada' : ref,
              style: const TextStyle(
                color: _navy,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: copiedReference,
            builder: (context, copied, child) => InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: ref.isEmpty
                  ? null
                  : () async {
                      await _copyReference(ref);
                      if (ctx.mounted) copiedReference.value = true;
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: copied
                      ? _green.withValues(alpha: 0.12)
                      : const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (copied ? _green : _blue).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 12,
                      color: copied ? _green : _blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      copied ? 'Copiada' : 'Copiar',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: copied ? _green : _blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  /// Tarjeta del representante: avatar + nombre + datos en 2 columnas.
  /// Con [fill] ocupa todo el alto que le da su padre y reparte el espacio
  /// sobrante en partes iguales entre sus filas (separaciones simétricas).
  Widget _representativeCard(
    BuildContext ctx,
    Map<String, dynamic> pago,
    ValueNotifier<bool> copiedReference, {
    bool fill = false,
  }) {
    final name = _representativeName(pago);
    final ref = _text(pago['referencia'], fallback: '');
    final header = Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            _initials(name),
            style: const TextStyle(
              color: _blue,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Cédula ${_representativeId(pago)}',
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
    final items = <Widget>[
      header,
      const Divider(height: 1, color: Color(0xFFE3EAF5)),
      ..._fieldRows([
        _infoField('Método de pago', _method(pago)),
        _infoField(
          'Moneda',
          _text(pago['moneda'], fallback: 'USD').toUpperCase(),
        ),
        _infoField('Fecha del pago', _declaredDate(pago['fecha_pago'])),
        _infoField('Fecha y hora del reporte', _reportedAtLong(pago)),
        _referenceField(ctx, ref, copiedReference),
        _infoField('Banco de origen', _text(pago['banco_origen'])),
      ]),
    ];
    return _detailCard(
      padding: const EdgeInsets.all(12),
      child: fill
          ? Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: items,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 9),
                  items[i],
                ],
              ],
            ),
    );
  }

  /// Primer valor no vacío entre varias claves posibles de la fila
  /// (también acepta relaciones embebidas como {nombre: ...}).
  String _firstText(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value is Map) {
        final nested = _text(value['nombre'] ?? value['name'], fallback: '');
        if (nested.isNotEmpty) return nested;
        continue;
      }
      final text = _text(value, fallback: '');
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _studentCedula(Map<String, dynamic> student) => _firstText(student, [
    'cedula',
    'cedula_escolar',
    'documento_identidad',
    'documento',
  ]);

  String _studentGrade(Map<String, dynamic> student) {
    final grade = _firstText(student, [
      'grado_seccion',
      'grado',
      'grado_nombre',
      'nombre_grado',
      'grados',
      'nivel',
      'curso',
    ]);
    final section = _firstText(student, [
      'seccion',
      'seccion_nombre',
      'secciones',
    ]);
    if (grade.isEmpty) return section.isEmpty ? '' : 'Sección $section';
    final g = grade.toLowerCase();
    final sec = section.toLowerCase();
    if (section.isEmpty || g == sec || g.endsWith(' $sec')) return grade;
    return '$grade $section';
  }

  /// "3er grado A · Cédula V-12345678"
  String _studentSubtitle(Map<String, dynamic> student) {
    final grade = _studentGrade(student);
    final id = _studentCedula(student);
    return '${grade.isEmpty ? 'Grado no registrado' : grade}  ·  '
        '${id.isEmpty ? 'Sin cédula' : 'Cédula $id'}';
  }

  /// Avatar circular con iniciales (mismo estilo que el resto de la página).
  Widget _initialsAvatar(String name, double size, {bool ring = false}) =>
      Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          shape: BoxShape.circle,
          border: Border.all(
            color: ring ? Colors.white : const Color(0xFFD3E2FA),
            width: ring ? 2 : 1,
          ),
        ),
        child: Text(
          _initials(name),
          style: TextStyle(
            color: _blue,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.34,
          ),
        ),
      );

  /// Fila de estudiante: avatar + nombre + "grado · cédula".
  Widget _studentMenuRow(
    Map<String, dynamic> student, {
    bool divider = true,
    double vertical = 10,
  }) {
    final name = _studentName(student);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: vertical),
      decoration: BoxDecoration(
        border: divider
            ? const Border(top: BorderSide(color: Color(0xFFE8EEF8)))
            : null,
      ),
      child: Row(
        children: [
          _initialsAvatar(name, 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _studentSubtitle(student),
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
  }

  Widget _studentsMenuBody(List<Map<String, dynamic>> students) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Text(
          'Asociados al representante, no necesariamente a este pago.',
          style: TextStyle(fontSize: 10.5, color: _muted),
        ),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 290),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final s in students) _studentMenuRow(s)],
          ),
        ),
      ),
    ],
  );

  /// Abre la lista de estudiantes justo debajo del campo con su mismo ancho.
  /// Si abajo no hay espacio suficiente, se abre hacia arriba para no tapar
  /// el propio campo.
  Future<void> _openStudentsMenu(
    BuildContext fieldContext,
    List<Map<String, dynamic>> students,
  ) async {
    final box = fieldContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(fieldContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null || !box.hasSize) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final rect = topLeft & box.size;
    // Alto aproximado del menú: nota (33) + filas (59 c/u, máx. 290).
    final menuHeight = 33.0 + (students.length * 59.0).clamp(0.0, 290.0);
    final below = overlayBox.size.height - rect.bottom - 14;
    final above = rect.top - 14;
    final openUp = below < menuHeight && above > below;
    final top = openUp ? rect.top - menuHeight - 6 : rect.bottom + 6;

    await showMenu<void>(
      context: fieldContext,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(rect.left, top, rect.width, 0),
        Offset.zero & overlayBox.size,
      ),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      constraints: BoxConstraints.tightFor(width: rect.width),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: _border),
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _studentsMenuBody(students),
        ),
      ],
    );
  }

  /// Sección "Estudiantes asociados".
  /// • Hasta [maxInline] estudiantes: se muestran directamente en una tarjeta.
  /// • Más que eso: selector desplegable (mismo estilo que el filtro de la
  ///   lista) con la lista completa, grado y cédula.
  Widget _studentsSection(
    Future<List<Map<String, dynamic>>> future, {
    int maxInline = 2,
  }) => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final hasError = snapshot.hasError;
      final students = snapshot.data ?? const <Map<String, dynamic>>[];
      final isList = !loading && !hasError && students.isNotEmpty;
      final inline = isList && students.length <= maxInline;

      final Widget content;
      if (inline) {
        content = Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFDCE6F5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < students.length; i++)
                _studentMenuRow(students[i], divider: i > 0, vertical: 8),
            ],
          ),
        );
      } else {
        final Widget leading;
        final String label;
        if (loading) {
          leading = const SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
              ),
            ),
          );
          label = 'Cargando estudiantes...';
        } else if (hasError) {
          leading = const SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.error_outline_rounded, color: _red, size: 24),
          );
          label = 'No se pudieron consultar los estudiantes';
        } else if (students.isEmpty) {
          leading = const SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.person_off_outlined, color: _muted, size: 24),
          );
          label = 'Sin estudiantes vinculados';
        } else {
          // Un solo ícono de grupo en lugar de varios avatares.
          leading = Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD3E2FA)),
            ),
            child: const Icon(Icons.people_alt_rounded, size: 18, color: _blue),
          );
          label = '${students.length} estudiantes asociados';
        }

        final row = Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: isList ? _blue : _muted,
              ),
            ],
          ),
        );
        final shape = RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: const BorderSide(color: Color(0xFFDCE6F5)),
        );
        content = isList
            ? Tooltip(
                message: 'Ver estudiantes asociados',
                child: Material(
                  color: Colors.white,
                  clipBehavior: Clip.antiAlias,
                  shape: shape,
                  child: Builder(
                    builder: (fieldContext) => InkWell(
                      hoverColor: _blue.withValues(alpha: 0.04),
                      onTap: () => _openStudentsMenu(fieldContext, students),
                      child: row,
                    ),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: ShapeDecoration(color: Colors.white, shape: shape),
                child: row,
              );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelTitle(
            Icons.people_alt_outlined,
            'Estudiantes asociados',
            trailing: isList && students.length >= 2
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${students.length}',
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          content,
        ],
      );
    },
  );

  /// Estilo de texto de botones con la fuente de la página (la del tema).
  TextStyle _buttonTextStyle(double size, FontWeight weight) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: weight,
      );

  /// Decoración común de las cajas (mismo estilo que el resto de tarjetas).
  BoxDecoration _flatCardDecoration() => BoxDecoration(
    color: Colors.white,
    border: Border.all(color: const Color(0xFFDCE6F5)),
    borderRadius: BorderRadius.circular(15),
  );

  /// Sección inferior izquierda: título + caja con logo del método y monto.
  Widget _totalSection(Map<String, dynamic> pago) {
    final isUsd = _text(pago['moneda'], fallback: 'USD').toUpperCase() == 'USD';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle(Icons.payments_outlined, 'Monto total del reporte de pago'),
        const SizedBox(height: 6),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _flatCardDecoration(),
          child: Row(
            children: [
              _methodBadge(pago, size: 38),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pagado con',
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _method(pago),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _originalAmount(pago),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                          height: 1.1,
                        ),
                      ),
                      if (!isUsd)
                        Text(
                          '≈ ${_equivalent(pago)}',
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Sección inferior derecha (misma altura que _totalSection): título + caja
  /// con el aviso según el estado del pago.
  Widget _noteSection(Map<String, dynamic> pago, String status) {
    final (icon, color, title, text) = switch (status) {
      'aprobado' => (
        Icons.check_circle_outline_rounded,
        _green,
        'Aplicación del pago',
        'Se aplicó a las cuotas más antiguas y el excedente quedó como saldo a favor.',
      ),
      'rechazado' => (
        Icons.highlight_off_rounded,
        _red,
        'Motivo del rechazo',
        _text(pago['motivo_rechazo']),
      ),
      _ => (
        Icons.info_outline_rounded,
        _blue,
        'Antes de aprobar',
        'Verifica que el monto, la fecha y la referencia coincidan con el comprobante.',
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle(Icons.fact_check_outlined, title),
        const SizedBox(height: 6),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _flatCardDecoration(),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Sección "Comprobante de pago" (título + tarjeta con vista previa).
  /// Con [fill] la vista previa se estira para llenar la columna.
  Widget _proofSection(
    Map<String, dynamic> pago,
    String path,
    Future<String?> urlFuture, {
    bool fill = false,
  }) {
    final isPdf = RegExp(r'\.pdf(?:$|\?)', caseSensitive: false).hasMatch(path);

    final cardBody = FutureBuilder<String?>(
      future: urlFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final url = snapshot.data;
        final canOpen = !loading && url != null && url.isNotEmpty;

        final Widget content;
        if (path.isEmpty) {
          content = const Text(
            'No se adjuntó un comprobante.',
            style: TextStyle(color: _muted, fontSize: 12),
          );
        } else if (loading) {
          content = const CircularProgressIndicator(
            color: _blue,
            strokeWidth: 2.5,
          );
        } else if (url == null || url.isEmpty) {
          content = const Text(
            'No fue posible obtener el comprobante.',
            style: TextStyle(color: _muted, fontSize: 12),
          );
        } else if (isPdf) {
          content = const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf_outlined, color: _red, size: 46),
              SizedBox(height: 9),
              Text(
                'Comprobante PDF',
                style: TextStyle(fontWeight: FontWeight.w800, color: _navy),
              ),
              SizedBox(height: 5),
              Text(
                'Toca para abrir el documento',
                style: TextStyle(fontSize: 11.5, color: _muted),
              ),
            ],
          );
        } else {
          content = Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) => progress == null
                      ? child
                      : Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _blue,
                            value: progress.expectedTotalBytes == null
                                ? null
                                : progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!,
                          ),
                        ),
                  errorBuilder: (ctx, error, stack) => const Center(
                    child: Text(
                      'No fue posible mostrar la imagen.',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _navy.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.zoom_in_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Clic para ampliar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final previewBox = Material(
          color: const Color(0xFFF3F7FC),
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: canOpen
                ? () => _openComprobante(url!, isPdf: isPdf, pago: pago)
                : null,
            borderRadius: BorderRadius.circular(13),
            hoverColor: _blue.withValues(alpha: 0.055),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDCE6F5)),
                borderRadius: BorderRadius.circular(13),
              ),
              clipBehavior: Clip.antiAlias,
              child: Center(child: content),
            ),
          ),
        );

        return Column(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fill)
              Expanded(child: previewBox)
            else
              SizedBox(height: 230, child: previewBox),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                onPressed: canOpen
                    ? () => _openComprobante(url!, isPdf: isPdf, pago: pago)
                    : null,
                icon: Icon(
                  isPdf ? Icons.open_in_new_rounded : Icons.zoom_in_rounded,
                  size: 17,
                ),
                label: Text(isPdf ? 'Abrir PDF' : 'Ampliar comprobante'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blue,
                  side: const BorderSide(color: _border),
                  textStyle: _buttonTextStyle(13, FontWeight.w800),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 32,
              child: TextButton.icon(
                onPressed: canOpen ? () => _downloadComprobante(pago) : null,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Descargar comprobante'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF55709F),
                  textStyle: _buttonTextStyle(12.5, FontWeight.w700),
                ),
              ),
            ),
          ],
        );
      },
    );

    final card = _detailCard(
      padding: const EdgeInsets.all(12),
      child: cardBody,
    );

    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle(Icons.image_outlined, 'Comprobante de pago'),
        const SizedBox(height: 6),
        if (fill) Expanded(child: card) else card,
      ],
    );
  }

  /// Fondo del modal (las tarjetas blancas resaltan sobre él).
  static const Color _modalBg = Color(0xFFEEF3FB);

  /// Botón grande de acción (52 px). Aprobar y Rechazar comparten el mismo
  /// efecto hover (ver _HoverActionButton).
  Widget _bigActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool primary,
  }) => _HoverActionButton(
    label: label,
    icon: icon,
    color: primary ? _green : _red,
    filled: primary,
    onPressed: onPressed,
  );

  /// Pie fijo. En escritorio usa las MISMAS dos columnas del cuerpo: el
  /// mensaje bajo la columna izquierda y los botones (Rechazar | Aprobar)
  /// ocupando todo el ancho de la columna del comprobante.
  Widget _reportFooter(
    BuildContext ctx,
    Map<String, dynamic> pago,
    String status, {
    required bool stacked,
  }) {
    final (icon, message, color) = switch (status) {
      'aprobado' => (
        Icons.check_circle_outline_rounded,
        'Este reporte ya fue aprobado.',
        _green,
      ),
      'rechazado' => (
        Icons.highlight_off_rounded,
        'Este reporte fue rechazado.',
        _red,
      ),
      _ => (
        Icons.schedule_rounded,
        'El reporte aún no ha sido conciliado.',
        _amber,
      ),
    };

    final text = Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12.5,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    final Widget? buttons = status == 'pendiente'
        ? Row(
            children: [
              Expanded(
                child: _bigActionButton(
                  label: 'Aprobar pago',
                  icon: Icons.check_circle_rounded,
                  primary: true,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _approvePayment(pago);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _bigActionButton(
                  label: 'Rechazar',
                  icon: Icons.close_rounded,
                  primary: false,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _rejectPaymentDialog(pago['id'].toString());
                  },
                ),
              ),
            ],
          )
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE3EAF5))),
      ),
      child: stacked
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                if (buttons != null) ...[const SizedBox(height: 12), buttons],
              ],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                Expanded(child: buttons ?? const SizedBox.shrink()),
              ],
            ),
    );
  }

  void _showDetailModal(Map<String, dynamic> pago) {
    final status = _status(pago);
    final proof = _text(pago['comprobante_path'], fallback: '');
    final urlFuture = proof.isEmpty
        ? Future<String?>.value(null)
        : _proofUrlFor(proof);
    final linkedStudentsFuture = _studentsFor(pago);
    final copiedReference = ValueNotifier<bool>(false);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        // Escritorio / tablet horizontal: todo visible, sin scroll.
        final wide = size.width >= 780 && size.height >= 640;
        final maxH = size.height - 28;
        final fixedH = maxH > 640 ? 640.0 : maxH;

        final header = _reportHeader(ctx, pago, status);
        final footer = _reportFooter(ctx, pago, status, stacked: !wide);

        Widget infoSection({required bool fill}) => Column(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panelTitle(
              Icons.person_outline_rounded,
              'Información del representante',
            ),
            const SizedBox(height: 6),
            if (fill)
              Expanded(
                child: _representativeCard(
                  ctx,
                  pago,
                  copiedReference,
                  fill: true,
                ),
              )
            else
              _representativeCard(ctx, pago, copiedReference),
          ],
        );

        final Widget content;
        if (wide) {
          // Dos columnas del MISMO ancho y todas las separaciones de 12 px.
          // En la izquierda, la tarjeta del representante absorbe el espacio
          // sobrante (repartido en partes iguales entre sus filas); abajo,
          // monto total y aviso miden igual y quedan alineados.
          content = SizedBox(
            height: fixedH,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, c) {
                              // Altura natural aproximada: representante (233)
                              // + monto total (86) + 2 separaciones (24) = 343.
                              // Con lo que sobra se decide cuántos
                              // estudiantes caben en línea (2, 1 o ninguno).
                              final spare = c.maxHeight - 343;
                              final maxInline = spare >= 152
                                  ? 2
                                  : (spare >= 100 ? 1 : 0);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: infoSection(fill: true)),
                                  const SizedBox(height: 12),
                                  _studentsSection(
                                    linkedStudentsFuture,
                                    maxInline: maxInline,
                                  ),
                                  const SizedBox(height: 12),
                                  _totalSection(pago),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _proofSection(
                                  pago,
                                  proof,
                                  urlFuture,
                                  fill: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _noteSection(pago, status),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                footer,
              ],
            ),
          );
        } else {
          // Pantallas pequeñas: una columna con scroll y pie siempre visible.
          content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            infoSection(fill: false),
                            const SizedBox(height: 12),
                            _studentsSection(linkedStudentsFuture),
                            const SizedBox(height: 12),
                            _totalSection(pago),
                            const SizedBox(height: 12),
                            _proofSection(pago, proof, urlFuture),
                            const SizedBox(height: 12),
                            _noteSection(pago, status),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              footer,
            ],
          );
        }

        return Dialog(
          backgroundColor: _modalBg,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 920, maxHeight: maxH),
            child: content,
          ),
        );
      },
    ).whenComplete(copiedReference.dispose);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: _red));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_header(), const SizedBox(height: 23), _paymentsPanel()],
    );
  }
}

/// Hover ligero: un borde coloreado por estado y fondo azul casi imperceptible.
/// Toda la fila puede abrir su detalle; el botón "ver" conserva su acción.
class _ReconciliationHoverSurface extends StatefulWidget {
  const _ReconciliationHoverSurface({
    required this.child,
    required this.accent,
    required this.onTap,
    this.onHoverStart,
  });

  final Widget child;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onHoverStart;

  @override
  State<_ReconciliationHoverSurface> createState() =>
      _ReconciliationHoverSurfaceState();
}

class _ReconciliationHoverSurfaceState
    extends State<_ReconciliationHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 150);
    return MouseRegion(
      onEnter: (_) {
        widget.onHoverStart?.call();
        setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: duration,
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFFF7FAFF) : Colors.white,
          border: Border.all(
            color: _hovered
                ? AppColors.primaryBlue.withValues(alpha: 0.53)
                : widget.accent.withValues(alpha: 0.43),
            width: _hovered ? 1.5 : 1.15,
          ),
          borderRadius: BorderRadius.circular(13),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.085),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            highlightColor: AppColors.primaryBlue.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(13),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Visor ampliado del comprobante: la imagen se ajusta a la pantalla, con
/// zoom (rueda, pellizco, doble clic y botones), arrastre, descarga y cierre.
class _ProofViewerDialog extends StatefulWidget {
  const _ProofViewerDialog({
    required this.url,
    required this.title,
    this.subtitle = '',
    this.onDownload,
  });

  final String url;
  final String title;
  final String subtitle;
  final VoidCallback? onDownload;

  @override
  State<_ProofViewerDialog> createState() => _ProofViewerDialogState();
}

class _ProofViewerDialogState extends State<_ProofViewerDialog> {
  static const double _minScale = 1;
  static const double _maxScale = 6;

  final TransformationController _controller = TransformationController();
  Size _viewport = Size.zero;
  Offset _doubleTapAt = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();

  Offset get _center => Offset(_viewport.width / 2, _viewport.height / 2);

  /// Mantiene la imagen dentro del visor al alejar o mover.
  Matrix4 _clamped(Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    if (s <= _minScale + 0.001 || _viewport.isEmpty) return Matrix4.identity();
    final t = m.getTranslation();
    final tx = t.x.clamp(_viewport.width * (1 - s), 0.0).toDouble();
    final ty = t.y.clamp(_viewport.height * (1 - s), 0.0).toDouble();
    return Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  void _zoomAround(double factor, Offset focal) {
    final current = _scale;
    final target = (current * factor).clamp(_minScale, _maxScale).toDouble();
    final f = target / current;
    if ((f - 1).abs() < 0.001) return;
    final step =
        Matrix4.translationValues(focal.dx, focal.dy, 0) *
        Matrix4.diagonal3Values(f, f, 1) *
        Matrix4.translationValues(-focal.dx, -focal.dy, 0);
    _controller.value = _clamped(step * _controller.value);
  }

  void _reset() => _controller.value = Matrix4.identity();

  void _toggleDoubleTap() {
    if (_scale > 1.05) {
      _reset();
    } else {
      _zoomAround(2.5, _doubleTapAt);
    }
  }

  static const Color _viewerBg = Color(0xFFEEF3FB);
  static const Color _line = Color(0xFFE3EAF5);

  Widget _toolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    color: AppColors.darkNavy,
    visualDensity: VisualDensity.compact,
  );

  Widget _toolbar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDCE6F5)),
      boxShadow: [
        BoxShadow(
          color: AppColors.darkNavy.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toolButton(
          icon: Icons.remove_rounded,
          tooltip: 'Alejar',
          onPressed: () => _zoomAround(1 / 1.4, _center),
        ),
        SizedBox(
          width: 52,
          child: ValueListenableBuilder<Matrix4>(
            valueListenable: _controller,
            builder: (context, matrix, child) => Text(
              '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.darkNavy,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        _toolButton(
          icon: Icons.add_rounded,
          tooltip: 'Acercar',
          onPressed: () => _zoomAround(1.4, _center),
        ),
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: _line,
        ),
        _toolButton(
          icon: Icons.fit_screen_rounded,
          tooltip: 'Ajustar a la pantalla',
          onPressed: _reset,
        ),
      ],
    ),
  );

  /// Cabecera con el mismo estilo que la del detalle del pago.
  Widget _topBar(bool narrow) => Container(
    padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.image_outlined,
            color: AppColors.primaryBlue,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Container(width: 1, height: 40, color: _line),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.darkNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.onDownload != null) ...[
          const SizedBox(width: 10),
          narrow
              ? IconButton.filled(
                  tooltip: 'Descargar',
                  onPressed: widget.onDownload,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.download_rounded),
                )
              : FilledButton.icon(
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Descargar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    textStyle:
                        (Theme.of(context).textTheme.bodyMedium ??
                                const TextStyle())
                            .copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
        ],
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.close_rounded,
            size: 22,
            color: AppColors.textMuted,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 640;
    return Dialog(
      insetPadding: EdgeInsets.all(narrow ? 8 : 20),
      backgroundColor: _viewerBg,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topBar(narrow),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FD),
                      border: Border.all(color: const Color(0xFFDCE6F5)),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _viewport = constraints.biggest;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                onDoubleTapDown: (d) =>
                                    _doubleTapAt = d.localPosition,
                                onDoubleTap: _toggleDoubleTap,
                                child: InteractiveViewer(
                                  transformationController: _controller,
                                  minScale: _minScale,
                                  maxScale: _maxScale,
                                  clipBehavior: Clip.hardEdge,
                                  child: Padding(
                                    // Espacio inferior para que la barra de
                                    // zoom no tape la imagen.
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      12,
                                      12,
                                      66,
                                    ),
                                    // width/height infinitos: la imagen se
                                    // escala para llenar el visor.
                                    child: Image.network(
                                      widget.url,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.medium,
                                      loadingBuilder:
                                          (
                                            context,
                                            child,
                                            progress,
                                          ) => progress == null
                                          ? child
                                          : const Center(
                                              child: CircularProgressIndicator(
                                                color: AppColors.primaryBlue,
                                                strokeWidth: 2.5,
                                              ),
                                            ),
                                      errorBuilder: (context, error, stack) =>
                                          const Center(
                                            child: Text(
                                              'No se pudo cargar la imagen.',
                                              style: TextStyle(
                                                color: AppColors.textMuted,
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 14,
                              left: 0,
                              right: 0,
                              child: Center(child: _toolbar()),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                child: Text(
                  narrow
                      ? 'Pellizca para ampliar · Arrastra para mover'
                      : 'Rueda para ampliar · Arrastra para mover · Doble clic para acercar',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón grande con el MISMO hover para aprobar y rechazar: se eleva 2 px,
/// proyecta una sombra de su propio color y intensifica su relleno/borde.
class _HoverActionButton extends StatefulWidget {
  const _HoverActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onPressed;

  @override
  State<_HoverActionButton> createState() => _HoverActionButtonState();
}

class _HoverActionButtonState extends State<_HoverActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final radius = BorderRadius.circular(14);
    final color = widget.color;
    final filled = widget.filled;
    final fg = filled ? Colors.white : color;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        height: 52,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          gradient: filled
              ? LinearGradient(
                  colors: [
                    Color.lerp(color, Colors.white, _hovered ? 0.2 : 0.1)!,
                    Color.lerp(color, Colors.black, _hovered ? 0.04 : 0.12)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          // Relleno opaco: con un fondo translúcido la sombra se veía a
          // través del botón y ensuciaba el color.
          color: filled ? null : Colors.white,
          borderRadius: radius,
          border: filled
              ? null
              : Border.all(
                  color: color.withValues(alpha: _hovered ? 1 : 0.5),
                  width: 1.4,
                ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(
                alpha: _hovered ? (filled ? 0.34 : 0.2) : (filled ? 0.18 : 0),
              ),
              blurRadius: _hovered ? 18 : 10,
              offset: Offset(0, _hovered ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: radius,
            hoverColor: Colors.transparent,
            splashColor: fg.withValues(alpha: 0.12),
            highlightColor: fg.withValues(alpha: 0.08),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 21, color: fg),
                  const SizedBox(width: 9),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
