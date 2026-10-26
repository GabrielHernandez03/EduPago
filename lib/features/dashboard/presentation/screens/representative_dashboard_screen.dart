import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/bcv_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';
import '../../../landing/presentation/screens/home_screen.dart';
import '../../data/account_status_service.dart';
import '../widgets/edit_profile_dialog.dart';
import '../widgets/report_payment_dialog.dart';
import '../../../../core/widgets/dashboard_shell.dart';

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

          // 2. Cargar estudiantes vinculados
          if (_repDbId.isNotEmpty) {
            await fetchAssociatedStudents(_repDbId);
          }
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

  // --- CÁLCULO DINÁMICO DE SALDOS Y TASA BCV (HU7) ---
  Future<void> _updateFinancialSummary() async {
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
    EstadoCuenta? estado;
    try {
      estado = await _accountStatusService.getEstadoCuenta(
        representanteId: _repDbId,
      );
    } catch (e) {
      debugPrint('Error consultando el estado de cuenta: $e');
    }

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

    final String titular = _students.length > 1
        ? (_familyName.isNotEmpty ? 'Familia $_familyName' : 'Mi familia')
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
    DashboardNavItem(Icons.home_outlined, Icons.home, 'Mi resumen'),
    DashboardNavItem(
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
      'Pagos',
    ),
    DashboardNavItem(Icons.verified_outlined, Icons.verified, 'Solvencias'),
    DashboardNavItem(
      Icons.description_outlined,
      Icons.description,
      'Documentos',
    ),
  ];

  static const String _schoolName = 'U.E. Nueva Generación';

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      navItems: _navItems,
      selectedIndex: _selectedNavIndex,
      onNavSelected: (i) => setState(() => _selectedNavIndex = i),
      schoolName: _schoolName,
      userName: _fullName.isEmpty ? 'Representante' : _fullName,
      userInitials: _initials.isEmpty ? 'U' : _initials,
      userRole: 'Representante',
      onLogout: _handleLogout,
      searchHint: 'Buscar pago, documento o referencia...',
      hasNotifications: true,
      headerActions: [_buildPeriodChip()],
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading || _isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    // Pestañas aún pendientes (igual que en el panel del administrador)
    if (_selectedNavIndex != 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _navItems[_selectedNavIndex].icon,
                color: AppColors.textMuted,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                '${_navItems[_selectedNavIndex].title} estará disponible próximamente.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _selectedNavIndex = 0),
                child: const Text('Volver al resumen'),
              ),
            ],
          ),
        ),
      );
    }

    final pagePad = Breakpoints.pageInsets(MediaQuery.sizeOf(context).width);

    return RefreshIndicator(
      onRefresh: () => fetchUserProfileAndStudents(silent: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pagePad,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HoverLift(
                  radius: 16,
                  lift: 0,
                  child: _buildRepresentativeHeaderCard(),
                ),
                const SizedBox(height: 24),
                _buildStudentsSection(),
                const SizedBox(height: 16),
                _buildAcademicStatusBanner(),
                const SizedBox(height: 16),
                HoverLift(radius: 16, lift: 2, child: _buildNextPaymentCard()),
                const SizedBox(height: 16),
                _buildEstadoCuentaDetalle(),
                const SizedBox(height: 16),
                _buildActionButtons(),
                const SizedBox(height: 28),
                HoverLift(
                  radius: 16,
                  lift: 0,
                  child: _buildRecentActivitySection(),
                ),
                const SizedBox(height: 28),
                HoverLift(
                  radius: 16,
                  lift: 0,
                  child: _buildDigitalDocumentsSection(),
                ),
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

  // Chip del período escolar (acción del encabezado, como la tasa en admin)
  Widget _buildPeriodChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 14,
            color: AppColors.darkNavy,
          ),
          SizedBox(width: 8),
          Text(
            'Período 2024-2025',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.darkNavy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepresentativeHeaderCard() {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 560;

        final avatar = Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: AppColors.primaryBlue,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        );

        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REPRESENTANTE',
              style: TextStyle(
                fontSize: 10,
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

        final editButton = OutlinedButton.icon(
          onPressed: () => _showEditProfileModal(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkNavy,
            side: const BorderSide(color: AppColors.cardBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.person_outline, size: 16),
          label: const Text(
            'Editar perfil',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                      children: [
                        avatar,
                        const SizedBox(width: 14),
                        Expanded(child: info),
                      ],
                    ),
                    const SizedBox(height: 14),
                    editButton,
                  ],
                )
              : Row(
                  children: [
                    avatar,
                    const SizedBox(width: 16),
                    Expanded(child: info),
                    const SizedBox(width: 12),
                    editButton,
                  ],
                ),
        );
      },
    );
  }

  // --- RENDERIZADO DINÁMICO Y FILTRADO CONSOLIDADO/INDIVIDUAL (HU7) ---
  Widget _buildStudentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Mis estudiantes',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.darkNavy,
              ),
            ),
            Text(
              '${_students.length} vinculados',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_students.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.textMuted, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No hay estudiantes asignados a este representante.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Pestaña Consolidado Familiar (Toda la familia)
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: _buildStudentTabCard(
                    -1,
                    'FAM',
                    'Consolidado Fam.',
                    'Todos los alumnos',
                  ),
                ),
                // Pestañas individuales de estudiantes
                ...List.generate(_students.length, (index) {
                  final student = _students[index];
                  final String studentNombres =
                      student['nombres'] ?? 'Estudiante';
                  final String studentApellidos = student['apellidos'] ?? '';
                  final String fullStudentName =
                      '$studentNombres $studentApellidos'.trim();
                  final String gradeSection =
                      student['grado_seccion'] ?? 'Grado no especificado';
                  final String initials = _getInitials(fullStudentName);

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index < _students.length - 1 ? 12.0 : 0.0,
                    ),
                    child: _buildStudentTabCard(
                      index,
                      initials,
                      fullStudentName,
                      gradeSection,
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStudentTabCard(
    int index,
    String initials,
    String name,
    String grade,
  ) {
    final bool isSelected = _selectedStudentIndex == index;
    return HoverBuilder(
      builder: (context, hovered) => HoverLift(
        radius: 12,
        lift: 2,
        child: InkWell(
          hoverColor: Colors.transparent,
          onTap: () {
            setState(() => _selectedStudentIndex = index);
            _updateFinancialSummary(); // Recalcular dinámicamente saldos al cambiar opción
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEFF6FF)
                  : (hovered ? const Color(0xFFF8FAFC) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primaryBlue
                    : (hovered
                          ? const Color(0xFF93C5FD)
                          : AppColors.cardBorder),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFBFDBFE)
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.primaryBlue
                            : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Ancho máximo: sin él, un nombre largo ensancha la tarjeta sin límite
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.darkNavy,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        grade,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.check,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAcademicStatusBanner() {
    if (_estadoCuentaError) return _buildEstadoCuentaErrorBanner();
    final bool isSolvente = _isSolventeFamiliar;

    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 480;

        final detail = Text(
          isSolvente
              ? ((_estadoCuenta?.creditoUsd ?? 0) > kToleranciaSaldoUsd
                    ? 'Saldo a favor: ${_fmtUsd(_estadoCuenta!.creditoUsd)}'
                    : 'Sin pagos pendientes')
              : 'Saldo familiar: ${_fmtUsd(_deudaFamiliarUsd)}',
          textAlign: compact ? TextAlign.start : TextAlign.end,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSolvente
                ? const Color(0xFF16A34A)
                : const Color(0xFFD97706),
          ),
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSolvente
                ? const Color(0xFFF0FDF4)
                : const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSolvente
                  ? const Color(0xFFBBF7D0)
                  : const Color(0xFFFDE68A),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSolvente
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFD97706),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSolvente ? Icons.check : Icons.priority_high,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ESTATUS FAMILIAR',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSolvente
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      isSolvente ? 'SOLVENTE' : 'PENDIENTE DE PAGO',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isSolvente
                            ? const Color(0xFF166534)
                            : const Color(0xFF92400E),
                      ),
                    ),
                    if (compact) ...[const SizedBox(height: 2), detail],
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth * 0.4),
                  child: detail,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- TARJETA DE SALDOS DINÁMICOS EN MULTIMONEDA (HU7) ---
  Widget _buildNextPaymentCard() {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 560;
        final usdSize = compact ? 28.0 : 32.0;
        final vesSize = compact ? 24.0 : 28.0;

        final usdBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SALDO EN USD',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _estadoCuenta == null
                    ? '—'
                    : '\$${_montoUsd.toStringAsFixed(2).replaceAll('.', ',')}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: usdSize,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Text(
              'USD',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        );

        final vesBlock = Column(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            const Text(
              'EQUIVALENTE EN VES',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: compact ? Alignment.centerLeft : Alignment.centerRight,
              child: Text(
                _estadoCuenta == null
                    ? '—'
                    : 'Bs. ${_equivalenteVes.toStringAsFixed(2).replaceAll('.', ',')}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: vesSize,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Text(
              'A la Tasa BCV Oficial',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        );

        final approx = Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Text(
            '≈',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

        final divider = Expanded(
          child: Container(height: 1, color: Colors.white12),
        );

        return Container(
          padding: EdgeInsets.all(compact ? 18 : 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A8A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedStudentIndex == -1
                          ? 'Total global adeudado (familia)'
                          : 'Estado de cuenta / Saldo pendiente',
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'PERÍODO ACTUAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 16 : 20),
              if (compact) ...[
                usdBlock,
                const SizedBox(height: 14),
                Row(
                  children: [
                    divider,
                    const SizedBox(width: 10),
                    approx,
                    const SizedBox(width: 10),
                    divider,
                  ],
                ),
                const SizedBox(height: 14),
                vesBlock,
              ] else
                Row(
                  children: [
                    Expanded(child: usdBlock),
                    const SizedBox(width: 12),
                    approx,
                    const SizedBox(width: 12),
                    Expanded(child: vesBlock),
                  ],
                ),
              SizedBox(height: compact ? 16 : 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF34D399),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Tasa BCV oficial:',
                          style: TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _tasaFechaLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '1 USD = $_tasaBcvStr VES',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmtUsd(double v) => '\$${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String _fmtFecha(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _buildEstadoCuentaErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No pudimos verificar tu estado de cuenta. Revisa tu conexión e intenta de nuevo.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF991B1B),
              ),
            ),
          ),
          TextButton(
            onPressed: _updateFinancialSummary,
            child: const Text('Reintentar'),
          ),
        ],
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
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
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          if (estado.creditoUsd > kToleranciaSaldoUsd)
            _buildInfoStrip(
              Icons.savings_outlined,
              const Color(0xFFF0FDF4),
              const Color(0xFFBBF7D0),
              const Color(0xFF166534),
              'Saldo a favor: ${_fmtUsd(estado.creditoUsd)}. Se aplicará automáticamente a tu próxima cuota.',
            ),
          if (estado.enRevisionUsd > kToleranciaSaldoUsd)
            _buildInfoStrip(
              Icons.hourglass_top,
              const Color(0xFFEFF6FF),
              const Color(0xFFBFDBFE),
              const Color(0xFF1D4ED8),
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
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCuotaRow(CuotaEstadoCuenta c, {String? alumno}) {
    final (Color bg, Color fg) = switch (c.estado) {
      'VENCIDO' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      'PARCIAL' => (const Color(0xFFFEF3C7), const Color(0xFFB45309)),
      _ => (const Color(0xFFEFF6FF), AppColors.primaryBlue),
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
                    fontSize: 11,
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
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  c.estado,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final primary = ElevatedButton.icon(
      onPressed: () => _showReportPaymentModal(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      icon: const Icon(Icons.upload, size: 18),
      label: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              'Reportar pago multimoneda',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          SizedBox(width: 8),
          Icon(Icons.arrow_forward, size: 16),
        ],
      ),
    );

    final secondary = OutlinedButton.icon(
      // TODO: generar el QR real. El bloqueo definitivo debe validarse en el
      // servidor (mi_familia_solvente()); deshabilitar el botón es solo UX.
      onPressed: _isSolventeFamiliar ? () {} : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.darkNavy,
        side: const BorderSide(color: AppColors.cardBorder),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.qr_code, size: 18),
      label: const Text(
        'Generar pase digital (Código QR)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 12), secondary],
          );
        }
        return Row(
          children: [
            Expanded(flex: 6, child: primary),
            const SizedBox(width: 12),
            Expanded(flex: 5, child: secondary),
          ],
        );
      },
    );
  }

  Widget _buildRecentActivitySection() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Actividad reciente',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pagos y documentos de $activeStudentFirstName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'Ver todo',
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildActivityItem(
            Icons.check,
            const Color(0xFFDCFCE7),
            const Color(0xFF166534),
            'Mensualidad Febrero',
            '\$45,00 • Verificado',
            '28 feb',
          ),
          const Divider(height: 8, color: AppColors.cardBorder),
          _buildActivityItem(
            Icons.description_outlined,
            const Color(0xFFDCFCE7),
            const Color(0xFF166534),
            'Solvencia emitida',
            'Documento PDF',
            '28 feb',
          ),
          const Divider(height: 8, color: AppColors.cardBorder),
          _buildActivityItem(
            Icons.access_time,
            const Color(0xFFFEF3C7),
            const Color(0xFFB45309),
            'Actividad cultural',
            '\$12,00 • En revisión',
            '17 mar',
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(
    IconData icon,
    Color iconBg,
    Color iconColor,
    String title,
    String subtitle,
    String date,
  ) {
    return HoverTint(
      borderRadius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: _activityRow(icon, iconBg, iconColor, title, subtitle, date),
    );
  }

  Widget _activityRow(
    IconData icon,
    Color iconBg,
    Color iconColor,
    String title,
    String subtitle,
    String date,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.darkNavy,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          date,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
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
                        fontSize: 9,
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
                        fontSize: 11,
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
                subtitle: 'Programación académica Lapso II',
                statusTagText: 'Disponible',
                statusTagBg: const Color(0xFFDCFCE7),
                statusTagTextColor: const Color(0xFF166534),
                buttonText: 'Descargar PDF',
                buttonIcon: Icons.download_outlined,
                isLocked: false,
              ),
              _buildDocCard(
                badgeText: 'PDF',
                badgeColor: const Color(0xFFF1F5F9),
                badgeTextColor: AppColors.textMuted,
                title: 'Boletín Digital de Calificaciones',
                subtitle: 'Resultados académicos Lapso II',
                statusTagText: _isSolventeFamiliar
                    ? 'Tratamiento administrativo pendiente'
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
                subtitle: 'Período escolar 2025-2026',
                statusTagText: _isSolventeFamiliar
                    ? 'Solvencia activa'
                    : 'Requiere solvencia activa',
                statusTagBg: _isSolventeFamiliar
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEE2E2),
                statusTagTextColor: _isSolventeFamiliar
                    ? const Color(0xFF166534)
                    : const Color(0xFFDC2626),
                buttonText: _isSolventeFamiliar ? 'Descargar PDF' : 'Bloqueado',
                buttonIcon: _isSolventeFamiliar
                    ? Icons.download_outlined
                    : Icons.lock_outline,
                isLocked: !_isSolventeFamiliar,
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
                fontSize: 10,
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
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
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
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isLocked ? null : () {},
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
                  fontSize: 11,
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
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    Text(
                      'El acceso a clases, evaluaciones y actividades académicas está garantizado conforme a la LOPNNA.',
                      style: TextStyle(fontSize: 10, color: AppColors.darkNavy),
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
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
