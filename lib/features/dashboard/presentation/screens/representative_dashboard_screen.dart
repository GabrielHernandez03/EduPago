import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';
import '../../../landing/presentation/screens/home_screen.dart';
import '../widgets/edit_profile_dialog.dart';
import '../widgets/report_payment_dialog.dart';

class RepresentativeDashboardScreen extends StatefulWidget {
  const RepresentativeDashboardScreen({super.key});

  @override
  State<RepresentativeDashboardScreen> createState() =>
      _RepresentativeDashboardScreenState();
}

class _RepresentativeDashboardScreenState
    extends State<RepresentativeDashboardScreen> {
  final User? currentUser = supabase.auth.currentUser;
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
  String _initials = '..';

  // Lista dinámica de estudiantes asociados en Supabase
  List<Map<String, dynamic>> _students = [];
  int _selectedStudentIndex = 0;
  int _selectedNavIndex = 0;

  final String tasaBcv = '64,25';
  final double montoUsd = 45.00;
  final double equivalenteVes = 2891.25;

  @override
  void initState() {
    super.initState();
    _fetchUserProfileAndStudents();
  }

  // --- CONSULTA EN VIVO DEL PERFIL DEL REPRESENTANTE ---
  Future<void> _fetchUserProfileAndStudents() async {
    setState(() => _isLoadingProfile = true);
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final userEmail = user.email ?? '';
        final userCedula = user.userMetadata?['cedula']?.toString() ?? '';
        final userFullName = user.userMetadata?['nombre_completo']?.toString() ?? '';

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
              : (userFullName.isNotEmpty ? userFullName : userEmail.split('@')[0]);

          final fetchedCedula = (data['cedula'] != null && data['cedula'].toString().isNotEmpty)
              ? data['cedula'].toString()
              : (userCedula.isNotEmpty ? userCedula : 'Sin cédula');

          final fetchedEmail = (data['email'] != null && data['email'].toString().isNotEmpty)
              ? data['email'].toString()
              : userEmail;

          final fetchedPhone = data['telefono_whatsapp']?.toString() ?? '';
          final fetchedAddress = data['direccion']?.toString() ?? '';
          final fetchedFamily = (data['familia'] != null && data['familia'].toString().isNotEmpty)
              ? data['familia'].toString()
              : 'Familia ${_getLastName(fetchedName)}';

          _fullName = fetchedName;
          _cedula = fetchedCedula;
          _email = fetchedEmail;
          _phone = fetchedPhone;
          _address = fetchedAddress;
          _familyName = fetchedFamily;
          _initials = _getInitials(fetchedName);

          // 2. Cargar los estudiantes asociados a este representante
          if (_repDbId.isNotEmpty) {
            await _fetchAssociatedStudents(_repDbId);
          }
        } else {
          // Fallback para usuario autenticado que aún no tiene perfil guardado en representantes
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

  // --- CONSULTAR ÚNICAMENTE LOS ESTUDIANTES VINCULADOS A ESTE REPRESENTANTE ---
  Future<void> _fetchAssociatedStudents(String representanteId) async {
    try {
      // 1. Obtener las relaciones desde representante_estudiante
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
        // 2. Traer la información detallada de esos estudiantes específicos
        final studentsResponse = await supabase
            .from('estudiantes')
            .select()
            .filter('id', 'in', studentIds);

        final loadedStudents = List<Map<String, dynamic>>.from(studentsResponse);

        if (mounted) {
          setState(() {
            _students = loadedStudents;
            if (_selectedStudentIndex >= _students.length) {
              _selectedStudentIndex = 0;
            }
          });
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
    }
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
          onSaveSuccess: () => _fetchUserProfileAndStudents(),
        );
      },
    );
  }

  void _showReportPaymentModal(BuildContext context) {
    final activeStudentName = _students.isNotEmpty && _selectedStudentIndex < _students.length
        ? '${_students[_selectedStudentIndex]['nombres'] ?? ''} ${_students[_selectedStudentIndex]['apellidos'] ?? ''}'.trim()
        : 'Estudiante';

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return ReportPaymentDialog(
          studentName: activeStudentName,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading || _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                if (isDesktop) _buildSidebar(),
                Expanded(
                  child: Column(
                    children: [
                      _buildTopHeader(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 24,
                          ),
                          child: Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 1000),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRepresentativeHeaderCard(),
                                  const SizedBox(height: 24),
                                  _buildStudentsSection(),
                                  const SizedBox(height: 16),
                                  _buildAcademicStatusBanner(),
                                  const SizedBox(height: 16),
                                  _buildNextPaymentCard(),
                                  const SizedBox(height: 16),
                                  _buildActionButtons(),
                                  const SizedBox(height: 28),
                                  _buildRecentActivitySection(),
                                  const SizedBox(height: 28),
                                  _buildDigitalDocumentsSection(),
                                  const SizedBox(height: 24),
                                  _buildFooterSecurityNotice(),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.apartment,
                      color: AppColors.primaryBlue, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INSTITUCIÓN',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'U.E. Nueva Generación',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_right,
                    color: Colors.white54, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 28),
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

          _buildNavItem(0, Icons.home_outlined, Icons.home, 'Mi resumen'),
          _buildNavItem(1, Icons.account_balance_wallet_outlined,
              Icons.account_balance_wallet, 'Pagos'),
          _buildNavItem(
              2, Icons.verified_outlined, Icons.verified, 'Solvencias'),
          _buildNavItem(
              3, Icons.description_outlined, Icons.description, 'Documentos'),

          const Spacer(),

          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.white60, size: 18),
                  SizedBox(width: 12),
                  Text(
                    'Soporte y seguridad',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primaryBlue,
                child: Text(_initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fullName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text('Representante',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white54, size: 18),
                onPressed: _handleLogout,
                tooltip: 'Cerrar Sesión',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData icon, IconData activeIcon, String title) {
    final bool isSelected = _selectedNavIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => setState(() => _selectedNavIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E3A8A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(isSelected ? activeIcon : icon,
                  color: isSelected ? Colors.white : Colors.white60, size: 18),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: AppColors.textMuted, size: 18),
                  SizedBox(width: 8),
                  Text('Buscar pago, documento o referencia...',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.cardBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 14, color: AppColors.darkNavy),
                SizedBox(width: 8),
                Text('Período 2024–2025',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkNavy)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.notifications_none,
                    size: 18, color: AppColors.darkNavy),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: Colors.redAccent, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFDBEAFE),
            child: Text(_initials,
                style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildRepresentativeHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
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
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_cedula · $_familyName${_email.isNotEmpty ? ' · $_email' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
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
          ),
        ],
      ),
    );
  }

  // --- RENDEREIZADO DINÁMICO DE "MIS ESTUDIANTES" ---
  Widget _buildStudentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Mis estudiantes',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy)),
            Text('${_students.length} vinculados',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
                Text(
                  'No hay estudiantes asignados a este representante.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          )
        else
          Row(
            children: List.generate(_students.length, (index) {
              final student = _students[index];
              final String studentNombres = student['nombres'] ?? 'Estudiante';
              final String studentApellidos = student['apellidos'] ?? '';
              final String fullStudentName = '$studentNombres $studentApellidos'.trim();
              final String gradeSection = student['grado_seccion'] ?? 'Grado no especificado';
              final String initials = _getInitials(fullStudentName);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index < _students.length - 1 ? 12.0 : 0.0,
                  ),
                  child: _buildStudentTabCard(
                      index, initials, fullStudentName, gradeSection),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildStudentTabCard(
      int index, String initials, String name, String grade) {
    final bool isSelected = _selectedStudentIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedStudentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColors.primaryBlue : AppColors.cardBorder,
              width: isSelected ? 1.5 : 1),
        ),
        child: Row(
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
                child: Text(initials,
                    style: TextStyle(
                        color: isSelected
                            ? AppColors.primaryBlue
                            : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.darkNavy),
                      overflow: TextOverflow.ellipsis),
                  Text(grade,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, color: AppColors.primaryBlue, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAcademicStatusBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
                color: Color(0xFF16A34A), shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ESTATUS ACADÉMICO',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                      letterSpacing: 0.5)),
              Text('SOLVENTE',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF166534))),
            ],
          ),
          const Spacer(),
          const Text('Sin pagos vencidos',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16A34A))),
        ],
      ),
    );
  }

  Widget _buildNextPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Próxima mensualidad',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('MARZO 2025',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SALDO EN USD',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('\$${montoUsd.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800)),
                    const Text('USD',
                        style: TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: const Text('=',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('EQUIVALENTE EN VES',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        'Bs. ${equivalenteVes.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: Color(0xFF34D399), size: 14),
                    SizedBox(width: 6),
                    Text('Tasa BCV oficial',
                        style: TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    SizedBox(width: 10),
                    Text('Actualizada el 18/03/2025 - 08:00 AM',
                        style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
                Text('1 USD = $tasaBcv VES',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: ElevatedButton.icon(
            onPressed: () => _showReportPaymentModal(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            icon: const Icon(Icons.upload, size: 18),
            label: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Reportar pago multimoneda',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: OutlinedButton.icon(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkNavy,
              side: const BorderSide(color: AppColors.cardBorder),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.qr_code, size: 18),
            label: const Text('Generar pase digital (Código QR)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection() {
    final activeStudentFirstName = _students.isNotEmpty && _selectedStudentIndex < _students.length
        ? (_students[_selectedStudentIndex]['nombres']?.toString().split(' ')[0] ?? 'estudiante')
        : 'estudiante';

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Actividad reciente',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy)),
                  const SizedBox(height: 2),
                  Text('Pagos y documentos de $activeStudentFirstName',
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
              TextButton(
                onPressed: () {},
                child: const Text('Ver todo',
                    style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildActivityItem(Icons.check, const Color(0xFFDCFCE7),
              const Color(0xFF166534), 'Mensualidad · Febrero', '\$45,00 · Verificado', '28 feb'),
          const Divider(height: 20, color: AppColors.cardBorder),
          _buildActivityItem(Icons.description_outlined, const Color(0xFFDCFCE7),
              const Color(0xFF166534), 'Solvencia emitida', 'Documento PDF', '28 feb'),
          const Divider(height: 20, color: AppColors.cardBorder),
          _buildActivityItem(Icons.access_time, const Color(0xFFFEF3C7),
              const Color(0xFFB45309), 'Actividad cultural', '\$12,00 · En revisión', '17 mar'),
        ],
      ),
    );
  }

  Widget _buildActivityItem(IconData icon, Color iconBg, Color iconColor,
      String title, String subtitle, String date) {
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
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.darkNavy)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
        Text(date,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
      ],
    );
  }

  Widget _buildDigitalDocumentsSection() {
    final activeStudentFirstName = _students.isNotEmpty && _selectedStudentIndex < _students.length
        ? (_students[_selectedStudentIndex]['nombres']?.toString().split(' ')[0] ?? 'estudiante')
        : 'estudiante';

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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.description_outlined,
                    color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PORTAL ACADÉMICO',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                          letterSpacing: 0.5)),
                  const Text('Trámites Digitales y Documentación Académica',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy)),
                  const SizedBox(height: 2),
                  Text('Documentos asociados a $activeStudentFirstName',
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildDocCard(
                  badgeText: 'PDF',
                  badgeColor: const Color(0xFFFEE2E2),
                  badgeTextColor: const Color(0xFFDC2626),
                  title: 'Plan de Evaluación y Horarios',
                  subtitle: 'Programación académica · Lapso II',
                  statusTagText: 'Disponible',
                  statusTagBg: const Color(0xFFDCFCE7),
                  statusTagTextColor: const Color(0xFF166534),
                  buttonText: 'Descargar PDF',
                  buttonIcon: Icons.download_outlined,
                  isLocked: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDocCard(
                  badgeText: '🔒',
                  badgeColor: const Color(0xFFF1F5F9),
                  badgeTextColor: AppColors.textMuted,
                  title: 'Boletín Digital de Calificaciones PDF',
                  subtitle: 'Resultados académicos · Lapso II',
                  statusTagText: 'Tratamiento administrativo pendiente',
                  statusTagBg: const Color(0xFFFEF3C7),
                  statusTagTextColor: const Color(0xFFB45309),
                  buttonText: 'No disponible',
                  buttonIcon: Icons.lock_outline,
                  isLocked: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDocCard(
                  badgeText: '🔒',
                  badgeColor: const Color(0xFFF1F5F9),
                  badgeTextColor: AppColors.textMuted,
                  title: 'Planilla de Reinscripción y Reserva de Cupo',
                  subtitle: 'Período escolar 2025-2026',
                  statusTagText: 'Requiere solvencia activa',
                  statusTagBg: const Color(0xFFFEE2E2),
                  statusTagTextColor: const Color(0xFFDC2626),
                  buttonText: 'Bloqueado',
                  buttonIcon: Icons.lock_outline,
                  isLocked: true,
                ),
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
                color: badgeColor, borderRadius: BorderRadius.circular(6)),
            child: Text(badgeText,
                style: TextStyle(
                    color: badgeTextColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.darkNavy),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style:
                  const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: statusTagBg, borderRadius: BorderRadius.circular(12)),
            child: Text(statusTagText,
                style: TextStyle(
                    color: statusTagTextColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
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
                    color: isLocked ? Colors.transparent : AppColors.cardBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(buttonIcon, size: 14),
              label: Text(buttonText,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold)),
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
          child: Row(
            children: const [
              Icon(Icons.shield_outlined,
                  color: AppColors.primaryBlue, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Protección integral del estudiante',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue)),
                    Text(
                        'El acceso a clases, evaluaciones y actividades académicas está garantizado conforme a la LOPNNA.',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.darkNavy)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 13, color: AppColors.textMuted),
            SizedBox(width: 6),
            Text(
                'Tus pagos están protegidos y serán verificados por la institución.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }
}