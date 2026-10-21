import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

const _kCedPrefixes = {
  'V-': 'Venezolano',
  'E-': 'Extranjero',
  'J-': 'Jurídico',
  'P-': 'Pasaporte',
};

class _RegisterScreenState extends State<RegisterScreen> {
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  // Paso 1: Cédula y FocusNode
  final _cedulaController = TextEditingController();
  final _cedulaFocusNode = FocusNode();
  String _selectedPrefix = 'V-';

  // Regex de validación reutilizables
  static final RegExp _emailRegex = RegExp(
    r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$',
  );
  static final RegExp _onlyDigitsRegex = RegExp(r'^\d+$');
  static final RegExp _phoneRegex = RegExp(r'^\d{10}$');

  // Estados de control
  int _currentStep = 1;
  bool _cedulaError = false;
  bool _cedulaYaRegistrada = false;
  String? _colegioId;
  bool _isLoading = false;
  bool _termsAccepted = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Contraseña: causa concreta de rechazo
  bool _showPasswordErrors = false;
  String? _passwordServerError;
  bool _isLogoHovered = false;

  // Paso 2: Inputs y FocusNodes para navegación con Enter
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _nombresFocusNode = FocusNode();
  final _apellidosFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  /// Cédula en el formato guardado en la base: letra, guion y solo números.
  String get _cedulaNormalizada =>
      '$_selectedPrefix${_cedulaController.text.replaceAll(RegExp(r'[^0-9]'), '')}';

  /// Teléfono en formato E.164 (+58XXXXXXXXXX), el que usa el bot de WhatsApp.
  String get _telefonoE164 {
    var d = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('0')) d = d.substring(1);
    return '+58$d';
  }

  @override
  void dispose() {
    _cedulaController.dispose();
    _cedulaFocusNode.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nombresFocusNode.dispose();
    _apellidosFocusNode.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : AppColors.successGreen,
      ),
    );
  }

  // --- VALIDAR CÉDULA (llama a la función segura de Supabase)
  Future<void> validateCedula() async {
    if (!_step1FormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _cedulaError = false;
      _cedulaYaRegistrada = false;
    });

    try {
      final res = await supabase.rpc(
        'verificar_cedula_representante',
        params: {'p_cedula': _cedulaNormalizada},
      );
      final data = res as Map<String, dynamic>;
      if (!mounted) return;

      switch (data['estado'] as String) {
        case 'disponible':
          setState(() {
            _colegioId = data['colegio_id'] as String?;
            _currentStep = 2;
            _isLoading = false;
          });
          break;

        case 'ya_registrada':
          setState(() {
            _cedulaYaRegistrada = true;
            _isLoading = false;
          });
          break;

        case 'colegio_requerido':
          setState(() => _isLoading = false);
          _showSnack(
            'Tu cédula figura en más de una institución. Comunícate con la administración.',
          );
          break;

        default:
          setState(() {
            _cedulaError = true;
            _isLoading = false;
          });
      }
    } on PostgrestException {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('No pudimos validar la cédula. Intenta de nuevo.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('validateCedula error: $e');
      _showSnack('Ocurrió un error inesperado. Intenta de nuevo.');
    }
  }

  // --- CREAR CUENTA EN SUPABASE AUTH
  Future<void> submitRegistration() async {
    if (!_termsAccepted) {
      _showSnack('Debes aceptar los términos y condiciones para continuar.');
      return;
    }

    if (!_step2FormKey.currentState!.validate()) {
      setState(() => _showPasswordErrors = true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'nombre_completo':
              '${_nombresController.text.trim()} ${_apellidosController.text.trim()}',
          'nombres': _nombresController.text.trim(),
          'apellidos': _apellidosController.text.trim(),
          'telefono_whatsapp': _telefonoE164,
          'cedula': _cedulaNormalizada,
          'colegio_id': _colegioId,
        },
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      final user = authResponse.user;

      final bool emailYaRegistrado =
          user != null && (user.identities?.isEmpty ?? false);

      if (emailYaRegistrado) {
        _showSnack(
          'Este correo ya está asociado a una cuenta. Inicia sesión o recupera tu contraseña.',
        );
        return;
      }

      if (user != null) {
        _passwordController.clear();
        _confirmPasswordController.clear();
        _showPendingVerificationModal();
      } else {
        _showSnack('No pudimos crear la cuenta. Intenta de nuevo.');
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      final reason = _passwordServerReason(e.message);
      if (reason != null) {
        setState(() {
          _passwordServerError = reason;
          _showPasswordErrors = true;
        });
        _step2FormKey.currentState?.validate();
        _showSnack(reason);
        return;
      }
      _showSnack(
        e.message.contains('Database error')
            ? 'No pudimos crear la cuenta con esa cédula. Es posible que ya esté registrada; intenta iniciar sesión.'
            : e.message,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      debugPrint('submitRegistration error: $e');
      _showSnack('Ocurrió un error inesperado. Intenta de nuevo.');
    }
  }

  Future<void> _contactSupport() async {
    _showSnack(
      'Escribe a soporte@edupago.com o contacta a la administración de tu institución.',
      isError: false,
    );
  }

  // --- MODAL DE VERIFICACIÓN PENDIENTE
  void _showPendingVerificationModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.mail_outline,
                    color: Color(0xFFD97706),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'PENDIENTE VERIFICACIÓN',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Confirma tu correo electrónico',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
                const SizedBox(height: 10),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(
                        text: 'Hemos enviado un enlace de confirmación a\n',
                      ),
                      TextSpan(
                        text: _emailController.text,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const TextSpan(
                        text:
                            '.\nPor favor, abre tu correo para activar tu cuenta.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'El enlace expira en 15 minutos',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF92400E),
                              ),
                            ),
                            Text(
                              'Revisa también tu carpeta de correo no deseado (Spam).',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Entendido, ir a Iniciar Sesión',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showExpiredTokenModal();
                  },
                  child: const Text(
                    'Ver estado de enlace expirado / Reenviar',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- MODAL DE TOKEN EXPIRADO / REENVIAR
  void _showExpiredTokenModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.access_time,
                    color: Color(0xFFD97706),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'TOKEN EXPIRADO',
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'El enlace de confirmación ha\nexpirado',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Por seguridad, los enlaces solo son válidos durante 15 minutos.\nSolicita uno nuevo para continuar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enlace vencido',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF92400E),
                              ),
                            ),
                            Text(
                              'Tu cuenta todavía no ha sido activada.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      try {
                        await supabase.auth.resend(
                          type: OtpType.signup,
                          email: _emailController.text.trim(),
                        );
                        if (mounted) {
                          _showPendingVerificationModal();
                        }
                      } on AuthException catch (e) {
                        _showSnack(e.message);
                      } catch (e) {
                        debugPrint('resend error: $e');
                        _showSnack(
                          'No pudimos reenviar el correo. Intenta de nuevo.',
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Reenviar Correo de Verificación',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
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

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          if (isDesktop)
            Expanded(
              flex: 5,
              child: Container(
                color: AppColors.darkNavy,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.15,
                        child: Image.asset(
                          'assets/images/register_img1.webp',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(60.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          MouseRegion(
                            onEnter: (_) =>
                                setState(() => _isLogoHovered = true),
                            onExit: (_) =>
                                setState(() => _isLogoHovered = false),
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: AnimatedScale(
                                scale: _isLogoHovered ? 1.05 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withValues(
                                              alpha: _isLogoHovered
                                                  ? 0.22
                                                  : 0.15,
                                            ),
                                            AppColors.primaryBlue.withValues(
                                              alpha: _isLogoHovered
                                                  ? 0.55
                                                  : 0.4,
                                            ),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: _isLogoHovered ? 0.35 : 0.2,
                                          ),
                                        ),
                                      ),
                                      child: Image.asset(
                                        'assets/images/logo_edupago.png',
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontFamily: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.fontFamily,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.5,
                                          decoration: TextDecoration.none,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: 'Edu',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          TextSpan(
                                            text: 'Pago',
                                            style: TextStyle(
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
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Registrate Ahora!',
                                style: TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontSize: 48,
                                  height: 0.8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 22),
                              const Text(
                                '¿Tu familia ya forma parte de\nnuestra comunidad?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Activa tu acceso con la cédula previamente registrada por la\ninstitución y gestiona todo desde un solo lugar.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 32),
                              _buildFeatureItem(
                                Icons.verified_user_outlined,
                                'Identidad pre-validada',
                              ),
                              _buildFeatureItem(
                                Icons.people_outline,
                                'Hijos vinculados automáticamente',
                              ),
                              _buildFeatureItem(
                                Icons.lock_outline,
                                'Acceso seguro y privado',
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                color: Colors.white54,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Protección de datos y acceso basado en identidad',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          label: const Text(
                            'Volver al inicio',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      if (_currentStep == 1) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Formulario de Registro',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryBlue,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const LoginScreen(),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    color: Colors.transparent,
                                    child: const Center(
                                      child: Text(
                                        'Iniciar Sesión',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      if (_currentStep == 1)
                        _buildStep1Widget()
                      else
                        _buildStep2Widget(),
                      const SizedBox(height: 36),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 13,
                                color: AppColors.textMuted,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Conexión Encriptada TLS 1.3',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(width: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 13,
                                color: AppColors.textMuted,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Datos protegidos',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1Widget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PASO 1 DE 2',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Activa tu cuenta familiar',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Primero verificaremos que estés registrado como representante en la institución.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        Form(
          key: _step1FormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cédula de Identidad del Representante',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 8),
              _CedulaField(
                controller: _cedulaController,
                focusNode: _cedulaFocusNode,
                prefix: _selectedPrefix,
                onPrefixChanged: (p) {
                  setState(() {
                    _selectedPrefix = p;
                    if (p != 'J-') {
                      _cedulaController.text = _cedulaController.text
                          .replaceAll(RegExp(r'\D'), '');
                    }
                    _cedulaError = false;
                    _cedulaYaRegistrada = false;
                  });
                },
                onChanged: (_) {
                  if (_cedulaError || _cedulaYaRegistrada) {
                    setState(() {
                      _cedulaError = false;
                      _cedulaYaRegistrada = false;
                    });
                  }
                },
                onSubmitted: () => validateCedula(),
                validator: (val) {
                  final cleaned = val?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa tu número de cédula';
                  }
                  if (!_onlyDigitsRegex.hasMatch(cleaned) ||
                      cleaned.length < 6 ||
                      cleaned.length > 9) {
                    return 'Cédula inválida (solo números, 6-9 dígitos)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              const Text(
                'Debe coincidir con la cédula registrada en el expediente escolar.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              if (_cedulaError) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.close, color: Color(0xFFDC2626), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cédula no registrada',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF991B1B),
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Su Cédula de Identidad no se encuentra registrada como representante en la institución. Por favor, comuníquese con el Departamento de Administración.',
                              style: TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_cedulaYaRegistrada) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.primaryBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ya existe una cuenta con esta cédula',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Esta cédula ya está asociada a una cuenta. Inicia sesión; si no recuerdas tu contraseña, puedes recuperarla desde esa pantalla.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                              ),
                              child: const Text(
                                'Ir a Iniciar Sesión',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : validateCedula,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Validar Cédula e Iniciar Registro',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                ),
              ),
              if (_cedulaError) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _contactSupport,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.people_outline, size: 18),
                    label: const Text(
                      'Contactar a Administración / Soporte',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Widget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PASO 2 DE 2',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.primaryBlue,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Completa tus datos',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tu identidad fue confirmada. Crea tus credenciales de acceso.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  color: AppColors.successGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cédula verificada en la base de datos del colegio',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF166534),
                      ),
                    ),
                    Text(
                      '$_cedulaNormalizada · Representante pre-registrado',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _currentStep = 1;
                  });
                },
                child: const Text(
                  'Cambiar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Form(
          key: _step2FormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nombres',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkNavy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nombresController,
                          focusNode: _nombresFocusNode,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) {
                            FocusScope.of(
                              context,
                            ).requestFocus(_apellidosFocusNode);
                          },
                          decoration: _buildInputDecoration(
                            'Nombres',
                            Icons.person_outline,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Requerido';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Apellidos',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkNavy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _apellidosController,
                          focusNode: _apellidosFocusNode,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) {
                            FocusScope.of(
                              context,
                            ).requestFocus(_emailFocusNode);
                          },
                          decoration: _buildInputDecoration(
                            'Apellidos',
                            Icons.person_outline,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Requerido';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Correo electrónico',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) {
                  FocusScope.of(context).requestFocus(_phoneFocusNode);
                },
                decoration: _buildInputDecoration(
                  'nombre@correo.com',
                  Icons.email_outlined,
                ),
                validator: (val) {
                  final v = val?.trim() ?? '';
                  if (v.isEmpty) return 'Ingresa tu correo';
                  if (!_emailRegex.hasMatch(v)) return 'Correo no válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Número de teléfono',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) {
                  FocusScope.of(context).requestFocus(_passwordFocusNode);
                },
                decoration: InputDecoration(
                  hintText: '412 555 0174',
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                  prefixIcon: Container(
                    width: 50,
                    alignment: Alignment.center,
                    child: const Text(
                      '+58',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 1.5,
                    ),
                  ),
                ),
                validator: (val) {
                  var cleaned = val?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
                  if (cleaned.startsWith('0')) cleaned = cleaned.substring(1);
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa tu teléfono';
                  }
                  if (!_phoneRegex.hasMatch(cleaned)) {
                    return 'Teléfono inválido. Ejemplo: 412 555 0174';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contraseña',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkNavy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) =>
                              setState(() => _passwordServerError = null),
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) {
                            FocusScope.of(
                              context,
                            ).requestFocus(_confirmPasswordFocusNode);
                          },
                          decoration: _buildInputDecoration(
                            'Crea una contraseña',
                            Icons.lock_outline,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: _validatePassword,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Confirmar contraseña',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkNavy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _confirmPasswordController,
                          focusNode: _confirmPasswordFocusNode,
                          obscureText: _obscureConfirmPassword,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => submitRegistration(),
                          decoration: _buildInputDecoration(
                            'Repetir contraseña',
                            Icons.lock_outline,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                            ),
                          ),
                          validator: (val) {
                            if (val != _passwordController.text) {
                              return 'No coinciden';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildPasswordChecklist(),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _termsAccepted,
                      activeColor: AppColors.primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (val) =>
                          setState(() => _termsAccepted = val ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Acepto los términos del servicio y el tratamiento seguro de mis datos.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : submitRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Crear Cuenta y Enviar Correo de Confirmación',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
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

  // ---------------------------------------------------------------------
  // CONTRASEÑA SEGURA
  // ---------------------------------------------------------------------
  static final RegExp _hasUpper = RegExp(r'[A-Z]');
  static final RegExp _hasLower = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');
  static final RegExp _hasSymbol = RegExp(
    r'''[!@#$%^&*()_+\-=\[\]{};':"\\|<>?,./`~]''',
  );

  List<_PwRule> _passwordRulesFor(String p) => [
    _PwRule('Mínimo 8 caracteres', 'mínimo 8 caracteres', p.length >= 8),
    _PwRule('Una mayúscula (A-Z)', 'una mayúscula', _hasUpper.hasMatch(p)),
    _PwRule('Una minúscula (a-z)', 'una minúscula', _hasLower.hasMatch(p)),
    _PwRule('Un número (0-9)', 'un número', _hasDigit.hasMatch(p)),
    _PwRule(
      'Un símbolo (! @ # \$ % & *)',
      'un símbolo',
      _hasSymbol.hasMatch(p),
    ),
  ];

  String? _validatePassword(String? val) {
    final p = val ?? '';
    if (p.isEmpty) return 'Ingresa una contraseña';
    final faltan = _passwordRulesFor(
      p,
    ).where((r) => !r.ok).map((r) => r.short).toList();
    if (faltan.isNotEmpty) return 'Falta: ${faltan.join(', ')}';
    return _passwordServerError;
  }

  String? _passwordServerReason(String message) {
    final m = message.toLowerCase();
    if (m.contains('known to be weak') ||
        m.contains('easy to guess') ||
        m.contains('pwned') ||
        m.contains('leaked')) {
      return 'Esa contraseña aparece en filtraciones de datos conocidas. Elige una distinta.';
    }
    if (m.contains('one character of each')) {
      return 'El servidor exige mayúscula, minúscula, número y símbolo en la contraseña.';
    }
    if (m.contains('at least') && m.contains('characters')) {
      return 'La contraseña es demasiado corta: el servidor exige más caracteres.';
    }
    if (m.contains('password')) {
      return 'El servidor rechazó la contraseña por no cumplir la política de seguridad.';
    }
    return null;
  }

  Widget _buildPasswordChecklist() {
    final p = _passwordController.text;
    final rules = _passwordRulesFor(p);
    final done = rules.where((r) => r.ok).length;
    const red = Color(0xFFDC2626);
    const green = Color(0xFF059669);

    final Color barColor;
    final String label;
    if (p.isEmpty) {
      barColor = AppColors.cardBorder;
      label = '';
    } else if (done <= 2) {
      barColor = red;
      label = 'Débil';
    } else if (done < rules.length) {
      barColor = const Color(0xFFD97706);
      label = 'Media';
    } else {
      barColor = green;
      label = 'Segura';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tu contraseña debe tener:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
              ),
              if (label.isNotEmpty)
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: barColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p.isEmpty ? 0 : done / rules.length,
              minHeight: 4,
              color: barColor,
              backgroundColor: const Color(0xFFE2E8F0),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              for (final r in rules)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      r.ok
                          ? Icons.check_circle
                          : (_showPasswordErrors
                                ? Icons.cancel
                                : Icons.radio_button_unchecked),
                      size: 14,
                      color: r.ok
                          ? green
                          : (_showPasswordErrors ? red : AppColors.textMuted),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      r.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: (!r.ok && _showPasswordErrors)
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: r.ok
                            ? const Color(0xFF166534)
                            : (_showPasswordErrors ? red : AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (_passwordServerError != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 14, color: red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _passwordServerError!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(
    String hint,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.textMuted, size: 18),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CedulaField extends StatelessWidget {
  final TextEditingController controller;
  final String prefix;
  final ValueChanged<String> onPrefixChanged;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;

  const _CedulaField({
    super.key,
    required this.controller,
    required this.prefix,
    required this.onPrefixChanged,
    this.focusNode,
    this.validator,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isJ = prefix == 'J-';

    return FormField<String>(
      validator: (_) => validator?.call(controller.text),
      builder: (FormFieldState<String> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: state.hasError
                      ? Colors.redAccent
                      : AppColors.cardBorder,
                  width: state.hasError ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  // Botón desplegable del prefijo anclado a la izquierda
                  PopupMenuButton<String>(
                    tooltip: 'Tipo de documento',
                    initialValue: prefix,
                    onSelected: (val) {
                      onPrefixChanged(val);
                      state.didChange(controller.text);
                    },
                    position: PopupMenuPosition.under,
                    offset: const Offset(114, 10),
                    color: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    elevation: 8,
                    constraints: const BoxConstraints(
                      minWidth: 180,
                      maxWidth: 220,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    itemBuilder: (_) => [
                      for (final e in _kCedPrefixes.entries)
                        PopupMenuItem<String>(
                          value: e.key,
                          height: 40,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: Text(
                                  e.key,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkNavy,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                e.value,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            prefix,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 22,
                            color: AppColors.cardBorder,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Campo de texto de la cédula
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.done,
                      keyboardType: isJ
                          ? TextInputType.text
                          : TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(isJ ? r'[0-9-]' : r'[0-9]'),
                        ),
                        LengthLimitingTextInputFormatter(12),
                      ],
                      onChanged: (val) {
                        state.didChange(val);
                        onChanged?.call(val);
                      },
                      onSubmitted: (_) => onSubmitted?.call(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.darkNavy,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Cédula *',
                        hintStyle: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Mensaje de validación de error si aplica
            if (state.hasError) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  state.errorText!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PwRule {
  final String label;
  final String short;
  final bool ok;
  const _PwRule(this.label, this.short, this.ok);
}
