import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/bcv_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';
import '../../../landing/presentation/screens/home_screen.dart';
import '../../data/account_status_service.dart';
import '../widgets/edit_profile_dialog.dart';
import '../widgets/report_payment_dialog.dart';
import '../widgets/representative_payments_section.dart';
import '../widgets/representative_calendar_section.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/widgets/dashboard_shell.dart';
import '../../../../core/widgets/skeleton_loader.dart';

class RepresentativeDashboardScreen extends StatefulWidget {
  const RepresentativeDashboardScreen({super.key});

  @override
  State<RepresentativeDashboardScreen> createState() =>
      _RepresentativeDashboardScreenState();
}

class _RepresentativeDashboardScreenState
    extends State<RepresentativeDashboardScreen> {
  final User? currentUser = supabase.auth.currentUser;

  // Servicios para Tasa BCV y Estado de Cuenta
  final BcvService _bcvService = BcvService();
  final AccountStatusService _accountStatusService = AccountStatusService();

  bool _isLoading = false;
  bool _isLoadingProfile = true;

  // Datos dinámicos del representante autenticado
  String _repDbId = '';
  String _fullName = '';
  String _cedula = '';
  String _email = '';
  String _phone = '';
  String _address = '';
  String _familyName = '';
  String _initials = '';

  // Lista dinámica de estudiantes asociados en Supabase
  List<Map<String, dynamic>> _students = [];
  int _selectedStudentIndex = 0; // -1 representa vista consolidada familiar
  int _selectedNavIndex = 0;
  String? _paymentNotificationId;
  String? _paymentNotificationReference;
  int _paymentNotificationVersion = 0;

  // Variables financieras dinámicas (HU7)
  double _montoUsd = 0.0;
  double _equivalenteVes = 0.0;
  String _tasaBcvStr = '0,00';
  String _tasaFechaLabel = 'Sincronizando Tasa BCV...';

  // Estado de cuenta familiar: desglose por cuota, crédito y solvencia global.
  EstadoCuenta? _estadoCuenta;
  bool _estadoCuentaError = false;
  double _tasaBcv = 0.0;
  bool _selectionInitialized = false;

  // Anclas para las acciones rápidas del dashboard.
  final GlobalKey _accountSectionKey = GlobalKey();
  final GlobalKey _documentsSectionKey = GlobalKey();

  /// Solvente SOLO si la consulta funcionó y el saldo GLOBAL de la familia es 0.
  bool get _isSolventeFamiliar =>
      _estadoCuenta != null && _estadoCuenta!.esSolvente;
  double get _deudaFamiliarUsd => _estadoCuenta?.totalPendienteUsd ?? 0.0;

  @override
  void initState() {
    super.initState();
    fetchUserProfileAndStudents();
  }

  // --- CONSULTA EN VIVO DEL PERFIL DEL REPRESENTANTE ---
  // silent: true se usa al refrescar (pull-to-refresh) para no reemplazar la
  // pantalla por el spinner de carga.
  Future<void> fetchUserProfileAndStudents({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingProfile = true);
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final userEmail = user.email ?? '';
        final userCedula = user.userMetadata?['cedula']?.toString() ?? '';
        final userFullName =
            user.userMetadata?['nombre_completo']?.toString() ?? '';

        Map<String, dynamic>? data;

        // 1. Buscar en 'representantes' por perfil_id, email o cédula
        try {
          data = await supabase
              .from('representantes')
              .select()
              .eq('perfil_id', user.id)
              .maybeSingle();
        } catch (_) {}

        if (data == null && userEmail.isNotEmpty) {
          try {
            data = await supabase
                .from('representantes')
                .select()
                .eq('email', userEmail)
                .maybeSingle();
          } catch (_) {}
        }

        if (data == null && userCedula.isNotEmpty) {
          try {
            data = await supabase
                .from('representantes')
                .select()
                .eq('cedula', userCedula)
                .maybeSingle();
          } catch (_) {}
        }

        if (data != null) {
          _repDbId = data['id']?.toString() ?? '';
          final nombres = data['nombres']?.toString() ?? '';
          final apellidos = data['apellidos']?.toString() ?? '';
          final computedName = '$nombres $apellidos'.trim();

          final fetchedName = computedName.isNotEmpty
              ? computedName
              : (userFullName.isNotEmpty
                    ? userFullName
                    : userEmail.split('@')[0]);

          final fetchedCedula =
              (data['cedula'] != null && data['cedula'].toString().isNotEmpty)
              ? data['cedula'].toString()
              : (userCedula.isNotEmpty ? userCedula : 'Sin cédula');

          final fetchedEmail =
              (data['email'] != null && data['email'].toString().isNotEmpty)
              ? data['email'].toString()
              : userEmail;

          final fetchedPhone = data['telefono_whatsapp']?.toString() ?? '';
          final fetchedAddress = data['direccion']?.toString() ?? '';
          final fetchedFamily =
              (data['familia'] != null && data['familia'].toString().isNotEmpty)
              ? data['familia'].toString()
              : 'Familia ${_getLastName(fetchedName)}';

          _fullName = fetchedName;
          _cedula = fetchedCedula;
          _email = fetchedEmail;
          _phone = fetchedPhone;
          _address = fetchedAddress;
          _familyName = fetchedFamily;
          _initials = _getInitials(fetchedName);

          // 2. Cargar colegio y estudiantes vinculados (en paralelo)
          final schoolFuture = _loadSchoolName(data['colegio_id']?.toString());
          if (_repDbId.isNotEmpty) {
            await fetchAssociatedStudents(_repDbId);
          }
          await schoolFuture;
        } else {
          // Fallback para usuario sin perfil creado aún
          final fallbackName = userFullName.isNotEmpty
              ? userFullName
              : (userEmail.isNotEmpty ? userEmail.split('@')[0] : 'Usuario');

          _fullName = fallbackName;
          _cedula = userCedula.isNotEmpty ? userCedula : 'Sin cédula';
          _email = userEmail;
          _familyName = 'Familia ${_getLastName(fallbackName)}';
          _initials = _getInitials(fallbackName);
        }
      }
    } catch (e) {
      debugPrint('Error al obtener datos del representante: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  // --- CONSULTAR ESTUDIANTES VINCULADOS ---
  Future<void> fetchAssociatedStudents(String representanteId) async {
    try {
      final relResponse = await supabase
          .from('representante_estudiante')
          .select('estudiante_id')
          .eq('representante_id', representanteId);

      final List<dynamic> relList = relResponse as List<dynamic>;
      final List<String> studentIds = relList
          .map((item) => item['estudiante_id']?.toString())
          .whereType<String>()
          .toList();

      if (studentIds.isNotEmpty) {
        final studentsResponse = await supabase
            .from('estudiantes')
            .select()
            .filter('id', 'in', studentIds);

        final loadedStudents = List<Map<String, dynamic>>.from(
          studentsResponse,
        );

        if (mounted) {
          setState(() {
            _students = loadedStudents;
            if (!_selectionInitialized) {
              // Con más de un hijo se abre la vista consolidada (total global).
              _selectedStudentIndex = _students.length > 1 ? -1 : 0;
              _selectionInitialized = true;
            } else if (_selectedStudentIndex >= _students.length ||
                (_students.length == 1 && _selectedStudentIndex == -1)) {
              _selectedStudentIndex = 0;
            }
          });
          // Recalcular finanzas con la Tasa BCV y saldos reales (HU7)
          await _updateFinancialSummary();
        }
        return;
      }
    } catch (e) {
      debugPrint('Error al consultar estudiantes asociados: $e');
    }

    if (mounted) {
      setState(() {
        _students = [];
        _selectedStudentIndex = 0;
      });
      await _updateFinancialSummary();
    }
  }

  // --- NOMBRE DEL COLEGIO DEL REPRESENTANTE ---
  Future<void> _loadSchoolName(String? colegioId) async {
    if (colegioId == null || colegioId.isEmpty) return;
    try {
      final row = await supabase
          .from('colegios')
          .select()
          .eq('id', colegioId)
          .maybeSingle();
      final nombre = row?['nombre']?.toString() ?? '';
      // Soporta nombres habituales del campo sin exigir una migración de BD.
      // Si no hay uno configurado, se presenta el ciclo calendario actual.
      String? periodo;
      for (final value in [
        row?['periodo_escolar'],
        row?['periodo_actual'],
        row?['anio_escolar'],
        row?['ano_escolar'],
      ]) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          periodo = text;
          break;
        }
      }
      if (mounted) {
        setState(() {
          if (nombre.isNotEmpty) _schoolName = nombre;
          _configuredSchoolPeriod = periodo;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar el colegio del representante: $e');
    }
  }

  // --- CÁLCULO DINÁMICO DE SALDOS Y TASA BCV (HU7) ---
  Future<void> _updateFinancialSummary() async {
    // Estado de cuenta de TODA la familia: se lanza ya y corre en paralelo
    // con la consulta de la Tasa BCV. Si falla NO se asume solvencia.
    final Future<EstadoCuenta?> estadoFuture = _accountStatusService
        .getEstadoCuenta(representanteId: _repDbId)
        .then<EstadoCuenta?>((v) => v)
        .catchError((Object e) {
          debugPrint('Error consultando el estado de cuenta: $e');
          return null;
        });

    // 1. Tasa BCV (oficial o caché). Si falla se conserva la última conocida.
    double rate = _tasaBcv;
    String rateStr = _tasaBcvStr;
    String rateLabel = _tasaFechaLabel;
    try {
      final bcvData = await _bcvService.getLatestBcvRate();
      if (bcvData.rate > 0) {
        rate = bcvData.rate;
        rateStr = bcvData.rate.toStringAsFixed(2).replaceAll('.', ',');
        rateLabel = bcvData.dateFormatted;
      }
    } catch (e) {
      debugPrint('Error obteniendo tasa BCV: $e');
    }

    // 2. Estado de cuenta de TODA la familia (una fila por cuota).
    //    Si falla NO se asume solvencia: se muestra un estado de error.
    final EstadoCuenta? estado = await estadoFuture;

    if (!mounted) return;
    setState(() {
      _estadoCuenta = estado;
      _estadoCuentaError = estado == null;

      // Vista individual: solo ese hijo. Consolidado (-1): total global.
      final String? selectedId =
          (_selectedStudentIndex >= 0 &&
              _selectedStudentIndex < _students.length)
          ? _students[_selectedStudentIndex]['id'].toString()
          : null;
      _montoUsd = estado?.pendienteDe(estudianteId: selectedId) ?? 0.0;

      _tasaBcv = rate;
      _equivalenteVes = _montoUsd * rate;
      _tasaBcvStr = rateStr;
      _tasaFechaLabel = rateLabel;
    });
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'U';
  }

  String _getLastName(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return parts[1];
    } else if (parts.isNotEmpty) {
      return parts[0];
    }
    return '';
  }

  Future<void> _handleLogout() async {
    setState(() => _isLoading = true);
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  void _showEditProfileModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return EditProfileDialog(
          fullName: _fullName,
          cedula: _cedula,
          phone: _phone,
          address: _address,
          email: _email,
          onSaveSuccess: () => fetchUserProfileAndStudents(),
        );
      },
    );
  }

  Future<void> _showReportPaymentModal(BuildContext context) async {
    final estado = _estadoCuenta;
    if (estado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos verificar tu saldo. Intenta nuevamente.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      _updateFinancialSummary();
      return;
    }

    // Monto sugerido: deuda global menos lo ya reportado y en revisión
    // (evita que la familia reporte dos veces el mismo pago). Es editable.
    final double sugerido = (estado.totalPendienteUsd - estado.enRevisionUsd)
        .clamp(0.0, double.infinity)
        .toDouble();
    if (sugerido <= kToleranciaSaldoUsd) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No tienes pagos por reportar o ya tienes un pago en revisión.',
            ),
          ),
        );
      }
      return;
    }

    final String titular = _students.length > 1
        ? (_familyName.isNotEmpty
              ? (RegExp(
                      r'^familia\b',
                      caseSensitive: false,
                    ).hasMatch(_familyName)
                    ? _familyName
                    : 'Familia $_familyName')
              : 'Mi familia')
        : (_students.isNotEmpty
              ? '${_students.first['nombres'] ?? ''} ${_students.first['apellidos'] ?? ''}'
                    .trim()
              : 'Estudiante');

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return ReportPaymentDialog(
          studentName: titular,
          monthPeriod: 'Pago unificado',
          amountUsd: sugerido,
          tasaBcv: _tasaBcv,
        );
      },
    );

    if (mounted) await _updateFinancialSummary();
  }

  // --- NAVEGACIÓN (misma estructura que el panel del administrador) ---
  static const _navItems = <DashboardNavItem>[
    DashboardNavItem(Icons.home_outlined, Icons.home_rounded, 'Inicio'),
    DashboardNavItem(
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
      'Pagos',
    ),
    DashboardNavItem(
      Icons.calendar_month_outlined,
      Icons.calendar_month_rounded,
      'Calendario',
    ),
    DashboardNavItem(
      Icons.description_outlined,
      Icons.description_rounded,
      'Documentos',
    ),
  ];

  // Nombre del colegio del representante (representantes.colegio_id -> colegios.nombre)
  String _schoolName = '';
  String? _configuredSchoolPeriod;

  /// El colegio tiene prioridad; si no registra el período, se calcula
  /// el ciclo septiembre-agosto a partir de la fecha local del dispositivo.
  String get _currentSchoolPeriod {
    final fromSchool = _configuredSchoolPeriod?.trim() ?? '';
    if (fromSchool.isNotEmpty) {
      return RegExp(r'^per[ií]odo\b', caseSensitive: false).hasMatch(fromSchool)
          ? fromSchool
          : 'Período $fromSchool';
    }
    final today = DateTime.now();
    final firstYear = today.month >= 9 ? today.year : today.year - 1;
    return 'Período $firstYear–${firstYear + 1}';
  }

  // La campana ya marca la notificación como leída. Aquí abrimos la pestaña
  // y enviamos el identificador del pago al historial para expandirlo.
  void _openPaymentNotification(AppNotification notification) {
    if (!{
      'pago_reportado',
      'pago_aprobado',
      'pago_rechazado',
    }.contains(notification.tipo))
      return;

    final data = notification.datos;
    String? identifier;
    for (final key in ['pago_id', 'id_pago', 'payment_id']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        identifier = value;
        break;
      }
    }
    final nested = data['pago'];
    if (identifier == null && nested is Map) {
      final candidate = nested['id']?.toString().trim();
      if (candidate != null && candidate.isNotEmpty) identifier = candidate;
    }
    String? reference;
    if (identifier == null) {
      for (final key in [
        'referencia',
        'referencia_pago',
        'referencia_bancaria',
        'numero_referencia',
      ]) {
        final value = data[key]?.toString().trim();
        if (value != null && value.isNotEmpty) {
          reference = value;
          break;
        }
      }
    }
    setState(() {
      _selectedNavIndex = 1;
      _paymentNotificationId = identifier;
      _paymentNotificationReference = reference;
      _paymentNotificationVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      navItems: _navItems,
      selectedIndex: _selectedNavIndex,
      onNavSelected: (i) => setState(() {
        _selectedNavIndex = i;
        _paymentNotificationId = null;
        _paymentNotificationReference = null;
        _paymentNotificationVersion = 0;
      }),
      schoolName: _schoolName,
      userName: _fullName.isEmpty ? 'Representante' : _fullName,
      userInitials: _initials.isEmpty ? 'U' : _initials,
      userRole: 'Representante',
      onLogout: _handleLogout,
      onEditProfile: () => _showEditProfileModal(context),
      searchHint: 'Buscar una sección del menú...',
      onSupportTap: _showSupportDialog,
      onNotificationTap: _openPaymentNotification,
      headerActions: const [],
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final width = MediaQuery.sizeOf(context).width;
    // Espaciado adaptable compartido con el dashboard del administrador.
    // En escritorio deja más aire a ambos lados sin alejar demasiado el saludo.
    final contentPadding = Breakpoints.pageInsets(width);

    if (_isLoading || _isLoadingProfile) {
      return RepresentativeDashboardSkeleton(padding: contentPadding);
    }

    if (_selectedNavIndex == 1) {
      return RepresentativePaymentsSection(
        representativeId: _repDbId,
        focusPaymentId: _paymentNotificationId,
        focusReference: _paymentNotificationReference,
        notificationSequence: _paymentNotificationVersion,
        onReportPayment: () => _showReportPaymentModal(context),
      );
    }

    if (_selectedNavIndex == 2) {
      return RepresentativeCalendarSection(
        representativeId: _repDbId,
        students: _students,
        onOpenPayment: (paymentId) => setState(() {
          _selectedNavIndex = 1;
          _paymentNotificationId = paymentId;
          _paymentNotificationReference = null;
          _paymentNotificationVersion++;
        }),
      );
    }

    if (_selectedNavIndex != 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _navItems[_selectedNavIndex].icon,
                size: 44,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(height: 12),
              Text(
                '${_navItems[_selectedNavIndex].title} estará disponible próximamente.',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _selectedNavIndex = 0),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: () => fetchUserProfileAndStudents(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentPadding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1250),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWelcomeHero(),
                const SizedBox(height: _sectionGap),
                _buildHeroStatusRow(),
                const SizedBox(height: _sectionGap),
                _buildQuickActions(),
                const SizedBox(height: _sectionGap),
                _buildPaymentAndSecurityRow(),
                const SizedBox(height: _sectionGap),
                _buildAccountAndSchoolRow(),
                const SizedBox(height: _sectionGap),
                Container(
                  key: _documentsSectionKey,
                  child: _buildDigitalDocumentsSection(),
                ),
                const SizedBox(height: _sectionGap),
                _buildActionButtons(),
                const SizedBox(height: _sectionGap),
                _buildFooterSecurityNotice(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _weekdays = <String>[
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];
  static const _months = <String>[
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

  String _longDate(DateTime date) =>
      '${_weekdays[date.weekday - 1]}, ${date.day} de ${_months[date.month - 1]} de ${date.year}';

  void _scrollTo(GlobalKey section) {
    final target = section.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOut,
        alignment: 0.06,
      );
    }
  }

  void _chooseStudent(int index) {
    if (index == _selectedStudentIndex) return;
    setState(() {
      _selectedStudentIndex = index;
      final String? id = (index >= 0 && index < _students.length)
          ? _students[index]['id'].toString()
          : null;
      _montoUsd = _estadoCuenta?.pendienteDe(estudianteId: id) ?? 0;
      _equivalenteVes = _montoUsd * _tasaBcv;
    });
    if (_estadoCuenta == null) _updateFinancialSummary();
  }

  // Conserva la estructura de las tarjetas existentes sin aplicar fondos
  // decorativos. Iconos, estados y acciones no se modifican.
  Widget _cornerWaves(Widget content, {Color color = AppColors.primaryBlue}) =>
      content;

  // Ondas en la esquina superior derecha para Estudiante, Solvencia y
  // Próximo pago. En hover crecen solo un 13 %, sin mover el contenido.
  // Los accesos rápidos utilizan un diseño independiente, sin ondas.
  Widget _featureCornerCurves(Widget child, {required Color color}) {
    return HoverBuilder(
      builder: (context, hovered) {
        final reduceMotion = MediaQuery.of(context).disableAnimations;
        return ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: hovered ? 1.13 : 1.0),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 330),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, _) => CustomPaint(
                      painter: _FeatureCornerCurvesPainter(color, scale: scale),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }

  // Hover uniforme en tarjetas principales: solo cambia elevación/sombra y
  // contorno; no altera el tamaño, el scroll ni las acciones de los controles.
  Widget _dashboardHover(
    Widget child, {
    double radius = 16,
    Color? hoverColor,
    bool outline = true,
  }) {
    return HoverBuilder(
      builder: (context, hovered) {
        final reducedMotion = MediaQuery.of(context).disableAnimations;
        return AnimatedContainer(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 155),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: hovered
                ? [
                    BoxShadow(
                      color: (hoverColor ?? AppColors.primaryBlue).withValues(
                        alpha: 0.065,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: hovered && outline
                  ? (hoverColor ?? AppColors.primaryBlue).withValues(
                      alpha: 0.30,
                    )
                  : Colors.transparent,
            ),
          ),
          child: child,
        );
      },
    );
  }

  BoxDecoration _whiteCard({Color border = AppColors.cardBorder, Color? bg}) =>
      BoxDecoration(
        color: bg ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4785).withValues(alpha: 0.035),
            blurRadius: 22,
            offset: const Offset(0, 5),
          ),
        ],
      );

  Widget _buildWelcomeHero() {
    final date = DateTime.now();
    final first = _fullName.trim().isEmpty
        ? 'bienvenido'
        : _fullName.trim().split(RegExp(r'\s+')).first;
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 720;
        final greeting = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¡Hola, $first!',
              style: TextStyle(
                fontSize: narrow ? 26 : 31,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: AppColors.darkNavy,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Aquí tienes el resumen de la información de tu familia.',
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ],
        );
        final dateAndPeriod = SizedBox(
          width: narrow ? c.maxWidth : 290,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    size: 17,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      _longDate(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.school_outlined,
                    size: 17,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      _currentSchoolPeriod,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        if (narrow)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [greeting, const SizedBox(height: 14), dateAndPeriod],
          );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: greeting),
            const SizedBox(width: 20),
            dateAndPeriod,
          ],
        );
      },
    );
  }

  // --- Simetría del dashboard -------------------------------------------
  // Todas las filas de dos tarjetas comparten la misma división (2 : 1), el
  // mismo espacio entre columnas y la misma altura; todas las secciones
  // verticales comparten el mismo espacio. Para dos columnas iguales (1 : 1)
  // basta con poner _mainFlex = 1.
  static const double _sectionGap = 24; // entre secciones (vertical)
  static const double _colGap = 20; // entre tarjetas (horizontal)
  static const double _stackGap =
      20; // entre tarjetas apiladas (pantalla angosta)
  static const int _mainFlex = 2;
  static const int _sideFlex = 1;

  double _mainColumnWidth(double rowWidth) =>
      (rowWidth - _colGap) * _mainFlex / (_mainFlex + _sideFlex);

  /// Dos tarjetas lado a lado con EXACTAMENTE la misma altura.
  /// (IntrinsicHeight: ninguna tarjeta de estas filas puede usar
  /// LayoutBuilder en su interior.)
  Widget _twoColumnRow({required Widget main, required Widget side}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: _mainFlex, child: main),
          const SizedBox(width: _colGap),
          Expanded(flex: _sideFlex, child: side),
        ],
      ),
    );
  }

  Widget _buildHeroStatusRow() {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 800) {
          return Column(
            children: [
              _buildStudentSelectorCard(),
              const SizedBox(height: _stackGap),
              _buildSolvencyStatusCard(),
            ],
          );
        }
        return _twoColumnRow(
          main: _buildStudentSelectorCard(),
          side: _buildSolvencyStatusCard(),
        );
      },
    );
  }

  /// Devuelve el primer campo informado en la fila real de Supabase.
  /// No se utiliza la cédula del representante como si fuese del estudiante.
  String _studentField(Map<String, dynamic>? student, List<String> keys) {
    if (student == null) return '';
    for (final key in keys) {
      final value = student[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  String _studentGrade(Map<String, dynamic>? student) {
    final grade = _studentField(student, const [
      'grado_seccion',
      'grado',
      'nivel_grado',
    ]);
    return grade.isEmpty ? 'Grado no especificado' : grade;
  }

  String _studentCedula(Map<String, dynamic>? student) {
    return _studentField(student, const [
      'cedula',
      'cedula_estudiante',
      'documento_identidad',
      'numero_documento',
      'numero_cedula',
      'nro_cedula',
      'ci',
    ]);
  }

  String _studentDetails(Map<String, dynamic> student) {
    final cedula = _studentCedula(student);
    return '${_studentGrade(student)}  •  C.I. ${cedula.isEmpty ? 'No registrada' : cedula}';
  }

  String _studentFullName(Map<String, dynamic> st) =>
      '${st['nombres'] ?? ''} ${st['apellidos'] ?? ''}'.trim();

  /// Avatar circular del selector: logotipo de familia o iniciales.
  Widget _selectorAvatar({
    required bool family,
    required String initials,
    double size = 66,
  }) {
    const bg1 = Color(0xFFEAF2FF);
    const bg2 = Color(0xFFD3E3FF);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg1, bg2],
        ),
        border: Border.all(color: Colors.white, width: size >= 56 ? 2.5 : 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.18),
            blurRadius: size >= 56 ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: family
          ? _FamilyMark(size: size * 0.62, background: const Color(0xFFDDE9FF))
          : Text(
              initials,
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontSize: size >= 56 ? 20 : 13,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  PopupMenuItem<int> _studentMenuItem({
    required int value,
    required Widget leading,
    required String title,
    required String subtitle,
    bool isLast = false,
  }) {
    final selected = value == _selectedStudentIndex;
    return PopupMenuItem<int>(
      value: value,
      padding: EdgeInsets.zero,
      height: 56, // alto mínimo; la fila define su propio alto real
      child: HoverBuilder(
        builder: (context, hovered) => AnimatedContainer(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 125),
          width: double.infinity,
          decoration: BoxDecoration(
            color: hovered
                ? AppColors.primaryLight
                : (selected
                      ? AppColors.primaryLight.withValues(alpha: 0.65)
                      : Colors.transparent),
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primaryBlue,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentSelectorCard() {
    final hasStudents = _students.isNotEmpty;
    final consolidated = _selectedStudentIndex == -1 && _students.length > 1;
    final selected =
        hasStudents &&
            _selectedStudentIndex >= 0 &&
            _selectedStudentIndex < _students.length
        ? _students[_selectedStudentIndex]
        : null;
    final name = consolidated
        ? 'Toda mi familia'
        : (selected == null
              ? 'Sin estudiantes vinculados'
              : _studentFullName(selected));
    final details = consolidated
        ? '${_students.length} estudiantes vinculados'
        : selected != null
        ? _studentDetails(selected)
        : 'Sin grado ni cédula registrados';
    final canChoose = _students.length > 1;
    final initials = _getInitials(name);
    final countLabel = consolidated
        ? '${_students.length}'
        : (selected == null ? '0' : '1');

    final inner = Container(
      constraints: const BoxConstraints(minHeight: 122),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          _selectorAvatar(family: consolidated, initials: initials),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'ESTUDIANTE',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.primaryBlue,
                      letterSpacing: 0.45,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.darkNavy,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: details,
                        child: Text(
                          details,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    if (consolidated) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.14,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Vista familiar',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.88),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  countLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
              if (canChoose) ...[
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    ),
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    final cardDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF214576).withValues(alpha: 0.025),
          blurRadius: 14,
          offset: const Offset(0, 3),
        ),
      ],
    );
    final decoratedInner = _featureCornerCurves(
      inner,
      color: AppColors.primaryBlue,
    );
    if (!canChoose) {
      return _dashboardHover(
        DecoratedBox(decoration: cardDecoration, child: decoratedInner),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: AppColors.backgroundLight,
        highlightColor: AppColors.primaryLight,
        splashColor: AppColors.primaryBlue.withValues(alpha: 0.08),
      ),
      child: Builder(
        builder: (ctx) => Semantics(
          button: true,
          label: 'Seleccionar estudiante',
          child: Tooltip(
            message: 'Seleccionar estudiante',
            child: _dashboardHover(
              DecoratedBox(
                decoration: cardDecoration,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openStudentMenu(ctx),
                    child: decoratedInner,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Abre el menú de estudiantes justo debajo de la tarjeta, con su mismo
  /// ancho. Se calcula a mano (sin LayoutBuilder) para que la tarjeta pueda
  /// igualar su altura con la de al lado.
  Future<void> _openStudentMenu(BuildContext ctx) async {
    final box = ctx.findRenderObject();
    final overlayBox = Overlay.of(ctx).context.findRenderObject();
    if (box is! RenderBox || overlayBox is! RenderBox || !box.hasSize) return;

    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy + box.size.height + 8,
      box.size.width,
      0,
    );

    final choice = await showMenu<int>(
      context: ctx,
      position: RelativeRect.fromRect(rect, Offset.zero & overlayBox.size),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0xFF1B4785).withValues(alpha: 0.22),
      clipBehavior: Clip.antiAlias,
      menuPadding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: box.size.width),
      // Mismo radio y borde neutro que el resto de las tarjetas.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      items: [
        // Etiqueta discreta, igual que el "ESTUDIANTE" de la tarjeta.
        PopupMenuItem<int>(
          enabled: false,
          padding: EdgeInsets.zero,
          height: 40,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE8EEF8))),
            ),
            child: const Text(
              'SELECCIONAR ESTUDIANTE',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        _studentMenuItem(
          value: -1,
          leading: _selectorAvatar(family: true, initials: '', size: 42),
          title: 'Toda mi familia',
          subtitle: '${_students.length} estudiantes vinculados',
        ),
        for (var i = 0; i < _students.length; i++)
          _studentMenuItem(
            value: i,
            isLast: i == _students.length - 1,
            leading: _selectorAvatar(
              family: false,
              initials: _getInitials(_studentFullName(_students[i])),
              size: 42,
            ),
            title: _studentFullName(_students[i]),
            subtitle: _studentDetails(_students[i]),
          ),
      ],
    );
    if (choice != null && mounted) _chooseStudent(choice);
  }

  Widget _buildSolvencyStatusCard() {
    final unknown = _estadoCuentaError || _estadoCuenta == null;
    final solvent = !unknown && _isSolventeFamiliar;
    final state = unknown
        ? AppColors.textMuted
        : solvent
        ? AppColors.successGreen
        : AppColors.warningAmber;
    final status = unknown
        ? 'Sin información'
        : solvent
        ? 'SOLVENTE'
        : 'PAGO PENDIENTE';
    final detail = unknown
        ? 'No fue posible verificar el saldo'
        : solvent
        ? 'Sin deudas pendientes'
        : 'Saldo familiar: ${_fmtUsd(_deudaFamiliarUsd)}';
    final outline = unknown
        ? const Color(0xFFD5DFEF)
        : solvent
        ? const Color(0xFFB8E4CC)
        : const Color(0xFFF1D5A7);
    return _dashboardHover(
      Semantics(
        liveRegion: true,
        label: 'Solvencia familiar: $status. $detail',
        child: Container(
          constraints: const BoxConstraints(minHeight: 114),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: outline),
            boxShadow: [
              BoxShadow(
                color: state.withValues(alpha: 0.025),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: _featureCornerCurves(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
              // El icono y el bloque de textos se centran como un solo grupo
              // dentro del área disponible, tanto horizontal como verticalmente.
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [state.withValues(alpha: 0.88), state],
                        ),
                      ),
                      child: Icon(
                        unknown
                            ? Icons.help_outline_rounded
                            : solvent
                            ? Icons.check_rounded
                            : Icons.schedule_rounded,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 17),
                    Flexible(
                      fit: FlexFit.loose,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Solvencia familiar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: state,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: state,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (unknown)
                      IconButton(
                        tooltip: 'Volver a consultar solvencia',
                        onPressed: _updateFinancialSummary,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            color: state,
          ),
        ),
      ),
      hoverColor: state,
    );
  }

  // Accesos rápidos: cuatro tarjetas con personalidad visual propia.
  // Mantienen las mismas rutas y acciones del dashboard; solo cambia el UI.
  Widget _buildQuickActions() {
    return ResponsiveGrid(
      wideCols: 4,
      mediumCols: 2,
      narrowCols: 1,
      wideBreak: 970,
      mediumBreak: 510,
      gap: _colGap,
      items: [
        _quickAction(
          Icons.credit_card_rounded,
          'Pagar mensualidad',
          'Reporta tu pago de forma segura',
          const Color(0xFF008B62), // verde: pagos
          const Color(0xFFE4F6ED),
          const Color(0xFFF2FBF7),
          () => _showReportPaymentModal(context),
        ),
        _quickAction(
          Icons.receipt_long_rounded,
          'Ver estado de cuenta',
          'Consulta tus cuotas y saldos',
          const Color(0xFF1663E9), // azul: estado de cuenta
          const Color(0xFFE3EDFF),
          const Color(0xFFF2F7FF),
          () => _scrollTo(_accountSectionKey),
        ),
        _quickAction(
          Icons.description_outlined,
          'Documentos',
          'Consulta tus trámites digitales',
          const Color(0xFFDE2626), // rojo: documentos
          const Color(0xFFFFE7E7),
          const Color(0xFFFFF6F6),
          () => _scrollTo(_documentsSectionKey),
        ),
        _quickAction(
          Icons.headset_mic_rounded,
          'Soporte',
          'Estamos aquí para ayudarte',
          const Color(0xFF7028DE), // morado: soporte
          const Color(0xFFF0E7FF),
          const Color(0xFFF9F6FF),
          _showSupportDialog,
        ),
      ],
    );
  }

  /// Acceso rápido compacto: la tarjeta completa conserva la acción original.
  /// El hover general resalta el bloque y la flecha tiene su propio hover,
  /// sin crear un segundo botón ni afectar la navegación por teclado.
  Widget _quickAction(
    IconData icon,
    String title,
    String subtitle,
    Color accent,
    Color tint,
    Color background,
    VoidCallback action,
  ) {
    return HoverBuilder(
      builder: (context, hovered) {
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final duration = reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 240);

        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0,
            hovered && !reduceMotion ? -2 : 0,
            0,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(Colors.white, background, 0.76)!, background],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: hovered ? 0.33 : 0.13),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: hovered ? 0.105 : 0.035),
                blurRadius: hovered ? 20 : 13,
                offset: Offset(0, hovered ? 7 : 4),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: action,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(18),
              hoverColor: Colors.transparent,
              highlightColor: accent.withValues(alpha: 0.035),
              splashColor: accent.withValues(alpha: 0.08),
              child: Semantics(
                button: true,
                label: '$title. $subtitle',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 17, 20, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedScale(
                        scale: hovered && !reduceMotion ? 1.04 : 1.0,
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: 54,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.075),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(
                                  alpha: hovered ? 0.14 : 0.08,
                                ),
                                blurRadius: hovered ? 14 : 9,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(icon, size: 27, color: accent),
                        ),
                      ),
                      const SizedBox(height: 11),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.22,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Mantiene las barras alineadas aunque el subtítulo
                      // tenga una o dos líneas en escritorio.
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 34),
                        child: Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Línea de acento puramente decorativa.
                          ExcludeSemantics(
                            child: Container(
                              width: 78,
                              height: 4,
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: AnimatedContainer(
                                width: hovered ? 58 : 42,
                                height: 4,
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                          // La flecha reacciona tanto al hover de la tarjeta
                          // como al mouse directamente encima de ella.
                          ExcludeSemantics(
                            child: HoverBuilder(
                              builder: (context, arrowHovered) {
                                return AnimatedScale(
                                  scale: arrowHovered && !reduceMotion
                                      ? 1.08
                                      : 1.0,
                                  duration: duration,
                                  curve: Curves.easeOutBack,
                                  child: AnimatedContainer(
                                    duration: duration,
                                    curve: Curves.easeOutCubic,
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: arrowHovered
                                          ? accent
                                          : (hovered
                                                ? accent.withValues(alpha: 0.21)
                                                : tint),
                                      border: Border.all(
                                        color: accent.withValues(
                                          alpha: arrowHovered ? 0.65 : 0.0,
                                        ),
                                      ),
                                      boxShadow: arrowHovered
                                          ? [
                                              BoxShadow(
                                                color: accent.withValues(
                                                  alpha: 0.25,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                          : const [],
                                    ),
                                    child: AnimatedSlide(
                                      duration: duration,
                                      curve: Curves.easeOutCubic,
                                      offset: arrowHovered
                                          ? const Offset(0.15, 0)
                                          : (hovered
                                                ? const Offset(0.06, 0)
                                                : Offset.zero),
                                      child: Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 21,
                                        color: arrowHovered
                                            ? Colors.white
                                            : accent,
                                      ),
                                    ),
                                  ),
                                );
                              },
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
  }

  Widget _buildPaymentAndSecurityRow() {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 820)
          return Column(
            children: [
              _buildNextPaymentCard(availableWidth: c.maxWidth),
              const SizedBox(height: _stackGap),
              _buildCalendarPreviewCard(),
            ],
          );
        // Ambas tarjetas comparten altura visual. El mini calendario conserva
        // su diseño compacto y ocupa el alto del bloque «Próximo pago».
        // IntrinsicHeight toma el alto natural de la tarjeta más alta; no
        // fija píxeles y respeta los tamaños de texto y el diseño responsive.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: _mainFlex,
                child: _buildNextPaymentCard(
                  availableWidth: _mainColumnWidth(c.maxWidth),
                ),
              ),
              const SizedBox(width: _colGap),
              Expanded(flex: _sideFlex, child: _buildCalendarPreviewCard()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountAndSchoolRow() {
    final account = Container(
      key: _accountSectionKey,
      child: _estadoCuenta == null
          ? _buildEstadoCuentaErrorBanner()
          : _buildEstadoCuentaDetalle(),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 820)
          return Column(
            children: [
              account,
              const SizedBox(height: _stackGap),
              _buildInstitutionCard(),
            ],
          );
        return _twoColumnRow(main: account, side: _buildInstitutionCard());
      },
    );
  }

  // Resumen del calendario en el lugar de la antigua tarjeta de seguridad.
  // La tarjeta completa abre la pestaña Calendario; sus eventos son reales.
  Widget _buildCalendarPreviewCard() {
    return RepresentativeCalendarPreview(
      representativeId: _repDbId,
      students: _students,
      onOpenCalendar: () {
        if (!mounted) return;
        setState(() => _selectedNavIndex = 2);
      },
    );
  }

  // Espacio reservado para la futura ficha institucional del colegio.
  // No mostramos datos de contacto ni horarios hasta que estén disponibles.
  Widget _buildInstitutionCard() {
    return _dashboardHover(
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomRight,
                children: [
                  const Icon(
                    Icons.school_outlined,
                    size: 75,
                    color: AppColors.violet,
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.violet,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Información del colegio',
              style: TextStyle(
                color: AppColors.darkNavy,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_schoolName.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                _schoolName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.violet,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Pronto podrás consultar horarios de atención, '
              'datos de contacto y comunicados de tu colegio desde aquí.',
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF2EEFF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE7DEFF)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: AppColors.violet,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Próximamente',
                    style: TextStyle(
                      color: AppColors.violet,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      hoverColor: AppColors.violet,
    );
  }

  void _showSupportDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Soporte'),
        content: const Text(
          'El canal de soporte en línea todavía no está disponible. Para consultas sobre pagos, comunícate con la administración de tu colegio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _showSecurityDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacidad de tu cuenta'),
        content: const Text(
          'Tu sesión requiere autenticación. Verifica los datos de cada pago antes de reportarlo y cierra sesión cuando uses un dispositivo compartido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // --- TARJETA DE SALDOS DINÁMICOS EN MULTIMONEDA (HU7) ---
  Widget _buildNextPaymentCard({double availableWidth = 1000}) {
    final hasAccount = _estadoCuenta != null;
    final balanceDue = hasAccount && _montoUsd > kToleranciaSaldoUsd;
    final String? selectedId =
        _selectedStudentIndex >= 0 && _selectedStudentIndex < _students.length
        ? _students[_selectedStudentIndex]['id'].toString()
        : null;
    final cuotas = _estadoCuenta?.cuotasPendientes(estudianteId: selectedId);
    final nextDue = cuotas != null && cuotas.isNotEmpty
        ? cuotas.first.fechaVencimiento
        : null;
    final dueText = nextDue == null
        ? (balanceDue
              ? 'Consulta el detalle de tus cuotas'
              : hasAccount
              ? 'No tienes cuotas pendientes'
              : 'Vencimiento no disponible')
        : 'Vencimiento: ${_fmtFecha(nextDue)}';
    final canReport =
        hasAccount &&
        (_deudaFamiliarUsd - (_estadoCuenta?.enRevisionUsd ?? 0)) >
            kToleranciaSaldoUsd;

    // Estado de la selección visible (familia completa o estudiante individual).
    // Una cuota vencida tiene prioridad sobre un pago aún en revisión.
    final today = DateUtils.dateOnly(DateTime.now());
    final hasOverdueBalance =
        balanceDue &&
        (cuotas?.any((cuota) {
              final due = cuota.fechaVencimiento;
              return due != null && DateUtils.dateOnly(due).isBefore(today);
            }) ??
            false);
    final reviewCoversBalance =
        balanceDue &&
        selectedId == null &&
        (_estadoCuenta?.enRevisionUsd ?? 0) > kToleranciaSaldoUsd &&
        (_estadoCuenta?.enRevisionUsd ?? 0) + kToleranciaSaldoUsd >= _montoUsd;

    final String paymentStatus;
    final Color paymentStatusColor;
    final IconData paymentStatusIcon;
    if (!hasAccount || _estadoCuentaError) {
      paymentStatus = 'SIN INFORMACIÓN';
      paymentStatusColor = AppColors.textMuted;
      paymentStatusIcon = Icons.help_outline_rounded;
    } else if (!balanceDue) {
      paymentStatus = 'SOLVENTE';
      paymentStatusColor = AppColors.successGreen;
      paymentStatusIcon = Icons.check_circle_outline_rounded;
    } else if (hasOverdueBalance) {
      paymentStatus = 'VENCIDO';
      paymentStatusColor = AppColors.errorRed;
      paymentStatusIcon = Icons.error_outline_rounded;
    } else if (reviewCoversBalance) {
      paymentStatus = 'EN REVISIÓN';
      paymentStatusColor = AppColors.primaryBlue;
      paymentStatusIcon = Icons.hourglass_top_rounded;
    } else {
      paymentStatus = 'PENDIENTE';
      paymentStatusColor = AppColors.warningAmber;
      paymentStatusIcon = Icons.schedule_rounded;
    }

    // Solo se presenta un estado cuando la consulta financiera es válida.
    final showPaymentStatus = hasAccount && !_estadoCuentaError;

    // Fondos pastel 100 % opacos: cada estado conserva su propia identidad.
    final Color paymentStatusBackground = switch (paymentStatus) {
      'SOLVENTE' => const Color(0xFFDDF5E8),
      'VENCIDO' => const Color(0xFFFDE5E5),
      'EN REVISIÓN' => const Color(0xFFE4EEFF),
      'PENDIENTE' => const Color(0xFFFFE8CF),
      _ => Colors.white,
    };

    final statusBadge = Semantics(
      label: 'Estado del pago: $paymentStatus',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: paymentStatusBackground,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: switch (paymentStatus) {
              'SOLVENTE' => const Color(0xFFA5E2BF),
              'VENCIDO' => const Color(0xFFF4B4B4),
              'EN REVISIÓN' => const Color(0xFFB5CEFF),
              'PENDIENTE' => const Color(0xFFF3CB9A),
              _ => AppColors.cardBorder,
            },
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(paymentStatusIcon, size: 15, color: paymentStatusColor),
            const SizedBox(width: 6),
            Text(
              paymentStatus,
              style: TextStyle(
                color: paymentStatusColor,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );

    return Builder(
      builder: (context) {
        final compact = availableWidth < 600;
        final actions = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: canReport
                  ? () => _showReportPaymentModal(context)
                  : null,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text(
                'Reportar pago',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _scrollTo(_accountSectionKey),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text(
                'Ver detalle',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.darkNavy,
                side: const BorderSide(color: Color(0xFF88B0FF)),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        );

        final amountSummary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Saldo pendiente',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              hasAccount ? '${_fmtUsd(_montoUsd)} USD' : 'Saldo no disponible',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 29 : 34,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w900,
                color: AppColors.darkNavy,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              hasAccount && _tasaBcv > 0
                  ? 'Equivalente: Bs. ${_fmtVes(_equivalenteVes)}'
                  : 'Equivalente en bolívares no disponible',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        );

        return _dashboardHover(
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF214576).withValues(alpha: 0.025),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: _featureCornerCurves(
              Padding(
                padding: EdgeInsets.all(compact ? 20 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compact && showPaymentStatus) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: statusBadge,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryBlue,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue.withValues(
                                  alpha: 0.12,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.calendar_month_outlined,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Próximo pago',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.darkNavy,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                dueText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!compact && showPaymentStatus) ...[
                          const SizedBox(width: 12),
                          statusBadge,
                        ],
                      ],
                    ),
                    const SizedBox(height: 22),
                    if (compact) ...[
                      amountSummary,
                      const SizedBox(height: 20),
                      actions,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(flex: 5, child: amountSummary),
                          const SizedBox(width: 20),
                          Expanded(flex: 3, child: actions),
                        ],
                      ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: AppColors.cardBorder),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.currency_exchange_rounded,
                          size: 16,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _tasaBcv > 0
                                ? 'Tasa BCV: 1 USD = Bs. $_tasaBcvStr · $_tasaFechaLabel'
                                : 'Tasa BCV no disponible',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              color: AppColors.primaryBlue,
            ),
          ),
        );
      },
    );
  }

  String _fmtVes(double amount) {
    final split = amount.abs().toStringAsFixed(2).split('.');
    final digits = split.first;
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return '${amount < 0 ? '-' : ''}$out,${split.last}';
  }

  String _fmtUsd(double v) => '\$${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String _fmtFecha(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _buildEstadoCuentaErrorBanner() {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.tint(AppColors.errorRed),
          borderRadius: BorderRadius.circular(AppSizes.radiusCard),
          border: Border.all(color: AppColors.tint(AppColors.errorRed, 0.4)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.errorRed,
              size: 24,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No pudimos cargar tu estado de cuenta. Tus datos están a salvo: revisa tu conexión y vuelve a intentarlo.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: AppColors.darkNavy,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _updateFinancialSummary,
              style: TextButton.styleFrom(
                minimumSize: const Size(AppSizes.minTarget, AppSizes.control),
                foregroundColor: AppColors.primaryBlue,
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text(
                'Reintentar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoStrip(
    IconData icon,
    Color bg,
    Color border,
    Color fg,
    String text,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.radiusControl),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: AppColors.darkNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- ESTADO DE CUENTA DESGLOSADO (cuota por cuota, de la más antigua) ---
  // Se mantiene el orden y la fuente de datos originales. La nueva distribución
  // prioriza el saldo, el vencimiento y el progreso de cada mensualidad.
  Widget _buildEstadoCuentaDetalle() {
    final estado = _estadoCuenta;
    if (estado == null) return const SizedBox.shrink();

    final String? selectedId =
        (_selectedStudentIndex >= 0 && _selectedStudentIndex < _students.length)
        ? _students[_selectedStudentIndex]['id'].toString()
        : null;
    final bool consolidado = selectedId == null;
    final pendientes = estado.cuotasPendientes(estudianteId: selectedId);
    final nombres = <String, String>{
      for (final st in _students)
        st['id'].toString():
            (st['nombres']?.toString().split(' ').first ?? 'Estudiante'),
    };
    final total = pendientes.length;

    return _dashboardHover(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.primaryBlue,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estado de cuenta',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        consolidado
                            ? 'Desglose de toda tu familia'
                            : 'Desglose del estudiante seleccionado',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$total ${total == 1 ? 'pendiente' : 'pendientes'}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Los pagos aprobados se aplican a la deuda o cuota más reciente',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            if (estado.creditoUsd > kToleranciaSaldoUsd)
              _buildInfoStrip(
                Icons.savings_outlined,
                AppColors.tint(AppColors.successGreen),
                AppColors.tint(AppColors.successGreen, 0.4),
                AppColors.successGreen,
                'Saldo a favor: ${_fmtUsd(estado.creditoUsd)}. Se aplicará automáticamente a tu próxima cuota.',
              ),
            if (estado.enRevisionUsd > kToleranciaSaldoUsd)
              _buildInfoStrip(
                Icons.hourglass_top,
                AppColors.primaryLight,
                AppColors.tint(AppColors.primaryBlue, 0.4),
                AppColors.primaryBlue,
                'Tienes ${_fmtUsd(estado.enRevisionUsd)} en pagos pendientes de revisión. Se actualizará su estado de cuenta cuando el colegio los apruebe.',
              ),
            if (pendientes.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppColors.successGreen,
                      size: 28,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No hay cuotas pendientes',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...pendientes.map(
                (c) => _buildCuotaRow(
                  c,
                  alumno: consolidado ? nombres[c.estudianteId] : null,
                ),
              ),
            if (estado.cuotasPagadas > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: AppColors.successGreen,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${estado.cuotasPagadas} ${estado.cuotasPagadas == 1 ? 'cuota pagada' : 'cuotas pagadas'} en total.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCuotaRow(CuotaEstadoCuenta c, {String? alumno}) {
    final (Color accent, IconData chipIcon) = switch (c.estado) {
      'VENCIDO' => (AppColors.errorRed, Icons.error_outline_rounded),
      'PARCIAL' => (AppColors.warningAmber, Icons.pie_chart_outline_rounded),
      _ => (AppColors.primaryBlue, Icons.schedule_rounded),
    };
    final String titulo = c.periodo.isNotEmpty ? c.periodo : c.concepto;
    final String detalle = [
      if (alumno != null && alumno.trim().isNotEmpty) alumno,
      if (c.concepto.isNotEmpty && c.periodo.isNotEmpty) c.concepto,
    ].join(' • ');
    final double abonado = c.aplicadoUsd.clamp(0.0, double.infinity).toDouble();
    final double total = c.montoUsd;
    final double porcentaje = total > 0
        ? (abonado / total).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HoverBuilder(
        builder: (context, hovered) => AnimatedContainer(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: hovered
                  ? accent.withValues(alpha: 0.48)
                  : AppColors.cardBorder,
            ),
            boxShadow: hovered
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.065),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 41,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkNavy,
                          ),
                        ),
                        if (detalle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            detalle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.event_outlined,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Vence ${_fmtFecha(c.fechaVencimiento)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Saldo pendiente',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _fmtUsd(c.saldoUsd),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tint(accent),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(chipIcon, size: 13, color: accent),
                            const SizedBox(width: 5),
                            Text(
                              c.estado,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: AppColors.cardBorder),
              const SizedBox(height: 12),
              Text(
                'Abonado ${_fmtUsd(abonado)} de ${_fmtUsd(total)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: porcentaje,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE9EFF8),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.successGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // El botón primario «Reportar pago» vive en la tarjeta de saldo. Aquí queda
  // solo la acción secundaria, con explicación cuando está deshabilitada.
  Widget _buildActionButtons() {
    final bool enabled = _isSolventeFamiliar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          // El QR todavía no está implementado en el código proporcionado.
          // No simular generación exitosa ni habilitar un botón sin acción.
          onPressed: null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkNavy,
            side: const BorderSide(color: AppColors.cardBorder),
            minimumSize: const Size.fromHeight(AppSizes.control),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusControl),
            ),
          ),
          icon: const Icon(Icons.qr_code, size: 18),
          label: const Text(
            'Pase digital (próximamente)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        if (!enabled) ...[
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Para emitir el pase será necesario estar solvente. Esta función está en desarrollo.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // Documentación académica: tarjetas informativas mientras los trámites no
  // estén publicados. Se evita mostrar botones de descarga sin acción real.
  Widget _buildDigitalDocumentsSection() {
    final activeStudentFirstName =
        _students.isNotEmpty &&
            _selectedStudentIndex >= 0 &&
            _selectedStudentIndex < _students.length
        ? (_students[_selectedStudentIndex]['nombres']
                  ?.toString()
                  .trim()
                  .split(RegExp(r'\s+'))
                  .firstOrNull ??
              'tu estudiante')
        : 'tu familia';
    final canCheckSolvency = _estadoCuenta != null;
    final blocked = canCheckSolvency && !_isSolventeFamiliar;
    final accessStatus = !canCheckSolvency
        ? 'Solvencia por verificar'
        : blocked
        ? 'Requiere solvencia'
        : 'Por publicar';
    final accessIcon = !canCheckSolvency
        ? Icons.help_outline_rounded
        : blocked
        ? Icons.lock_outline_rounded
        : Icons.schedule_rounded;
    final accessBg = !canCheckSolvency
        ? const Color(0xFFF1F5F9)
        : blocked
        ? const Color(0xFFFFF3E2)
        : const Color(0xFFEAF2FF);
    final accessFg = !canCheckSolvency
        ? const Color(0xFF475569)
        : blocked
        ? const Color(0xFF995100)
        : AppColors.primaryDark;

    return _dashboardHover(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.folder_copy_outlined,
                    size: 22,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Documentos académicos',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Trámites y documentos de $activeStudentFirstName',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ResponsiveGrid(
              wideCols: 3,
              mediumCols: 2,
              narrowCols: 1,
              wideBreak: 720,
              mediumBreak: 440,
              gap: 12,
              hoverLift: 0,
              hoverRadius: 14,
              items: [
                SizedBox(
                  height: 226,
                  child: _buildDocCard(
                    icon: Icons.calendar_month_outlined,
                    iconColor: AppColors.primaryBlue,
                    iconBackground: const Color(0xFFEAF2FF),
                    title: 'Plan de evaluación y horarios',
                    description:
                        'Actividades, evaluaciones y horarios escolares.',
                    status: 'En preparación',
                    statusIcon: Icons.schedule_rounded,
                    statusBackground: const Color(0xFFEAF2FF),
                    statusColor: AppColors.primaryDark,
                  ),
                ),
                SizedBox(
                  height: 226,
                  child: _buildDocCard(
                    icon: Icons.school_outlined,
                    iconColor: const Color(0xFF6D45C8),
                    iconBackground: const Color(0xFFF0EDFF),
                    title: 'Boletín de calificaciones',
                    description:
                        'Consulta de las calificaciones del estudiante.',
                    status: accessStatus,
                    statusIcon: accessIcon,
                    statusBackground: accessBg,
                    statusColor: accessFg,
                  ),
                ),
                SizedBox(
                  height: 226,
                  child: _buildDocCard(
                    icon: Icons.assignment_outlined,
                    iconColor: const Color(0xFF087E64),
                    iconBackground: const Color(0xFFE7F7F1),
                    title: 'Reinscripción y reserva',
                    description:
                        'Documentación para el próximo período escolar.',
                    status: accessStatus,
                    statusIcon: accessIcon,
                    statusBackground: accessBg,
                    statusColor: accessFg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.textMuted,
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estos documentos se habilitarán cuando el colegio los publique.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required String description,
    required String status,
    required IconData statusIcon,
    required Color statusBackground,
    required Color statusColor,
  }) {
    return _dashboardHover(
      Container(
        constraints: const BoxConstraints(minHeight: 188),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: iconColor),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F6FB),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text(
                    'PDF',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            // Same vertical slots on every card, even when titles wrap.
            SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkNavy,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 38,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: statusBackground,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 15, color: statusColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      radius: 14,
    );
  }

  Widget _buildFooterSecurityNotice() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: AppColors.primaryBlue,
                size: 18,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protección integral del estudiante',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    Text(
                      'El acceso a clases, evaluaciones y actividades académicas está garantizado conforme a la LOPNNA.',
                      style: TextStyle(fontSize: 11, color: AppColors.darkNavy),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.shield_outlined,
                size: 13,
                color: AppColors.textMuted,
              ),
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Tus pagos están protegidos y serán verificados por la institución.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Logotipo de familia: un adulto detrás de dos hijos. Se dibuja en
/// vectores, así que se ve nítido a cualquier tamaño.
class _FamilyMark extends StatelessWidget {
  final double size;

  /// Color del fondo sobre el que se dibuja (separa al niño de los adultos).
  final Color background;

  const _FamilyMark({required this.size, required this.background});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Un adulto con dos hijos',
      child: CustomPaint(
        size: Size.square(size),
        painter: _FamilyMarkPainter(background: background),
      ),
    );
  }
}

class _FamilyMarkPainter extends CustomPainter {
  final Color background;
  const _FamilyMarkPainter({required this.background});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final adult = Paint()..color = AppColors.primaryBlue;
    final child = Paint()
      ..color = Color.lerp(AppColors.primaryBlue, Colors.white, 0.38)!;
    final gap = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05;

    void person({
      required double cx,
      required double headY,
      required double headR,
      required double bodyTop,
      required double bodyBottom,
      required double bodyHalfW,
      required Paint paint,
      bool outline = false,
    }) {
      final body = RRect.fromRectAndCorners(
        Rect.fromLTRB(
          (cx - bodyHalfW) * s,
          bodyTop * s,
          (cx + bodyHalfW) * s,
          bodyBottom * s,
        ),
        topLeft: Radius.circular(bodyHalfW * s * 0.95),
        topRight: Radius.circular(bodyHalfW * s * 0.95),
        bottomLeft: Radius.circular(bodyHalfW * s * 0.35),
        bottomRight: Radius.circular(bodyHalfW * s * 0.35),
      );
      final head = Offset(cx * s, headY * s);
      if (outline) {
        canvas.drawRRect(body, gap);
        canvas.drawCircle(head, headR * s, gap);
      }
      canvas.drawRRect(body, paint);
      canvas.drawCircle(head, headR * s, paint);
    }

    // Adulto en el centro, detrás de los hijos.
    person(
      cx: 0.50,
      headY: 0.20,
      headR: 0.125,
      bodyTop: 0.38,
      bodyBottom: 0.95,
      bodyHalfW: 0.18,
      paint: adult,
    );
    // Dos niños más pequeños en primer plano, separados del adulto.
    person(
      cx: 0.23,
      headY: 0.50,
      headR: 0.091,
      bodyTop: 0.64,
      bodyBottom: 0.96,
      bodyHalfW: 0.115,
      paint: child,
      outline: true,
    );
    person(
      cx: 0.77,
      headY: 0.50,
      headR: 0.091,
      bodyTop: 0.64,
      bodyBottom: 0.96,
      bodyHalfW: 0.115,
      paint: child,
      outline: true,
    );
  }

  @override
  bool shouldRepaint(_FamilyMarkPainter old) => old.background != background;
}

// Tres capas orgánicas muy tenues, limitadas a la esquina superior derecha.
// El color se parametriza para respetar el estado de solvencia.
class _FeatureCornerCurvesPainter extends CustomPainter {
  final Color color;
  final double scale;
  const _FeatureCornerCurvesPainter(this.color, {this.scale = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Se ancla en la esquina superior derecha: al aumentar de 1 a 1.13,
    // las ondas avanzan suavemente hacia abajo y hacia la izquierda.
    canvas.save();
    canvas.translate(w, 0);
    canvas.scale(scale, scale);
    canvas.translate(-w, 0);

    final outer = Path()
      ..moveTo(w - 210, 0)
      ..cubicTo(w - 165, 55, w - 118, 127, w, 96)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(outer, Paint()..color = color.withValues(alpha: 0.060));

    final mid = Path()
      ..moveTo(w - 138, 0)
      ..cubicTo(w - 111, 44, w - 66, 85, w, 60)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(mid, Paint()..color = color.withValues(alpha: 0.055));

    final inner = Path()
      ..moveTo(w - 68, 0)
      ..cubicTo(w - 48, 28, w - 24, 44, w, 35)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(inner, Paint()..color = color.withValues(alpha: 0.055));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FeatureCornerCurvesPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scale != scale;
}
