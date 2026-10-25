import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/bcv_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/session/idle_session_store.dart';
import '../../../../main.dart';
import '../../../landing/presentation/screens/home_screen.dart';
import '../widgets/students_import_card.dart';
import '../widgets/payment_reconciliation_widget.dart';
import '../widgets/generate_billing_dialog.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

//
// Modelos de apoyo
//
class _MonthTotal {
  final String label;
  final double value;
  const _MonthTotal(this.label, this.value);
}

class _PendingItem {
  final String studentId;
  final double saldo;
  final int daysOverdue; // <= 0 significa vigente (aún no vence)
  const _PendingItem(this.studentId, this.saldo, this.daysOverdue);
}

class _PagoRow {
  final String representative;
  final String student;
  final String concept;
  final double amount;
  final String currency;
  final String status; // pendiente | aprobado | rechazado
  final DateTime? date;

  const _PagoRow({
    required this.representative,
    required this.student,
    required this.concept,
    required this.amount,
    required this.currency,
    required this.status,
    required this.date,
  });
}

class _NavDef {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  const _NavDef(this.icon, this.activeIcon, this.title);
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final BcvService _bcvService = BcvService();

  static const _navItems = <_NavDef>[
    _NavDef(Icons.home_outlined, Icons.home, 'Resumen'),
    _NavDef(Icons.people_outline, Icons.people, 'Estudiantes'),
    _NavDef(
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
      'Pagos',
    ),
    _NavDef(Icons.receipt_long_outlined, Icons.receipt_long, 'Conciliación'),
    _NavDef(Icons.bar_chart_outlined, Icons.bar_chart, 'Reportes'),
  ];

  static const _monthsShort = [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];

  static const _monthsLong = [
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

  static const _weekdays = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  static const _agingLabels = [
    'Todas',
    'Vigentes',
    '1-30 días',
    'Más de 30 días',
  ];

  static const _green = Color(0xFF059669);
  static const _amber = Color(0xFFD97706);
  static const _red = Color(0xFFDC2626);

  // Estado de la pantalla
  bool _loading = true;
  String? _error;
  bool _sidebarExpanded = false;
  int _navIndex = 0;

  // Validación de cuenta / colegio
  String? _colegioId;
  bool _needsStudents = false; // el colegio no tiene estudiantes aún
  bool _noSchool = false; // el perfil no tiene colegio_id

  // Datos
  String _adminName = '';
  String _schoolName = '';
  double? _tasa;
  String _tasaSubtitle = '';
  int _studentsTotal = 0;
  int _solventes = 0;
  int _pendientes = 0;
  int _insolventes = 0;
  List<_MonthTotal> _monthly = [];
  int _rangeMonths = 6;
  int? _selectedBar;
  List<_PendingItem> _pending = [];
  double _totalBilled = 0;
  int _agingFilter = 0;
  int _pendingReceipts = 0;
  int _receiptsLastHour = 0;
  List<_PagoRow> _recent = [];

  //
  // Cierre automático por inactividad
  //
  static const Duration _idleTimeout = Duration(minutes: 15);
  static const Duration _idleWarning = Duration(seconds: 60);
  Timer? _idleTicker;
  DateTime _lastActivity = DateTime.now();
  bool _idleWarningOpen = false;
  bool _loggingOut = false;
  bool _checking = false;
  DateTime _persistedActivity = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<AuthState>? _authSub;
  final ValueNotifier<int> _idleSecondsLeft = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut && !_loggingOut) {
        _forceLogout('Tu sesión ya no es válida. Inicia sesión nuevamente.');
      }
    });
    _bootSession();
  }

  Future<void> _bootSession() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (supabase.auth.currentSession == null) {
      await _forceLogout('Debes iniciar sesión para continuar.');
      return;
    }
    final last = await IdleSessionStore.last();
    if (!mounted) return;
    if (last != null && DateTime.now().difference(last) >= _idleTimeout) {
      await _logoutByInactivity();
      return;
    }
    _startIdleWatch();
    _load();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stopIdleWatch();
    _idleSecondsLeft.dispose();
    super.dispose();
  }

  void _startIdleWatch() {
    _lastActivity = DateTime.now();
    _persistedActivity = _lastActivity;
    IdleSessionStore.touch(_lastActivity);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerActivity);
    HardwareKeyboard.instance.addHandler(_onKeyActivity);
    _idleTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkIdle(),
    );
  }

  void _stopIdleWatch() {
    _idleTicker?.cancel();
    _idleTicker = null;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerActivity);
    HardwareKeyboard.instance.removeHandler(_onKeyActivity);
  }

  void _onPointerActivity(PointerEvent event) => _markActivity();

  bool _onKeyActivity(KeyEvent event) {
    _markActivity();
    return false;
  }

  void _markActivity() {
    if (_idleWarningOpen) return;
    _lastActivity = DateTime.now();
  }

  Future<void> _checkIdle() async {
    if (!mounted || _loggingOut || _checking) return;
    _checking = true;
    try {
      var idle = DateTime.now().difference(_lastActivity);
      if (idle >= _idleTimeout - _idleWarning) {
        final stored = await IdleSessionStore.last();
        if (stored != null && stored.isAfter(_lastActivity)) {
          _lastActivity = stored;
          idle = DateTime.now().difference(_lastActivity);
        }
      }
      if (!mounted || _loggingOut) return;
      if (idle >= _idleTimeout) {
        await _logoutByInactivity();
        return;
      }
      if (_lastActivity.difference(_persistedActivity) >= const Duration(seconds: 10)) {
        _persistedActivity = _lastActivity;
        IdleSessionStore.touch(_lastActivity);
      }
      final left = _idleTimeout - idle;
      if (left <= _idleWarning) {
        _idleSecondsLeft.value = (left.inMilliseconds / 1000).ceil();
        if (!_idleWarningOpen) _showIdleWarning();
      }
    } finally {
      _checking = false;
    }
  }

  void _showIdleWarning() {
    _idleWarningOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.timer_outlined, color: Color(0xFFD97706)),
            SizedBox(width: 10),
            Expanded(child: Text('Sesión por expirar')),
          ],
        ),
        content: ValueListenableBuilder<int>(
          valueListenable: _idleSecondsLeft,
          builder: (_, seconds, __) => Text(
            'Por seguridad, tu sesión se cerrará por inactividad en $seconds s.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: _logoutByInactivity,
            child: const Text('Cerrar sesión'),
          ),
          ElevatedButton(
            onPressed: () {
              _lastActivity = DateTime.now();
              _idleWarningOpen = false;
              Navigator.of(ctx).pop();
            },
            child: const Text('Seguir conectado'),
          ),
        ],
      ),
    ).then((_) => _idleWarningOpen = false);
  }

  Future<void> _logoutByInactivity() => _forceLogout('Tu sesión se cerró por inactividad.');

  Future<void> _forceLogout(String message) async {
    if (_loggingOut) return;
    final messenger = ScaffoldMessenger.of(context);
    await _logout();
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  //
  // Utilidades
  //
  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  String _money(double v, {int decimals = 2}) {
    final neg = v < 0;
    final fixed = v.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
      buf.write(intPart[i]);
    }
    final dec = decimals > 0 ? ',${parts[1]}' : '';
    return '${neg ? '-' : ''}$buf$dec';
  }

  String _pct(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  String _compact(double v) {
    if (v >= 1000000) {
      return '\$${(v / 1000000).toStringAsFixed(1).replaceAll('.', ',')}M';
    }
    if (v >= 1000) {
      return '\$${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1).replaceAll('.', ',')}k';
    }
    return v.toStringAsFixed(0);
  }

  double _niceMax(double v) {
    if (v <= 0) return 100;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / exp;
    final nice = f <= 1 ? 1.0 : (f <= 2 ? 2.0 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5.0 : 10.0)));
    return nice * exp;
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _hm(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _when(DateTime? d) {
    if (d == null) return '-';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoy, ${_hm(d)}';
    if (diff == 1) return 'Ayer, ${_hm(d)}';
    return '${d.day} ${_monthsShort[d.month - 1].toLowerCase()}';
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return 'A';
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }

  String get _firstName {
    final parts = _adminName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'administrador' : parts.first;
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what estará disponible próximamente.')),
    );
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    _stopIdleWatch();
    await IdleSessionStore.clear();
    try {
      await supabase.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  //
  // Carga de datos
  //
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _needsStudents = false;
      _noSchool = false;
    });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        await _logout();
        return;
      }
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final start12 = DateTime(now.year, now.month - 11, 1);

      // 1. Perfil del administrador
      final perfil = await supabase
          .from('perfiles')
          .select('nombre_completo, colegio_id')
          .eq('id', user.id)
          .maybeSingle();

      final colegioId = perfil?['colegio_id']?.toString();
      final adminName =
          (perfil?['nombre_completo'] ?? user.email ?? 'Administrador')
              .toString();

      if (colegioId == null || colegioId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _adminName = adminName;
          _colegioId = null;
          _noSchool = true;
          _loading = false;
        });
        return;
      }

      // 2. ¿Existe al menos un estudiante en este colegio?
      final exists = await supabase
          .from('estudiantes')
          .select('id')
          .eq('colegio_id', colegioId)
          .limit(1);

      if ((exists as List).isEmpty) {
        if (!mounted) return;
        setState(() {
          _adminName = adminName;
          _colegioId = colegioId;
          _needsStudents = true;
          _loading = false;
        });
        _loadSchool(colegioId);
        return;
      }

      // 3. Estudiantes activos del colegio
      List<Map<String, dynamic>> students = [];
      try {
        final resEst = await supabase
            .from('estudiantes')
            .select('id')
            .eq('colegio_id', colegioId)
            .eq('activo', true);
        students = List<Map<String, dynamic>>.from(resEst);
      } catch (e) {
        debugPrint('Error en estudiantes: $e');
      }

      // 4. Saldo Cuotas
      List<Map<String, dynamic>> saldoRows = [];
      try {
        final resSaldo = await supabase
            .from('v_saldo_cuotas')
            .select('cuota_id, estudiante_id, monto_usd, saldo_usd');
        saldoRows = List<Map<String, dynamic>>.from(resSaldo);
      } catch (e) {
        debugPrint('Error en v_saldo_cuotas: $e');
      }

      // 5. Cuotas
      List<Map<String, dynamic>> cuotaRows = [];
      try {
        final resCuotas = await supabase
            .from('cuotas')
            .select('id, fecha_vencimiento');
        cuotaRows = List<Map<String, dynamic>>.from(resCuotas);
      } catch (e) {
        debugPrint('Error en cuotas: $e');
      }

      // 6. Pagos Aprobados
      List<Map<String, dynamic>> paidRows = [];
      try {
        final resPaid = await supabase
            .from('pagos')
            .select('monto_usd_equivalente, fecha_pago')
            .eq('estado', 'aprobado')
            .gte('fecha_pago', _isoDate(start12));
        paidRows = List<Map<String, dynamic>>.from(resPaid);
      } catch (e) {
        debugPrint('Error en pagos aprobados: $e');
      }

      // 7. Pagos Pendientes
      List<Map<String, dynamic>> pendingRows = [];
      try {
        final resPending = await supabase
            .from('pagos')
            .select('id, creado_at')
            .eq('estado', 'pendiente');
        pendingRows = List<Map<String, dynamic>>.from(resPending);
      } catch (e) {
        debugPrint('Error en pagos pendientes: $e');
      }

      // 8. Tasa BCV Oficial obtenida mediante el BcvService en vivo
      double? tasa;
      String tasaSubtitle = '';
      try {
        final bcvData = await _bcvService.getLatestBcvRate();
        tasa = bcvData.rate;
        tasaSubtitle = bcvData.dateFormatted;
      } catch (e) {
        debugPrint('Error al obtener Tasa BCV en el panel de admin: $e');
      }

      // Vencimiento de cada cuota
      final venc = <String, DateTime?>{
        for (final c in cuotaRows)
          c['id'].toString(): DateTime.tryParse('${c['fecha_vencimiento']}'),
      };

      // Estado de cada estudiante: 0 solvente, 1 pendiente, 2 insolvente
      final status = <String, int>{
        for (final s in students) s['id'].toString(): 0,
      };

      final pending = <_PendingItem>[];
      var billed = 0.0;
      for (final row in saldoRows) {
        final monto = _num(row['monto_usd']);
        final saldo = _num(row['saldo_usd']);
        billed += monto;
        if (saldo <= 0.01) continue;

        final studentId = row['estudiante_id'].toString();
        final due = venc[row['cuota_id'].toString()];
        final overdue = due == null ? 0 : today.difference(due).inDays;
        pending.add(_PendingItem(studentId, saldo, overdue));

        if (status.containsKey(studentId)) {
          if (overdue > 0) {
            status[studentId] = 2;
          } else if (status[studentId] == 0) {
            status[studentId] = 1;
          }
        }
      }

      // Recaudación mensual (últimos 12 meses)
      final totals = <String, double>{};
      for (final p in paidRows) {
        final key = '${p['fecha_pago']}'.length >= 7
            ? '${p['fecha_pago']}'.substring(0, 7)
            : '';
        if (key.isEmpty) continue;
        totals[key] = (totals[key] ?? 0) + _num(p['monto_usd_equivalente']);
      }

      final monthly = <_MonthTotal>[];
      for (var i = 11; i >= 0; i--) {
        final d = DateTime(now.year, now.month - i, 1);
        final key =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
        monthly.add(_MonthTotal(_monthsShort[d.month - 1], totals[key] ?? 0));
      }

      // Comprobantes pendientes
      var lastHour = 0;
      for (final p in pendingRows) {
        final d = DateTime.tryParse('${p['creado_at']}')?.toLocal();
        if (d != null && now.difference(d).inMinutes < 60) lastHour++;
      }

      if (!mounted) return;
      setState(() {
        _adminName = adminName;
        _colegioId = colegioId;
        _studentsTotal = students.length;
        _solventes = status.values.where((v) => v == 0).length;
        _pendientes = status.values.where((v) => v == 1).length;
        _insolventes = status.values.where((v) => v == 2).length;
        _pending = pending;
        _totalBilled = billed;
        _monthly = monthly;
        _selectedBar = null;
        _pendingReceipts = pendingRows.length;
        _receiptsLastHour = lastHour;
        _tasa = tasa;
        _tasaSubtitle = tasaSubtitle;
        _loading = false;
      });

      _loadSchool(colegioId);
      _loadRecentPayments();
    } catch (e) {
      debugPrint('Error crítico al cargar el panel administrativo: $e');
      if (!mounted) return;
      setState(() {
        _error = kDebugMode
            ? 'Error: $e'
            : 'No pudimos cargar los datos del panel. Revisa tu conexión y vuelve a intentarlo.';
        _loading = false;
      });
    }
  }

  Future<void> _loadSchool(String? colegioId) async {
    if (colegioId == null) return;
    try {
      final row = await supabase
          .from('colegios')
          .select('nombre')
          .eq('id', colegioId)
          .maybeSingle();

      if (row != null && mounted) {
        setState(() => _schoolName = (row['nombre'] ?? '').toString());
      }
    } catch (_) {}
  }

  Future<void> _loadRecentPayments() async {
    List<dynamic> rows = [];
    try {
      rows = await supabase
          .from('pagos')
          .select(
            'id, monto, moneda, estado, creado_at, representantes (nombres, apellidos), '
            'pago_aplicaciones (cuotas (periodo, estudiantes (nombres, apellidos), conceptos_cobro(nombre)))',
          )
          .order('creado_at', ascending: false)
          .limit(6);
    } catch (_) {
      try {
        rows = await supabase
            .from('pagos')
            .select(
              'id, monto, moneda, estado, creado_at, representantes (nombres, apellidos)',
            )
            .order('creado_at', ascending: false)
            .limit(6);
      } catch (e) {
        debugPrint('Error al cargar pagos recientes: $e');
      }
    }

    final list = rows
        .whereType<Map>()
        .map((m) => _toPagoRow(Map<String, dynamic>.from(m)))
        .toList();

    if (mounted) setState(() => _recent = list);
  }

  _PagoRow _toPagoRow(Map<String, dynamic> m) {
    final rep = _asMap(m['representantes']);
    final repName = rep == null
        ? 'Representante'
        : '${rep['nombres'] ?? ''} ${rep['apellidos'] ?? ''}'.trim();

    var student = '-';
    var concept = '-';
    final aps = m['pago_aplicaciones'];
    if (aps is List && aps.isNotEmpty && aps.first is Map) {
      final cuota = _asMap((aps.first as Map)['cuotas']);
      final est = _asMap(cuota?['estudiantes']);
      final con = _asMap(cuota?['conceptos_cobro']);
      final periodo = cuota?['periodo'];

      if (est != null) {
        student = '${est['nombres'] ?? ''} ${est['apellidos'] ?? ''}'.trim();
      }
      if (con != null) {
        concept = '${con['nombre'] ?? ''}${periodo != null ? ' $periodo' : ''}';
        if (aps.length > 1) concept += ' +${aps.length - 1}';
      }
    }

    return _PagoRow(
      representative: repName.isEmpty ? 'Representante' : repName,
      student: student,
      concept: concept,
      amount: _num(m['monto']),
      currency: (m['moneda'] ?? 'USD').toString(),
      status: (m['estado'] ?? 'pendiente').toString(),
      date: DateTime.tryParse('${m['creado_at']}')?.toLocal(),
    );
  }

  //
  // Estructura principal
  //
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final sidebarW = _sidebarExpanded ? 250.0 : 76.0;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: isDesktop
          ? null
          : Drawer(
              backgroundColor: const Color(0xFF0F172A),
              child: _buildSidebar(expanded: true),
            ),
      body: Stack(
        children: [
          Row(
            children: [
              if (isDesktop) _buildSidebar(expanded: _sidebarExpanded),
              Expanded(
                child: Column(
                  children: [
                    _buildTopHeader(isDesktop),
                    Expanded(child: _buildBody()),
                  ],
                ),
              ),
            ],
          ),
          if (isDesktop)
            Positioned(
              left: sidebarW - 12,
              top: 64,
              child: _buildCollapseButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildCollapseButton() {
    return InkWell(
      onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
      customBorder: const CircleBorder(),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(
          _sidebarExpanded ? Icons.chevron_left : Icons.chevron_right,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                color: AppColors.textMuted,
                size: 36,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SelectableText(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_noSchool) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.apartment_outlined,
                color: AppColors.textMuted,
                size: 36,
              ),
              const SizedBox(height: 12),
              const Text(
                'Tu cuenta aún no está vinculada a ninguna institución.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.darkNavy,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Contacta al soporte para que asignen un colegio a tu perfil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Verificar de nuevo'),
              ),
            ],
          ),
        ),
      );
    }

    if (_needsStudents && _colegioId != null) {
      return StudentsImportCard(colegioId: _colegioId!, onImported: _load);
    }

    // --- INTEGRACIÓN HU9: Pestaña "Conciliación" (_navIndex == 3) ---
    if (_navIndex == 3 && _colegioId != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: PaymentReconciliationWidget(
                colegioId: _colegioId!,
                onPaymentProcessed: _load,
              ),
            ),
          ),
        ),
      );
    }

    // Para las demás pestañas aún pendientes (Estudiantes, Pagos, Reportes)
    if (_navIndex != 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _navItems[_navIndex].icon,
              color: AppColors.textMuted,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              '${_navItems[_navIndex].title} estará disponible próximamente.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _navIndex = 0),
              child: const Text('Volver al resumen'),
            ),
          ],
        ),
      );
    }

    // Pestaña principal: Resumen (_navIndex == 0)
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGreeting(),
                const SizedBox(height: 20),
                _buildQuickActions(),
                const SizedBox(height: 20),
                _grid(
                  wideCols: 4,
                  narrowCols: 2,
                  items: [
                    _kpiRecaudado(),
                    _kpiPorCobrar(),
                    _kpiComprobantes(),
                    _kpiEstudiantes(),
                  ],
                ),
                const SizedBox(height: 20),
                _buildChartsRow(),
                const SizedBox(height: 20),
                _buildRecentPayments(),
                const SizedBox(height: 24),
                _buildFooterNotice(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  //
  // Barra lateral
  //
  Widget _buildSidebar({required bool expanded}) {
    return Container(
      width: expanded ? 250 : 76,
      color: const Color(0xFF0F172A),
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 16 : 12,
        vertical: 20,
      ),
      child: Column(
        crossAxisAlignment:
            expanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          _sidebarInstitution(expanded),
          SizedBox(height: expanded ? 28 : 24),
          if (expanded) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'MENÚ PRINCIPAL',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < _navItems.length; i++) _navItem(i, expanded),
          const Spacer(),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          _sidebarUser(expanded),
        ],
      ),
    );
  }

  Widget _sidebarInstitution(bool expanded) {
    final school = _schoolName.isEmpty ? 'Mi institución' : _schoolName;
    final iconBox = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.apartment,
        color: AppColors.primaryBlue,
        size: 18,
      ),
    );

    if (!expanded) {
      return Tooltip(
        message: school,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Center(child: iconBox),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          iconBox,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'INSTITUCIÓN',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  school,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, bool expanded) {
    final item = _navItems[index];
    final selected = _navIndex == index;

    void onTap() {
      setState(() => _navIndex = index);
      if (!expanded &&
          Navigator.of(context).canPop() &&
          (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
        Navigator.of(context).pop();
      }
    }

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Tooltip(
          message: item.title,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1E3A8A) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primaryBlue : Colors.transparent,
                ),
              ),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                color: selected ? Colors.white : Colors.white60,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () {
          setState(() => _navIndex = index);
          if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
            Navigator.of(context).pop();
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1E3A8A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                selected ? item.activeIcon : item.icon,
                color: selected ? Colors.white : Colors.white60,
                size: 18,
              ),
              const SizedBox(width: 12),
              Text(
                item.title,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebarUser(bool expanded) {
    final avatar = _userMenu(
      child: CircleAvatar(
        radius: expanded ? 16 : 20,
        backgroundColor: AppColors.primaryBlue,
        child: Text(
          _initials(_adminName),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    if (!expanded) return avatar;

    return Row(
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _adminName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(
                'Administración',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white54, size: 18),
          onPressed: _logout,
          tooltip: 'Cerrar sesión',
        ),
      ],
    );
  }

  Widget _userMenu({required Widget child}) {
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      onSelected: (v) {
        if (v == 'logout') _logout();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 16),
              SizedBox(width: 8),
              Text('Cerrar sesión'),
            ],
          ),
        ),
      ],
      child: child,
    );
  }

  //
  // Encabezado superior
  //
  Widget _buildTopHeader(bool isDesktop) {
    final w = MediaQuery.of(context).size.width;
    final showTasa = w > 760;
    final compactTasa = w < 1150;
    final showUserText = w > 1000;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.darkNavy),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Menú',
            ),
          Expanded(
            child: Container(
              height: 38,
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: AppColors.textMuted, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Buscar alumno por cédula, código escolar o nombre...',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (showTasa) ...[
            _tasaChip(compactTasa),
            const SizedBox(width: 12),
          ],
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.notifications_none,
                  size: 18,
                  color: AppColors.darkNavy,
                ),
              ),
              if (_pendingReceipts > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          _userMenu(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFDBEAFE),
                  child: Text(
                    _initials(_adminName),
                    style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (showUserText) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          _adminName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkNavy,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const Row(
                        children: [
                          Icon(Icons.circle, size: 7, color: _green),
                          SizedBox(width: 4),
                          Text(
                            'Sesión activa',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tasaChip(bool compact) {
    final ok = _tasa != null;
    final bg = ok ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB);
    final border = ok ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A);
    final accent = ok ? _green : _amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Icon(
              ok ? Icons.check : Icons.priority_high,
              color: Colors.white,
              size: 11,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ok
                    ? 'Tasa BCV Oficial: 1 USD = ${_money(_tasa!)} VES'
                    : 'Sin tasa BCV registrada hoy',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              if (!compact)
                Text(
                  ok ? _tasaSubtitle : 'Los saldos en Bs. no se pueden calcular',
                  style: TextStyle(fontSize: 10, color: accent),
                ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
            Icon(Icons.schedule, size: 16, color: accent),
          ],
        ],
      ),
    );
  }

  // Saludo y acciones rápidas
  Widget _buildGreeting() {
    final now = DateTime.now();
    final date =
        '${_weekdays[now.weekday - 1]}, ${now.day} de ${_monthsLong[now.month - 1]}'
            .toUpperCase();
    final saludo = now.hour < 12
        ? 'Buenos días'
        : (now.hour < 19 ? 'Buenas tardes' : 'Buenas noches');

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          date,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$saludo, $_firstName',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Aquí tienes el pulso financiero de tu institución.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ],
    );

    final buttons = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: () => _soon('Vincular estudiantes'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkNavy,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.cardBorder),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.people_outline, size: 18),
          label: const Text(
            'Vincular estudiantes',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => setState(() => _navIndex = 3),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Conciliar comprobantes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_pendingReceipts',
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 860) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              buttons,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [left, const SizedBox(height: 16), buttons],
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return _card(
      padding: const EdgeInsets.all(12),
      child: _grid(
        wideCols: 4,
        narrowCols: 2,
        gap: 12,
        items: [
          _quickTile(
            leading: const Icon(
              Icons.calendar_month_outlined,
              color: Colors.white,
              size: 18,
            ),
            leadingBg: Colors.white.withValues(alpha: 0.12),
            title: 'Generar facturación masiva mensual',
            subtitle: 'Crea cargos para toda la matrícula',
            bg: const Color(0xFF0F172A),
            border: const Color(0xFF0F172A),
            titleColor: Colors.white,
            subColor: Colors.white60,
            onTap: () {
              if (_colegioId != null) {
                showDialog(
                  context: context,
                  builder: (context) => GenerateBillingDialog(
                    colegioId: _colegioId!,
                    onBillingGenerated: _load,
                  ),
                );
              }
            },
          ),
          _quickTile(
            leading: const Icon(
              Icons.file_download_outlined,
              color: AppColors.darkNavy,
              size: 18,
            ),
            leadingBg: const Color(0xFFF1F5F9),
            title: 'Exportar reportes',
            subtitle: 'PDF o CSV',
            bg: Colors.white,
            border: AppColors.cardBorder,
            titleColor: AppColors.darkNavy,
            subColor: AppColors.textMuted,
            onTap: () => _soon('La exportación de reportes'),
          ),
          _quickTile(
            leading: const Icon(
              Icons.shield_outlined,
              color: AppColors.primaryBlue,
              size: 18,
            ),
            leadingBg: const Color(0xFFDBEAFE),
            title: 'Ver auditoría de transacciones',
            subtitle: 'Bitácora y trazabilidad',
            bg: const Color(0xFFEFF6FF),
            border: const Color(0xFFBFDBFE),
            titleColor: AppColors.darkNavy,
            subColor: AppColors.textMuted,
            onTap: () => _soon('La auditoría de transacciones'),
          ),
          _quickTile(
            leading: const Text(
              'WA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            leadingBg: const Color(0xFF16A34A),
            title: 'Simular bot de cobranza',
            subtitle: 'WhatsApp automatizado',
            bg: const Color(0xFFF0FDF4),
            border: const Color(0xFFBBF7D0),
            titleColor: AppColors.darkNavy,
            subColor: const Color(0xFF15803D),
            onTap: () => _soon('El simulador del bot de cobranza'),
          ),
        ],
      ),
    );
  }

  Widget _quickTile({
    required Widget leading,
    required Color leadingBg,
    required String title,
    required String subtitle,
    required Color bg,
    required Color border,
    required Color titleColor,
    required Color subColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: leadingBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(child: leading),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: subColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tarjetas de indicadores (KPI)
  Widget _kpiCard({
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required String label,
    required Widget value,
    Widget? sub,
    Widget? topRight,
    bool accent = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (accent) Container(height: 3, color: AppColors.primaryBlue),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: iconFg, size: 20),
                      ),
                      if (topRight != null) topRight,
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  value,
                  if (sub != null) ...[const SizedBox(height: 10), sub],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill({required String text, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _bigValue(String main, {String? unit}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: main),
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppColors.darkNavy,
      ),
    );
  }

  Widget _kpiRecaudado() {
    final cur = _monthly.isNotEmpty ? _monthly.last.value : 0.0;
    final prev = _monthly.length > 1 ? _monthly[_monthly.length - 2].value : 0.0;

    Widget? badge;
    if (prev > 0) {
      final d = (cur - prev) / prev * 100;
      final up = d >= 0;
      badge = _pill(
        text: '${up ? '↑' : ''} ${_pct(d.abs())}%',
        bg: up ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        fg: up ? const Color(0xFF166534) : const Color(0xFFB91C1C),
      );
    }

    final bs = _tasa != null
        ? 'Bs. ${_money(cur * _tasa!)} Tasa BCV oficial'
        : 'Sin tasa BCV registrada';

    return _kpiCard(
      accent: true,
      icon: Icons.account_balance_wallet_outlined,
      iconBg: const Color(0xFFEFF6FF),
      iconFg: AppColors.primaryBlue,
      label: 'Recaudado total mensual',
      value: _bigValue('\$${_money(cur)}', unit: 'USD'),
      sub: Text(bs, style: const TextStyle(fontSize: 11, color: _green)),
      topRight: badge,
    );
  }

  List<_PendingItem> get _filteredPending {
    switch (_agingFilter) {
      case 1:
        return _pending.where((p) => p.daysOverdue <= 0).toList();
      case 2:
        return _pending
            .where((p) => p.daysOverdue >= 1 && p.daysOverdue <= 30)
            .toList();
      case 3:
        return _pending.where((p) => p.daysOverdue > 30).toList();
      default:
        return _pending;
    }
  }

  Widget _kpiPorCobrar() {
    final items = _filteredPending;
    final amount = items.fold<double>(0, (a, p) => a + p.saldo);
    final accounts = items.map((p) => p.studentId).toSet().length;
    final overdueAmount = _pending
        .where((p) => p.daysOverdue > 0)
        .fold<double>(0, (a, p) => a + p.saldo);
    final morosidad =
        _totalBilled > 0 ? overdueAmount / _totalBilled * 100 : 0.0;

    final filter = PopupMenuButton<int>(
      tooltip: 'Filtrar por antigüedad',
      initialValue: _agingFilter,
      onSelected: (v) => setState(() => _agingFilter = v),
      itemBuilder: (context) => [
        for (var i = 0; i < _agingLabels.length; i++)
          PopupMenuItem(value: i, child: Text(_agingLabels[i])),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _agingLabels[_agingFilter],
              style: const TextStyle(fontSize: 11, color: AppColors.darkNavy),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );

    return _kpiCard(
      icon: Icons.schedule,
      iconBg: const Color(0xFFFEF3C7),
      iconFg: _amber,
      label: 'Cuentas por cobrar',
      value: _bigValue('\$${_money(amount)}', unit: 'USD'),
      sub: Text(
        '${_pct(morosidad)}% de morosidad • $accounts ${accounts == 1 ? 'cuenta' : 'cuentas'}',
        style: const TextStyle(fontSize: 11, color: _red),
      ),
      topRight: filter,
    );
  }

  Widget _kpiComprobantes() {
    return _kpiCard(
      icon: Icons.receipt_long_outlined,
      iconBg: const Color(0xFFFEE2E2),
      iconFg: _red,
      label: 'Comprobantes pendientes',
      value: _bigValue('$_pendingReceipts', unit: 'por conciliar'),
      sub: InkWell(
        onTap: () => setState(() => _navIndex = 3),
        child: Text(
          _receiptsLastHour == 0
              ? 'Ninguno recibido en la última hora →'
              : '$_receiptsLastHour ${_receiptsLastHour == 1 ? 'recibido' : 'recibidos'} en la última hora →',
          style: const TextStyle(fontSize: 11, color: AppColors.primaryBlue),
        ),
      ),
      topRight: _pendingReceipts > 0
          ? Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: _red,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$_pendingReceipts',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  Widget _kpiEstudiantes() {
    final pct = _studentsTotal > 0 ? _solventes / _studentsTotal * 100 : 0.0;
    final conSaldo = _pendientes + _insolventes;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.people_outline, color: _green, size: 20),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total estudiantes',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$_studentsTotal',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkNavy,
                        ),
                      ),
                    ],
                  ),
                ),
                _donut(
                  values: [
                    _solventes.toDouble(),
                    (_studentsTotal - _solventes).toDouble(),
                  ],
                  colors: const [_green, Color(0xFFFEE2E2)],
                  size: 62,
                  stroke: 9,
                  center: Text(
                    '${pct.round()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$_solventes ${_solventes == 1 ? 'solvente' : 'solventes'} • $conSaldo con saldo',
              style: const TextStyle(fontSize: 11, color: _green),
            ),
          ],
        ),
      ),
    );
  }

  // Gráficos
  Widget _buildChartsRow() {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildMonthlyChartCard()),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: _buildSolvencyCard()),
            ],
          );
        }
        return Column(
          children: [
            _buildMonthlyChartCard(),
            const SizedBox(height: 20),
            _buildSolvencyCard(),
          ],
        );
      },
    );
  }

  Widget _buildMonthlyChartCard() {
    final rangeMenu = PopupMenuButton<int>(
      tooltip: 'Rango de meses',
      initialValue: _rangeMonths,
      onSelected: (v) => setState(() {
        _rangeMonths = v;
        _selectedBar = null;
      }),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 3, child: Text('Últimos 3 meses')),
        PopupMenuItem(value: 6, child: Text('Últimos 6 meses')),
        PopupMenuItem(value: 12, child: Text('Últimos 12 meses')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Últimos $_rangeMonths meses',
              style: const TextStyle(fontSize: 11, color: AppColors.darkNavy),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );

    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recaudación mensual',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pagos aprobados, en USD',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              rangeMenu,
            ],
          ),
          const SizedBox(height: 20),
          _buildBarChart(),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    final data = _monthly.sublist(_monthly.length - _rangeMonths);
    final maxV = _niceMax(data.fold<double>(0, (a, e) => math.max(a, e.value)));
    final selected = _selectedBar ?? (data.length - 1);
    const axisH = 22.0;

    return SizedBox(
      height: 230,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 4; i >= 0; i--)
                        Text(
                          _compact(maxV * i / 4),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: axisH),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < 5; i++)
                            Container(
                              height: 1,
                              color: const Color(0xFFE2E8F0),
                            ),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < data.length; i++)
                            Expanded(
                              child: _bar(
                                i,
                                data[i].value,
                                maxV,
                                i == selected,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: axisH,
                  child: Row(
                    children: [
                      for (final m in data)
                        Expanded(
                          child: Center(
                            child: Text(
                              m.label,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
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
    );
  }

  Widget _bar(int index, double value, double maxV, bool selected) {
    final f = maxV > 0 ? (value / maxV).clamp(0.0, 1.0).toDouble() : 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedBar = index),
      child: LayoutBuilder(
        builder: (context, c) {
          final h = math.max(c.maxHeight * f, value > 0 ? 3.0 : 0.0);
          final w = (c.maxWidth * 0.42).clamp(14.0, 36.0).toDouble();

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryBlue
                      : const Color(0xFFBFDBFE),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              if (selected)
                Positioned(
                  bottom: h + 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '\$${_compact(value)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSolvencyCard() {
    Widget legend(Color color, String label, int count) {
      final pct = _studentsTotal > 0 ? count / _studentsTotal * 100 : 0.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.darkNavy),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.darkNavy,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 44,
              child: Text(
                '${_pct(pct)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado de solvencias',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Matrícula actual',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: _donut(
              values: [
                _solventes.toDouble(),
                _pendientes.toDouble(),
                _insolventes.toDouble(),
              ],
              colors: const [_green, _amber, _red],
              size: 170,
              stroke: 20,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_studentsTotal',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const Text(
                    'estudiantes',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 8),
          legend(_green, 'Solventes', _solventes),
          legend(_amber, 'Pendientes', _pendientes),
          legend(_red, 'Insolventes', _insolventes),
        ],
      ),
    );
  }

  Widget _donut({
    required List<double> values,
    required List<Color> colors,
    required double size,
    required double stroke,
    required Widget center,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(values, colors, stroke),
          ),
          center,
        ],
      ),
    );
  }

  //
  // Pagos recientes
  //
  Widget _buildRecentPayments() {
    const headerStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.bold,
      color: AppColors.textMuted,
      letterSpacing: 0.5,
    );

    Widget header() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border.symmetric(
              horizontal: BorderSide(color: AppColors.cardBorder),
            ),
          ),
          child: const Row(
            children: [
              Expanded(flex: 3, child: Text('REPRESENTANTE', style: headerStyle)),
              Expanded(flex: 3, child: Text('ESTUDIANTE', style: headerStyle)),
              Expanded(flex: 3, child: Text('CONCEPTO', style: headerStyle)),
              Expanded(flex: 2, child: Text('MONTO', style: headerStyle)),
              Expanded(flex: 2, child: Text('ESTADO', style: headerStyle)),
              Expanded(flex: 2, child: Text('FECHA', style: headerStyle)),
            ],
          ),
        );

    return _card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pagos recientes',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Últimas operaciones registradas',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _soon('El historial completo de pagos'),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver todos',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: AppColors.primaryBlue,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final width = math.max(c.maxWidth, 760.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      header(),
                      if (_recent.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(
                            child: Text(
                              'Aún no hay pagos registrados. Cuando un representante reporte uno, aparecerá aquí.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        for (var i = 0; i < _recent.length; i++) ...[
                          _payRow(_recent[i]),
                          if (i < _recent.length - 1)
                            const Divider(
                              height: 1,
                              color: AppColors.cardBorder,
                            ),
                        ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _payRow(_PagoRow p) {
    final amount = p.currency == 'USD'
        ? '\$${_money(p.amount)}'
        : 'Bs. ${_money(p.amount)}';
    const cell = TextStyle(fontSize: 12, color: AppColors.darkNavy);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFEFF6FF),
                  child: Text(
                    _initials(p.representative),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    p.representative,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              p.student,
              style: cell,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              p.concept,
              style: cell,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.darkNavy,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusChip(p.status),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _when(p.date),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    switch (status) {
      case 'aprobado':
        return _pill(
          text: 'Verificado',
          bg: const Color(0xFFDCFCE7),
          fg: const Color(0xFF166534),
        );
      case 'rechazado':
        return _pill(
          text: 'Rechazado',
          bg: const Color(0xFFFEE2E2),
          fg: const Color(0xFFB91C1C),
        );
      default:
        return _pill(
          text: 'En revisión',
          bg: const Color(0xFFFEF3C7),
          fg: const Color(0xFFB45309),
        );
    }
  }

  Widget _buildFooterNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: AppColors.primaryBlue, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trazabilidad completa',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                  ),
                ),
                Text(
                  'Cada aprobación, rechazo o cambio queda registrado en la auditoría inalterable del sistema.',
                  style: TextStyle(fontSize: 10, color: AppColors.darkNavy),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  //
  // Componentes de layout reutilizables
  //
  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }

  Widget _grid({
    required List<Widget> items,
    required int wideCols,
    required int narrowCols,
    double gap = 16,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 800 ? wideCols : narrowCols;
        final rows = <Widget>[];

        for (var i = 0; i < items.length; i += cols) {
          final slice = items.sublist(i, math.min(i + cols, items.length));
          final cells = <Widget>[];

          for (var j = 0; j < cols; j++) {
            if (j > 0) cells.add(SizedBox(width: gap));
            cells.add(
              Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
            );
          }

          if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          );
        }

        return Column(children: rows);
      },
    );
  }
}

//
// Gráfico de anillo (sin dependencias externas)
//
class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double stroke;

  _DonutPainter(this.values, this.colors, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final total = values.fold<double>(0, (a, b) => a + b);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFF1F5F9);

    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, base);
      return;
    }

    final visible = values.where((v) => v > 0).length;
    final gap = visible > 1 ? 0.04 : 0.0;

    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = colors[i];

      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.001),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors || old.stroke != stroke;
}