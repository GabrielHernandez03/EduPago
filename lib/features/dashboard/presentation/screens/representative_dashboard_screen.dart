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
            } else if (_selectedStudentIndex >= _students.length) {
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
                const SizedBox(height: 26),
                _buildHeroStatusRow(),
                const SizedBox(height: 24),
                _buildQuickActions(),
                const SizedBox(height: 24),
                _buildPaymentAndSecurityRow(),
                const SizedBox(height: 24),
                _buildAccountAndSchoolRow(),
                const SizedBox(height: 26),
                Container(
                  key: _documentsSectionKey,
                  child: _buildDigitalDocumentsSection(),
                ),
                const SizedBox(height: 20),
                _buildActionButtons(),
                const SizedBox(height: 24),
                _buildRepresentativeHeaderCard(),
                const SizedBox(height: 24),
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

  Widget _buildHeroStatusRow() {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 800) {
          return Column(
            children: [
              _buildStudentSelectorCard(),
              const SizedBox(height: 14),
              _buildSolvencyStatusCard(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: _buildStudentSelectorCard()),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: _buildSolvencyStatusCard()),
          ],
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
              : '${selected['nombres'] ?? ''} ${selected['apellidos'] ?? ''}'
                    .trim());
    final details = consolidated
        ? '${_students.length} estudiantes vinculados'
        : selected != null
        ? _studentDetails(selected)
        : 'Sin grado ni cédula registrados';
    final initials = consolidated ? 'FAM' : _getInitials(name);
    final content = Container(
      constraints: const BoxConstraints(minHeight: 114),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: _whiteCard(border: AppColors.primaryBlue),
      child: Row(
        children: [
          CircleAvatar(
            radius: 33,
            backgroundColor: const Color(0xFFDDE9FF),
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.primaryBlue,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ESTUDIANTE',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
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
                const SizedBox(height: 6),
                Tooltip(
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
              ],
            ),
          ),
          if (hasStudents) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted,
            ),
          ],
        ],
      ),
    );
    if (!hasStudents) return content;
    return PopupMenuButton<int>(
      tooltip: 'Seleccionar estudiante',
      onSelected: _chooseStudent,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        if (_students.length > 1)
          const PopupMenuItem(value: -1, child: Text('Toda mi familia')),
        for (var i = 0; i < _students.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_students[i]['nombres'] ?? ''} ${_students[i]['apellidos'] ?? ''}'
                      .trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  _studentDetails(_students[i]),
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
      ],
      child: content,
    );
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
    final backgroundStart = unknown
        ? const Color(0xFFF7F9FC)
        : solvent
        ? const Color(0xFFF3FCF7)
        : const Color(0xFFFFF9F0);
    final backgroundEnd = unknown
        ? const Color(0xFFEDF2F9)
        : solvent
        ? const Color(0xFFE0F5E9)
        : const Color(0xFFFFEED8);
    final outline = unknown
        ? const Color(0xFFD5DFEF)
        : solvent
        ? const Color(0xFFB8E4CC)
        : const Color(0xFFF1D5A7);
    return Semantics(
      liveRegion: true,
      label: 'Solvencia familiar: $status. $detail',
      child: Container(
        constraints: const BoxConstraints(minHeight: 114),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [backgroundStart, backgroundEnd],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: outline),
          boxShadow: [
            BoxShadow(
              color: state.withValues(alpha: 0.045),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            children: [
              Positioned(
                right: -38,
                top: -48,
                child: Container(
                  width: 146,
                  height: 146,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.withValues(alpha: 0.045),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 22,
                ),
                child: Row(
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
                    Expanded(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return ResponsiveGrid(
      wideCols: 4,
      mediumCols: 2,
      narrowCols: 1,
      wideBreak: 970,
      mediumBreak: 510,
      gap: 18,
      hoverLift: 2,
      items: [
        _quickAction(
          Icons.credit_card_rounded,
          'Pagar mensualidad',
          'Reporta tu pago de forma segura',
          AppColors.primaryBlue,
          const Color(0xFFE5EFFF),
          () => _showReportPaymentModal(context),
        ),
        _quickAction(
          Icons.receipt_long_rounded,
          'Ver estado de cuenta',
          'Consulta tus cuotas y saldos',
          AppColors.violet,
          AppColors.lavender,
          () => _scrollTo(_accountSectionKey),
        ),
        _quickAction(
          Icons.description_outlined,
          'Documentos',
          'Consulta tus trámites digitales',
          const Color(0xFF069B67),
          AppColors.mint,
          () => _scrollTo(_documentsSectionKey),
        ),
        _quickAction(
          Icons.headset_mic_rounded,
          'Soporte',
          'Estamos aquí para ayudarte',
          AppColors.violet,
          AppColors.lavender,
          _showSupportDialog,
        ),
      ],
    );
  }

  Widget _quickAction(
    IconData icon,
    String title,
    String subtitle,
    Color accent,
    Color tint,
    VoidCallback action,
  ) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 160),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: tint,
                  child: Icon(icon, color: accent, size: 27),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkNavy,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentAndSecurityRow() {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 820)
          return Column(
            children: [
              _buildNextPaymentCard(),
              const SizedBox(height: 18),
              _buildProtectionCard(),
            ],
          );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: _buildNextPaymentCard()),
            const SizedBox(width: 20),
            Expanded(flex: 3, child: _buildProtectionCard()),
          ],
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
              const SizedBox(height: 18),
              _buildInstitutionCard(),
            ],
          );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: account),
            const SizedBox(width: 20),
            Expanded(flex: 3, child: _buildInstitutionCard()),
          ],
        );
      },
    );
  }

  Widget _buildProtectionCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFEBF4FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD5E5FC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                const Icon(
                  Icons.article_outlined,
                  size: 75,
                  color: AppColors.primaryBlue,
                ),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primaryBlue,
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Tu información está protegida',
            style: TextStyle(
              color: AppColors.darkNavy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tu información escolar y financiera se consulta desde tu cuenta.',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _showSecurityDialog,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.shield_outlined, size: 18),
            label: const Text(
              'Más información',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstitutionCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6F5FF), Color(0xFFEFF2FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 23,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.school_rounded,
              color: AppColors.violet,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _schoolName.isEmpty
                      ? 'Tu colegio, siempre contigo'
                      : _schoolName,
                  maxLines: 3,
                  style: const TextStyle(
                    color: AppColors.darkNavy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Consulta tus mensualidades, documentos y la información de tu familia en un solo lugar.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildRepresentativeHeaderCard() {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 560;

        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REPRESENTANTE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _fullName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: AppColors.darkNavy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$_cedula • $_familyName${_email.isNotEmpty ? ' • $_email' : ''}',
              maxLines: compact ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        );

        // Botón tonal (no outline): se distingue de una etiqueta estática.
        final editButton = ElevatedButton.icon(
          onPressed: () => _showEditProfileModal(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.primaryDark,
            elevation: 0,
            minimumSize: const Size(AppSizes.minTarget, AppSizes.control),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            side: const BorderSide(color: AppColors.primaryBlue),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusControl),
            ),
          ),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text(
            'Editar perfil',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        );

        return Container(
          padding: EdgeInsets.all(compact ? 16 : 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Expanded(child: info)],
                    ),
                    const SizedBox(height: 14),
                    editButton,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 12),
                    editButton,
                  ],
                ),
        );
      },
    );
  }

  // --- TARJETA DE SALDOS DINÁMICOS EN MULTIMONEDA (HU7) ---
  Widget _buildNextPaymentCard() {
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
              : 'No tienes cuotas pendientes')
        : 'Vencimiento: ${_fmtFecha(nextDue)}';
    final canReport =
        hasAccount &&
        (_deudaFamiliarUsd - (_estadoCuenta?.enRevisionUsd ?? 0)) >
            kToleranciaSaldoUsd;

    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 600;
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
                  borderRadius: BorderRadius.circular(11),
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
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ],
        );
        final summary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primaryBlue,
                  child: Icon(
                    Icons.calendar_month_outlined,
                    size: 26,
                    color: Colors.white,
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
                          fontSize: 18,
                          color: AppColors.darkNavy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dueText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              hasAccount ? '${_fmtUsd(_montoUsd)} USD' : 'Saldo no disponible',
              style: TextStyle(
                fontSize: compact ? 30 : 34,
                letterSpacing: -0.6,
                color: AppColors.darkNavy,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              hasAccount && _tasaBcv > 0
                  ? 'Equivalente en bolívares: Bs. ${_fmtVes(_equivalenteVes)}'
                  : 'Equivalente en bolívares no disponible',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 17,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Tasa BCV: $_tasaFechaLabel',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _tasaBcv > 0
                      ? '1 USD = Bs. $_tasaBcvStr'
                      : 'Tasa por consultar',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        );
        return Container(
          padding: EdgeInsets.all(compact ? 20 : 28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF2F7FF)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC9DEFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: balanceDue
                        ? const Color(0xFFFFF2E4)
                        : AppColors.mint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    !hasAccount
                        ? 'Por verificar'
                        : balanceDue
                        ? 'Por pagar'
                        : 'Al día',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: balanceDue
                          ? AppColors.warningAmber
                          : AppColors.successGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (compact) ...[
                summary,
                const SizedBox(height: 18),
                actions,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 5, child: summary),
                    const SizedBox(width: 18),
                    Expanded(flex: 3, child: actions),
                  ],
                ),
            ],
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

    return Container(
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
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  consolidado
                      ? 'Estado de cuenta desglosado (familia)'
                      : 'Estado de cuenta desglosado',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'De la cuota más antigua a la más reciente. Cada pago aprobado se aplica en ese orden.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
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
              'Tienes ${_fmtUsd(estado.enRevisionUsd)} en pagos pendientes de revisión. Se aplicarán a las cuotas más antiguas cuando el colegio los apruebe.',
            ),
          if (pendientes.isEmpty)
            const Text(
              'No hay cuotas pendientes.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
            Text(
              '${estado.cuotasPagadas} ${estado.cuotasPagadas == 1 ? 'cuota pagada' : 'cuotas pagadas'} en total.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCuotaRow(CuotaEstadoCuenta c, {String? alumno}) {
    final (Color accent, IconData chipIcon) = switch (c.estado) {
      'VENCIDO' => (AppColors.errorRed, Icons.error_outline),
      'PARCIAL' => (AppColors.warningAmber, Icons.timelapse),
      _ => (AppColors.primaryBlue, Icons.schedule),
    };
    final String titulo = c.periodo.isNotEmpty ? c.periodo : c.concepto;
    final String sub = [
      if (alumno != null) alumno,
      if (c.concepto.isNotEmpty && c.periodo.isNotEmpty) c.concepto,
      'Vence ${_fmtFecha(c.fechaVencimiento)}',
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmtUsd(c.saldoUsd),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                ),
              ),
              if (c.aplicadoUsd > kToleranciaSaldoUsd)
                Text(
                  'Abonado ${_fmtUsd(c.aplicadoUsd)} de ${_fmtUsd(c.montoUsd)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.tint(accent),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(chipIcon, size: 14, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      c.estado,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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

  Widget _buildDigitalDocumentsSection() {
    final activeStudentFirstName =
        _students.isNotEmpty &&
            _selectedStudentIndex >= 0 &&
            _selectedStudentIndex < _students.length
        ? (_students[_selectedStudentIndex]['nombres']?.toString().split(
                ' ',
              )[0] ??
              'estudiante')
        : 'la familia';

    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PORTAL ACADÉMICO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Text(
                      'Trámites Digitales y Documentación Académica',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Documentos asociados a $activeStudentFirstName',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 3 columnas en escritorio, 2 en tablet, 1 en teléfono
          ResponsiveGrid(
            wideCols: 3,
            mediumCols: 2,
            narrowCols: 1,
            wideBreak: 720,
            mediumBreak: 440,
            gap: 12,
            hoverLift: 2,
            hoverRadius: 12,
            items: [
              _buildDocCard(
                badgeText: 'PDF',
                badgeColor: const Color(0xFFFEE2E2),
                badgeTextColor: const Color(0xFFDC2626),
                title: 'Plan de Evaluación y Horarios',
                subtitle: 'Disponible cuando el colegio lo publique',
                statusTagText: 'En preparación',
                statusTagBg: const Color(0xFFDCFCE7),
                statusTagTextColor: const Color(0xFF166534),
                buttonText: 'Próximamente',
                buttonIcon: Icons.download_outlined,
                isLocked: true,
              ),
              _buildDocCard(
                badgeText: 'PDF',
                badgeColor: const Color(0xFFF1F5F9),
                badgeTextColor: AppColors.textMuted,
                title: 'Boletín Digital de Calificaciones',
                subtitle: 'Disponible cuando el colegio lo publique',
                statusTagText: _isSolventeFamiliar
                    ? 'Pendiente de publicación'
                    : 'Bloqueado: saldo pendiente',
                statusTagBg: const Color(0xFFFEF3C7),
                statusTagTextColor: const Color(0xFFB45309),
                buttonText: 'No disponible',
                buttonIcon: Icons.lock_outline,
                isLocked: true,
              ),
              _buildDocCard(
                badgeText: 'PDF',
                badgeColor: const Color(0xFFF1F5F9),
                badgeTextColor: AppColors.textMuted,
                title: 'Planilla de Reinscripción y Reserva',
                subtitle: 'Se habilitará desde el colegio',
                statusTagText: _isSolventeFamiliar
                    ? 'En preparación'
                    : 'Requiere solvencia activa',
                statusTagBg: _isSolventeFamiliar
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEE2E2),
                statusTagTextColor: _isSolventeFamiliar
                    ? const Color(0xFF166534)
                    : const Color(0xFFDC2626),
                buttonText: _isSolventeFamiliar ? 'Próximamente' : 'Bloqueado',
                buttonIcon: _isSolventeFamiliar
                    ? Icons.download_outlined
                    : Icons.lock_outline,
                isLocked: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocCard({
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    required String title,
    required String subtitle,
    required String statusTagText,
    required Color statusTagBg,
    required Color statusTagTextColor,
    required String buttonText,
    required IconData buttonIcon,
    required bool isLocked,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: badgeTextColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.darkNavy,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusTagBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusTagText,
              style: TextStyle(
                color: statusTagTextColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  null, // Se conectará a la generación real de documentos.
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.darkNavy,
                disabledForegroundColor: AppColors.textMuted,
                side: BorderSide(
                  color: isLocked ? Colors.transparent : AppColors.cardBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(buttonIcon, size: 14),
              label: Text(
                buttonText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterSecurityNotice() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
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
