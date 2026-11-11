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

/// Pasos del registro:
///  1. cédula (verificación contra la institución)
///  2. datos de contacto (nombres, correo, teléfono)
///  3. contraseña y términos
const int _kTotalSteps = 3;

const List<AuthStepInfo> _kStepsInfo = [
  AuthStepInfo(
    'Verifica tu cédula',
    'Confirmamos que figuras como representante.',
  ),
  AuthStepInfo('Tus datos', 'Nombre, correo y teléfono de contacto.'),
  AuthStepInfo('Tu contraseña', 'Crea tu acceso y confirma tu correo.'),
];

class _RegisterScreenState extends State<RegisterScreen> {
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();

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

  // Paso 2 y 3: Inputs y FocusNodes para navegación con Enter
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

  // --- PASO 1: VALIDAR CÉDULA (llama a la función segura de Supabase)
  Future<void> validateCedula() async {
    if (_isLoading) return;
    setState(() {
      _cedulaError = false;
      _cedulaYaRegistrada = false;
      _cedulaCustomError = null;
      _formError = null;
    });
    // Espera a que el campo se reconstruya sin los errores viejos del servidor;
    // si no, validate() los vería como actuales y bloquearía el reintento.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!_step1FormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

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

  // --- PASO 2 -> 3: datos de contacto válidos, pasa a la contraseña
  void _continueToPassword() {
    if (!_step2FormKey.currentState!.validate()) return;
    setState(() {
      _currentStep = 3;
      _formError = null;
    });
  }

  // --- PASO 3: CREAR CUENTA EN SUPABASE AUTH
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

    final bool formOk = _step3FormKey.currentState!.validate();
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
        // El correo se edita en el paso 2: se vuelve allí para mostrar el error.
        setState(() {
          _isLoading = false;
          _currentStep = 2;
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
          // Correo repetido -> en el campo de correo (paso 2)
          _currentStep = 2;
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
      builder: (dialogContext) {
        return AuthStatusDialog(
          icon: Icons.mark_email_unread_outlined,
          tone: AuthTone.warning,
          badge: 'Pendiente de verificación',
          title: 'Confirma tu correo electrónico',
          message: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Hemos enviado un enlace de confirmación a\n',
                ),
                TextSpan(
                  text: _emailController.text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkNavy,
                  ),
                ),
                const TextSpan(
                  text: '.\nAbre tu correo para activar tu cuenta.',
                ),
              ],
            ),
          ),
          noticeTitle: 'El enlace expira en 15 minutos',
          noticeText: 'Revisa también tu carpeta de correo no deseado (spam).',
          primaryLabel: 'Entendido, ir a iniciar sesión',
          onPrimary: () {
            Navigator.pop(dialogContext);
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          },
          secondaryLabel: 'Mi enlace expiró / reenviar correo',
          onSecondary: () {
            Navigator.pop(dialogContext);
            _showExpiredTokenModal();
          },
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
      builder: (dialogContext) {
        return AuthStatusDialog(
          icon: Icons.timer_off_outlined,
          tone: AuthTone.danger,
          badge: 'Enlace expirado',
          title: 'El enlace de confirmación expiró',
          message: const Text(
            'Por seguridad, los enlaces solo son válidos durante 15 minutos. '
            'Solicita uno nuevo para continuar.',
          ),
          noticeTitle: 'Enlace vencido',
          noticeText: 'Tu cuenta todavía no ha sido activada.',
          primaryLabel: 'Reenviar correo de verificación',
          onPrimary: () async {
            Navigator.pop(dialogContext);
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
              _showSnack('No pudimos reenviar el correo. Intenta de nuevo.');
            }
          },
        );
      },
    );
  }

  void _goToLogin() {
    Navigator.pushReplacement(context, authFadeRoute(const LoginScreen()));
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return AuthShell(
      onBack: () => Navigator.pop(context),
      intro: AuthBrandIntro(
        lead: 'Activa tu cuenta',
        title: 'Gestiona los pagos de tu familia en tres pasos.',
        description:
            'Usa la cédula que la institución ya registró y gestiona los pagos de tu familia desde un solo lugar.',
        children: [
          AuthStepsOverview(current: _currentStep, steps: _kStepsInfo),
        ],
      ),
      // La altura de la tarjeta la anima AuthCard; aquí solo el fundido +
      // desplazamiento entre pasos.
      child: AnimatedSwitcher(
        duration: authMotion(context, 300),
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
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 2:
        return _buildStep2Widget();
      case 3:
        return _buildStep3Widget();
      default:
        return _buildStep1Widget();
    }
  }

  // Dos campos en fila; en espacios angostos se apilan.
  Widget _pair(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 400) {
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

  /// Botones de navegación de los pasos 2 y 3: "Atrás" + acción principal.
  Widget _navRow({required VoidCallback onBack, required Widget primary}) {
    return Row(
      children: [
        AuthOutlineButton(
          label: 'Atrás',
          icon: Icons.arrow_back_rounded,
          height: 52,
          onPressed: _isLoading ? null : onBack,
        ),
        const SizedBox(width: 12),
        Expanded(child: primary),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // PASO 1 · CÉDULA
  // ---------------------------------------------------------------------
  Widget _buildStep1Widget() {
    final bool isJ = _selectedPrefix == 'J-';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const AuthStepper(current: 1, total: _kTotalSteps),
        const SizedBox(height: 20),
        const AuthCardHeader(
          title: 'Verifica tu cédula',
          subtitle:
              'Primero comprobamos que estés registrado como representante en la institución.',
        ),
        const SizedBox(height: 22),
        Form(
          key: _step1FormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTextField(
                controller: _cedulaController,
                focusNode: _cedulaFocusNode,
                label: 'Cédula de identidad del representante',
                hint: 'Número de cédula',
                prefix: _DocTypeMenu(
                  prefix: _selectedPrefix,
                  onSelected: (p) {
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
                ),
                helperText:
                    'Debe coincidir con la cédula registrada en el expediente escolar.',
                serverError: _cedulaServerError,
                keyboardType: isJ ? TextInputType.text : TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(isJ ? r'[0-9-]' : r'[0-9]'),
                  ),
                  LengthLimitingTextInputFormatter(12),
                ],
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
                onFieldSubmitted: (_) => validateCedula(),
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
                AuthTextLink(
                  label: 'Contactar a administración / soporte',
                  icon: Icons.support_agent_outlined,
                  onTap: _contactSupport,
                  fontSize: 13,
                ),
              if (_cedulaYaRegistrada)
                AuthTextLink(
                  label: 'Ir a iniciar sesión',
                  icon: Icons.login_rounded,
                  onTap: _goToLogin,
                  fontSize: 13,
                ),
              if (_formError != null) ...[
                const SizedBox(height: 14),
                AuthErrorBanner(message: _formError!),
              ],
              const SizedBox(height: 20),
              AuthPrimaryButton(
                label: 'Verificar cédula',
                loadingLabel: 'Verificando…',
                loading: _isLoading,
                onPressed: validateCedula,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        AuthSwitchRow(
          prompt: '¿Ya tienes una cuenta?',
          action: 'Iniciar sesión',
          onTap: _goToLogin,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // PASO 2 · DATOS DE CONTACTO
  // ---------------------------------------------------------------------
  Widget _buildStep2Widget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const AuthStepper(current: 2, total: _kTotalSteps),
        const SizedBox(height: 20),
        const AuthCardHeader(
          title: 'Tus datos de contacto',
          subtitle:
              'Usaremos tu correo para confirmar la cuenta y tu teléfono como dato de contacto.',
        ),
        const SizedBox(height: 18),
        _verifiedPill(),
        const SizedBox(height: 20),
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
                  controller: _nombresController,
                  focusNode: _nombresFocusNode,
                  label: 'Nombres',
                  hint: 'Tus nombres',
                  icon: Icons.person_outline,
                  autofillHints: const [AutofillHints.givenName],
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_apellidosFocusNode),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Ingresa tus nombres'
                      : null,
                ),
                AuthTextField(
                  controller: _apellidosController,
                  focusNode: _apellidosFocusNode,
                  label: 'Apellidos',
                  hint: 'Tus apellidos',
                  icon: Icons.person_outline,
                  autofillHints: const [AutofillHints.familyName],
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
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                label: 'Número de teléfono',
                hint: '412 555 0174',
                prefix: Container(
                  width: 54,
                  alignment: Alignment.center,
                  child: const Text(
                    '+58',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkNavy,
                    ),
                  ),
                ),
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _continueToPassword(),
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
              if (_formError != null) ...[
                const SizedBox(height: 14),
                AuthErrorBanner(message: _formError!),
              ],
              const SizedBox(height: 22),
              _navRow(
                onBack: () => setState(() {
                  _currentStep = 1;
                  _formError = null;
                }),
                primary: AuthPrimaryButton(
                  label: 'Continuar',
                  onPressed: _continueToPassword,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Confirmación de que la cédula fue verificada (paso 2).
  Widget _verifiedPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: AppColors.successGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cédula verificada',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF166534),
                  ),
                ),
                Text(
                  '$_cedulaNormalizada · Representante pre-registrado',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // PASO 3 · CONTRASEÑA Y TÉRMINOS
  // ---------------------------------------------------------------------
  Widget _buildStep3Widget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const AuthStepper(current: 3, total: _kTotalSteps),
        const SizedBox(height: 20),
        const AuthCardHeader(
          title: 'Crea tu contraseña',
          subtitle:
              'Será tu clave para entrar a EduPago. Después te enviaremos un correo para confirmar la cuenta.',
        ),
        const SizedBox(height: 22),
        Form(
          key: _step3FormKey,
          onChanged: () {
            if (_formError != null) setState(() => _formError = null);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTextField(
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
                suffix: AuthVisibilityToggle(
                  obscured: _obscurePassword,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: _validatePassword,
              ),
              const SizedBox(height: 16),
              AuthTextField(
                controller: _confirmPasswordController,
                focusNode: _confirmPasswordFocusNode,
                label: 'Confirmar contraseña',
                hint: 'Repite tu contraseña',
                icon: Icons.lock_outline,
                obscureText: _obscureConfirmPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => submitRegistration(),
                // Si cambia la contraseña, se re-evalúa "no coinciden"
                revalidateWhen: _passwordController,
                suffix: AuthVisibilityToggle(
                  obscured: _obscureConfirmPassword,
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
              const SizedBox(height: 14),
              _buildPasswordChecklist(),
              const SizedBox(height: 12),
              _buildTerms(),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                AuthErrorBanner(message: _formError!),
              ],
              const SizedBox(height: 20),
              _navRow(
                onBack: () => setState(() {
                  _currentStep = 2;
                  _formError = null;
                }),
                primary: AuthPrimaryButton(
                  label: 'Crear cuenta',
                  loadingLabel: 'Creando cuenta…',
                  loading: _isLoading,
                  icon: Icons.check_rounded,
                  onPressed: submitRegistration,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Te enviaremos un correo de confirmación para activar tu cuenta.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color.lerp(
                    AppColors.textMuted,
                    AppColors.darkNavy,
                    0.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                _termsAccepted = !_termsAccepted;
                if (_termsAccepted) _termsError = false;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _termsAccepted,
                        activeColor: AppColors.primaryBlue,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        side: _termsError
                            ? const BorderSide(color: kAuthError, width: 2)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        onChanged: (val) => setState(() {
                          _termsAccepted = val ?? false;
                          if (_termsAccepted) _termsError = false;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Acepto los términos del servicio y el tratamiento seguro de mis datos.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Color.lerp(
                              AppColors.textMuted,
                              AppColors.darkNavy,
                              0.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_termsError)
          const AuthFieldError(
            'Debes aceptar los términos para continuar.',
            left: 36,
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tu contraseña debe tener',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkNavy,
                  ),
                ),
              ),
              if (label.isNotEmpty)
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: barColor == AppColors.cardBorder
                        ? AppColors.textMuted
                        : barColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p.isEmpty ? 0 : done / rules.length,
              minHeight: 5,
              color: barColor,
              backgroundColor: const Color(0xFFE2E8F0),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final r in rules) _ruleChip(r, red, green)],
          ),
        ],
      ),
    );
  }

  Widget _ruleChip(_PwRule r, Color red, Color green) {
    final bool failed = !r.ok && _showPasswordErrors;
    final Color fg = r.ok
        ? const Color(0xFF166534)
        : (failed ? const Color(0xFF991B1B) : AppColors.textMuted);
    final Color bg = r.ok
        ? const Color(0xFFDCFCE7)
        : (failed ? const Color(0xFFFEE2E2) : Colors.white);
    final Color border = r.ok
        ? const Color(0xFFBBF7D0)
        : (failed ? const Color(0xFFFECACA) : AppColors.cardBorder);

    return Semantics(
      label: '${r.label}: ${r.ok ? 'cumplido' : 'pendiente'}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: authMotion(context, 160),
        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              r.ok
                  ? Icons.check_circle
                  : (failed ? Icons.cancel : Icons.radio_button_unchecked),
              size: 14,
              color: r.ok ? green : (failed ? red : AppColors.textMuted),
            ),
            const SizedBox(width: 5),
            Text(
              r.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: r.ok || failed ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector del tipo de documento (V-, E-, J-, P-) que vive dentro del campo
/// de cédula, como prefijo.
class _DocTypeMenu extends StatelessWidget {
  const _DocTypeMenu({required this.prefix, required this.onSelected});

  final String prefix;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<String>(
        tooltip: 'Tipo de documento',
        initialValue: prefix,
        onSelected: onSelected,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        constraints: const BoxConstraints(minWidth: 190, maxWidth: 230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        itemBuilder: (_) => [
          for (final e in _kCedPrefixes.entries)
            PopupMenuItem<String>(
              value: e.key,
              height: 42,
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    e.value,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                prefix,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkNavy,
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 22, color: AppColors.cardBorder),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _PwRule {
  final String label;
  final String short;
  final bool ok;
  const _PwRule(this.label, this.short, this.ok);
}
