import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';
import '../widgets/auth_shared_widgets.dart';
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
  // Correo: acepta cualquier formato real (RFC 5322 práctico): letras, números
  // y símbolos habituales (. _ % + - ...) antes de la @, y dominios con uno o
  // varios subdominios (gmail.com, correo.unimet.edu.ve, mail.empresa.com.ve).
  static final RegExp _emailRegex = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
    r"@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
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

  // Errores del servidor, mostrados en el campo al que corresponden
  String? _cedulaCustomError;
  String? _emailServerError;
  String? _formError; // errores generales -> aviso sobre el botón
  bool _termsError = false;

  // Pestaña superior (0 = Registro, 1 = Iniciar sesión)
  int _authTab = 0;
  bool _leavingToLogin = false;

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
  void initState() {
    super.initState();
    // El checklist de la contraseña solo se ve mientras el campo tiene foco.
    _passwordFocusNode.addListener(_onPasswordFocusChanged);
  }

  void _onPasswordFocusChanged() {
    if (!mounted) return;
    setState(() {
      // Al salir con la contraseña a medias, las reglas pendientes se marcan.
      if (!_passwordFocusNode.hasFocus && _passwordController.text.isNotEmpty) {
        _showPasswordErrors = true;
      }
    });
  }

  /// Mensaje de error de la cédula (si lo hay), mostrado dentro del campo.
  String? get _cedulaServerError {
    if (_cedulaError) {
      return 'Esta cédula no está registrada como representante en la institución.';
    }
    if (_cedulaYaRegistrada) return 'Ya existe una cuenta con esta cédula.';
    return _cedulaCustomError;
  }

  @override
  void dispose() {
    _passwordFocusNode.removeListener(_onPasswordFocusChanged);
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
      _cedulaCustomError = null;
      _formError = null;
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
            _formError = null;
            _termsError = false;
          });
          break;

        case 'ya_registrada':
          setState(() {
            _cedulaYaRegistrada = true;
            _isLoading = false;
          });
          break;

        case 'colegio_requerido':
          setState(() {
            _cedulaCustomError =
                'Tu cédula figura en más de una institución. Comunícate con la administración.';
            _isLoading = false;
          });
          break;

        default:
          setState(() {
            _cedulaError = true;
            _isLoading = false;
          });
      }
    } on PostgrestException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _formError = 'No pudimos validar la cédula. Intenta de nuevo.';
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('validateCedula error: $e');
      setState(() {
        _isLoading = false;
        _formError = 'Ocurrió un error inesperado. Intenta de nuevo.';
      });
    }
  }

  // --- CREAR CUENTA EN SUPABASE AUTH
  Future<void> submitRegistration() async {
    if (_isLoading) return;
    setState(() {
      _formError = null;
      _emailServerError = null;
      _passwordServerError = null;
    });
    // Espera a que los campos se reconstruyan sin los errores viejos del
    // servidor; si no, validate() los vería como si fueran actuales.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final bool formOk = _step2FormKey.currentState!.validate();
    if (!_termsAccepted) setState(() => _termsError = true);

    if (!formOk || !_termsAccepted) {
      setState(() => _showPasswordErrors = true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
        // Llega a la plantilla del correo como {{ .RedirectTo }}: el enlace
        // abre la app aquí y se muestra la pantalla "Correo confirmado".
        // Debe estar en Authentication > URL Configuration > Redirect URLs.
        emailRedirectTo: kIsWeb ? '${Uri.base.origin}/' : null,
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

      final user = authResponse.user;

      final bool emailYaRegistrado =
          user != null && (user.identities?.isEmpty ?? false);

      if (emailYaRegistrado) {
        setState(() {
          _isLoading = false;
          _emailServerError =
              'Este correo ya está asociado a una cuenta. Inicia sesión o recupera tu contraseña.';
        });
        return;
      }

      if (user != null) {
        setState(() => _isLoading = false);
        _passwordController.clear();
        _confirmPasswordController.clear();
        _showPendingVerificationModal();
      } else {
        setState(() {
          _isLoading = false;
          _formError = 'No pudimos crear la cuenta. Intenta de nuevo.';
        });
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      final reason = _passwordServerReason(e.message);

      setState(() {
        _isLoading = false;
        if (reason != null) {
          // Error de contraseña -> en el campo de contraseña
          _passwordServerError = reason;
          _showPasswordErrors = true;
        } else if (m.contains('already registered') ||
            m.contains('already been registered')) {
          // Correo repetido -> en el campo de correo
          _emailServerError =
              'Este correo ya está asociado a una cuenta. Inicia sesión o recupera tu contraseña.';
        } else if (e.message.contains('Database error')) {
          _formError =
              'No pudimos crear la cuenta con esa cédula. Es posible que ya esté registrada; intenta iniciar sesión.';
        } else {
          _formError = e.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('submitRegistration error: $e');
      setState(() {
        _isLoading = false;
        _formError = 'Ocurrió un error inesperado. Intenta de nuevo.';
      });
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

  // Deja que la pastilla termine de deslizarse y luego pasa a Login con fundido.
  void _onAuthTabChanged(int index) {
    if (index == 0 || _leavingToLogin) return;
    _leavingToLogin = true;
    setState(() => _authTab = 1);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, authFadeRoute(const LoginScreen()));
    });
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
              child: AuthBrandPanel(
                imageAsset: 'assets/images/register_img1.webp',
                onLogoTap: () => Navigator.pop(context),
                headline: 'Registrate Ahora!',
                subtitle: '¿Tu familia ya forma parte de\nnuestra comunidad?',
                description:
                    'Activa tu acceso con la cédula previamente registrada por la institución y gestiona todo desde un solo lugar.',
                features: const [
                  AuthFeature(
                    Icons.verified_user_outlined,
                    'Identidad pre-validada',
                  ),
                  AuthFeature(
                    Icons.people_outline,
                    'Hijos vinculados automáticamente',
                  ),
                  AuthFeature(Icons.lock_outline, 'Acceso seguro y privado'),
                ],
                footnote: 'Protección de datos y acceso basado en identidad',
              ),
            ),
          Expanded(
            flex: 5,
            child: AuthFormPanel(
              isDesktop: isDesktop,
              onBack: () => Navigator.pop(context),
              // La altura de la tarjeta la anima AuthFormPanel; aquí solo el
              // fundido + desplazamiento entre pasos.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, if (current != null) current],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.03, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey<int>(_currentStep),
                  child: _buildStepContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Contenido de la tarjeta según el paso actual.
  Widget _buildStepContent() {
    if (_currentStep != 1) return _buildStep2Widget();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AuthSegmentedSelector(
          segments: const [
            AuthSegment(
              label: 'Formulario de Registro',
              color: AppColors.primaryBlue,
            ),
            AuthSegment(label: 'Iniciar Sesión', color: AppColors.primaryBlue),
          ],
          selectedIndex: _authTab,
          onChanged: _onAuthTabChanged,
        ),
        const SizedBox(height: 28),
        _buildStep1Widget(),
      ],
    );
  }

  // Enlace de acción pequeño bajo un campo con error
  Widget _inlineLink(String text, VoidCallback onTap, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: AppColors.primaryBlue),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ),
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
        const SizedBox(height: 22),
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
                helperText:
                    'Debe coincidir con la cédula registrada en el expediente escolar.',
                serverError: _cedulaServerError,
                onPrefixChanged: (p) {
                  setState(() {
                    _selectedPrefix = p;
                    if (p != 'J-') {
                      _cedulaController.text = _cedulaController.text
                          .replaceAll(RegExp(r'\D'), '');
                    }
                    _cedulaError = false;
                    _cedulaYaRegistrada = false;
                    _cedulaCustomError = null;
                  });
                },
                onChanged: (_) {
                  if (_cedulaError ||
                      _cedulaYaRegistrada ||
                      _cedulaCustomError != null ||
                      _formError != null) {
                    setState(() {
                      _cedulaError = false;
                      _cedulaYaRegistrada = false;
                      _cedulaCustomError = null;
                      _formError = null;
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
              if (_cedulaError)
                _inlineLink(
                  'Contactar a Administración / Soporte',
                  _contactSupport,
                  icon: Icons.support_agent_outlined,
                ),
              if (_cedulaYaRegistrada)
                _inlineLink(
                  'Ir a Iniciar Sesión',
                  () => Navigator.pushReplacement(
                    context,
                    authFadeRoute(const LoginScreen()),
                  ),
                  icon: Icons.login,
                ),
              if (_formError != null) ...[
                const SizedBox(height: 14),
                AuthErrorBanner(message: _formError!),
              ],
              const SizedBox(height: 18),
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
            ],
          ),
        ),
      ],
    );
  }

  // Dos campos en fila (como antes); solo en pantallas angostas se apilan.
  Widget _pair(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
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
                    _formError = null;
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
          onChanged: () {
            if (_formError != null) setState(() => _formError = null);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pair(
                AuthTextField(
                  compact: true,
                  controller: _nombresController,
                  focusNode: _nombresFocusNode,
                  label: 'Nombres',
                  hint: 'Nombres',
                  icon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_apellidosFocusNode),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Ingresa tus nombres'
                      : null,
                ),
                AuthTextField(
                  compact: true,
                  controller: _apellidosController,
                  focusNode: _apellidosFocusNode,
                  label: 'Apellidos',
                  hint: 'Apellidos',
                  icon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_emailFocusNode),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Ingresa tus apellidos'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              AuthTextField(
                compact: true,
                controller: _emailController,
                focusNode: _emailFocusNode,
                label: 'Correo electrónico',
                hint: 'nombre@correo.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(_phoneFocusNode),
                serverError: _emailServerError,
                onChanged: (_) {
                  if (_emailServerError != null) {
                    setState(() => _emailServerError = null);
                  }
                },
                validator: (val) {
                  final v = val?.trim() ?? '';
                  if (v.isEmpty) return 'Ingresa tu correo';
                  if (v.length > 254 || !_emailRegex.hasMatch(v)) {
                    return 'Correo no válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AuthTextField(
                compact: true,
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                label: 'Número de teléfono',
                hint: '412 555 0174',
                prefix: Container(
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
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(_passwordFocusNode),
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
              _pair(
                AuthTextField(
                  compact: true,
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  label: 'Contraseña',
                  hint: 'Crea una contraseña',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(
                    context,
                  ).requestFocus(_confirmPasswordFocusNode),
                  // Refresca el checklist en vivo y limpia el error del servidor
                  onChanged: (_) => setState(() => _passwordServerError = null),
                  serverError: _passwordServerError,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: _validatePassword,
                ),
                AuthTextField(
                  compact: true,
                  controller: _confirmPasswordController,
                  focusNode: _confirmPasswordFocusNode,
                  label: 'Confirmar contraseña',
                  hint: 'Repetir contraseña',
                  icon: Icons.lock_outline,
                  obscureText: _obscureConfirmPassword,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => submitRegistration(),
                  // Si cambia la contraseña, se re-evalúa "no coinciden"
                  revalidateWhen: _passwordController,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Confirma tu contraseña';
                    }
                    if (val != _passwordController.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
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
                      side: _termsError
                          ? const BorderSide(color: kAuthError, width: 2)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (val) => setState(() {
                        _termsAccepted = val ?? false;
                        if (_termsAccepted) _termsError = false;
                      }),
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
              if (_termsError)
                const AuthFieldError(
                  'Debes aceptar los términos para continuar.',
                  left: 28,
                ),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                AuthErrorBanner(message: _formError!),
              ],
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
    return null;
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

  /// Error que viene del servidor (cédula no registrada, ya usada...).
  final String? serverError;

  /// Texto de ayuda: se muestra solo cuando no hay error.
  final String? helperText;

  const _CedulaField({
    super.key,
    required this.controller,
    required this.prefix,
    required this.onPrefixChanged,
    this.focusNode,
    this.validator,
    this.onSubmitted,
    this.onChanged,
    this.serverError,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final isJ = prefix == 'J-';

    return FormField<String>(
      validator: (_) => validator?.call(controller.text),
      builder: (FormFieldState<String> state) {
        final String? err = state.errorText ?? serverError;
        final bool hasErr = err != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasErr ? kAuthError : AppColors.cardBorder,
                  width: hasErr ? 1.5 : 1.0,
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
                        // Si ya había un error local, se re-evalúa en vivo
                        if (state.hasError) state.validate();
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

            // Error (rojo) o, si no hay, el texto de ayuda
            if (err != null)
              AuthFieldError(err)
            else if (helperText != null)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 12),
                child: Text(
                  helperText!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.25,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
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
