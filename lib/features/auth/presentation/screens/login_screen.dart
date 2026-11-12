import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/session/idle_session_store.dart';
import '../../../../main.dart';
import '../widgets/auth_shared_widgets.dart';
import '../widgets/forgot_password_dialog.dart';
import 'register_screen.dart';
import '../../../dashboard/presentation/screens/admin_dashboard_screen.dart';
import '../../../dashboard/presentation/screens/representative_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // FocusNodes para controlar el salto entre campos con Enter
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isRepresentanteRole = true;
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Errores del servidor, mostrados en el campo al que corresponden
  bool _credentialsError = false; // contraseña (y borde del correo) en rojo
  String? _emailServerError; // correo sin confirmar
  String? _portalError; // la cuenta es del otro portal -> bajo el selector
  String? _formError; // errores generales -> aviso sobre el botón

  static const List<AuthSegment> _segments = [
    AuthSegment(
      label: 'Representante',
      icon: Icons.person_outline,
      color: AppColors.primaryBlue,
    ),
    AuthSegment(
      label: 'Administrador',
      icon: Icons.account_balance_outlined,
      color: AppColors.darkNavy,
    ),
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _clearServerErrors() {
    _credentialsError = false;
    _emailServerError = null;
    _portalError = null;
    _formError = null;
  }

  // Limpia errores del servidor al editar (solo reconstruye si había alguno)
  void _onEdited() {
    if (_credentialsError ||
        _emailServerError != null ||
        _portalError != null ||
        _formError != null) {
      setState(_clearServerErrors);
    }
  }

  // Inicio de sesión con Supabase Auth y redirección basada en roles
  Future<void> _submitLogin() async {
    if (_isLoading) return;
    setState(_clearServerErrors);
    // Espera a que los campos se reconstruyan sin los errores viejos del
    // servidor; si no, validate() los vería como si fueran actuales y
    // bloquearía el reintento.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user == null || !mounted) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final user = response.user!;

      final perfil = await supabase
          .from('perfiles')
          .select('rol, activo')
          .eq('id', user.id)
          .maybeSingle();

      if (perfil == null || perfil['activo'] != true) {
        await supabase.auth.signOut();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _formError =
              'Tu cuenta no tiene un perfil activo. Contacta a la administración.';
        });
        return;
      }

      final bool esCuentaAdmin = perfil['rol'] == 'administrador';

      if (_isRepresentanteRole && esCuentaAdmin) {
        await supabase.auth.signOut();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _portalError =
              'Esta cuenta pertenece al portal Administrador. Selecciona esa opción para continuar.';
        });
        return;
      }

      if (!_isRepresentanteRole && !esCuentaAdmin) {
        await supabase.auth.signOut();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _portalError =
              'Esta cuenta pertenece al portal Representante. Selecciona esa opción para continuar.';
        });
        return;
      }

      // Auditoría: todas las validaciones pasaron, el inicio de sesión es
      // exitoso -> se guarda fecha, hora e IP antes de entrar al panel.
      await _registrarInicioSesion();
      await IdleSessionStore.touch(); // reinicia el reloj de inactividad

      if (!mounted) return;
      setState(() => _isLoading = false);

      _passwordController.clear();

      if (esCuentaAdmin) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const RepresentativeDashboardScreen(),
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _applyAuthError(e.message);
      });
    } catch (e) {
      debugPrint('login error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _formError = 'Ocurrió un error inesperado. Intenta de nuevo.';
      });
    }
  }

  /// Reparte el error de Supabase en el campo que corresponde.
  /// No revela si el correo existe: el servidor responde lo mismo para
  /// "correo inexistente" y "contraseña incorrecta", así que se marcan ambos
  /// campos y el mensaje va bajo la contraseña.
  void _applyAuthError(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      _credentialsError = true;
    } else if (m.contains('email not confirmed')) {
      _emailServerError =
          'Debes confirmar tu correo antes de iniciar sesión. Revisa tu bandeja de entrada.';
    } else if (m.contains('rate limit') || m.contains('too many')) {
      _formError =
          'Demasiados intentos. Espera unos minutos antes de volver a intentarlo.';
    } else {
      _formError = 'No pudimos iniciar sesión. Intenta de nuevo.';
    }
  }

  /// Registro de auditoría del inicio de sesión (fecha, hora e IP).
  ///
  /// La IP NO se envía desde la app: la función SQL `registrar_inicio_sesion`
  /// la lee de las cabeceras de la petición en el servidor, así no se puede
  /// falsear desde el cliente. Si el registro falla no se bloquea el acceso,
  /// pero el error queda en consola.
  Future<void> _registrarInicioSesion() async {
    try {
      await supabase.rpc('registrar_inicio_sesion');
    } catch (e) {
      debugPrint('auditoría de sesión no registrada: $e');
    }
  }

  void _showForgotPasswordModal() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return const ForgotPasswordDialog();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // El portal Administrador usa el azul marino como acento.
    final Color accent = _isRepresentanteRole
        ? AppColors.primaryBlue
        : AppColors.darkNavy;

    return AuthShell(
      onBack: () => Navigator.pop(context),
      cardMaxWidth: 560,
      cardExtraVerticalPadding: 24,
      intro: const AuthBrandIntro(
        lead: 'Bienvenido de nuevo',
        title: 'Administrar la educación también puede sentirse simple.',
        description:
            'Todo lo que necesitas para mantener las cuentas claras y la comunidad conectada.',
        children: [
          SizedBox(
            width: 460,
            child: Divider(height: 1, thickness: 1, color: Color(0xB3FFFFFF)),
          ),
          SizedBox(height: 22),
          AuthFeatureChips(
            features: [
              AuthFeature(Icons.payments_outlined, 'Gestión de pagos'),
              AuthFeature(Icons.verified_user_outlined, 'Solvencias digitales'),
              AuthFeature(Icons.receipt_long_outlined, 'Control y seguimiento'),
            ],
          ),
        ],
      ),
      child: _buildFormContent(accent),
    );
  }

  Widget _buildFormContent(Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AuthCardHeader(
          icon: Icons.lock_rounded,
          accent: accent,
          iconDecorated: false,
          title: 'Inicia sesión',
          subtitle: 'Elige tu portal e ingresa con tu correo y contraseña.',
        ),
        const SizedBox(height: 18),

        // ── Selector de portal ──
        AuthSegmentedSelector(
          height: 44,
          segments: _segments,
          hasError: _portalError != null,
          selectedIndex: _isRepresentanteRole ? 0 : 1,
          onChanged: (i) => setState(() {
            _isRepresentanteRole = i == 0;
            _portalError = null;
          }),
        ),
        if (_portalError != null) AuthFieldError(_portalError!, left: 4),
        const SizedBox(height: 16),

        // ── Formulario ──
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTextField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                label: 'Correo electrónico',
                hint: 'nombre@correo.com',
                icon: Icons.email_outlined,
                activeColor: accent,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(_passwordFocusNode),
                onChanged: (_) => _onEdited(),
                serverError: _emailServerError,
                // Si las credenciales fallan, el borde del correo también se
                // marca (el mensaje va bajo la contraseña).
                forceErrorBorder: _credentialsError,
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Ingresa tu correo electrónico';
                  if (!kAuthEmailRegex.hasMatch(v)) {
                    return 'Ingresa un correo válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AuthTextField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                label: 'Contraseña',
                labelTrailing: AuthTextLink(
                  label: '¿Olvidaste tu contraseña?',
                  onTap: _showForgotPasswordModal,
                  color: accent,
                  fontSize: 12.5,
                  dense: true,
                ),
                hint: 'Tu contraseña',
                icon: Icons.lock_outline,
                activeColor: accent,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submitLogin(),
                onChanged: (_) => _onEdited(),
                serverError: _credentialsError
                    ? 'Correo o contraseña incorrectos.'
                    : null,
                suffix: AuthVisibilityToggle(
                  obscured: _obscurePassword,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa tu contraseña';
                  }
                  if (value.length < 8) {
                    return 'La contraseña debe tener al menos 8 caracteres';
                  }
                  return null;
                },
              ),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                AuthErrorBanner(message: _formError!),
              ],
              const SizedBox(height: 20),
              AuthPrimaryButton(
                label: 'Iniciar sesión',
                loadingLabel: 'Ingresando…',
                loading: _isLoading,
                color: accent,
                onPressed: _submitLogin,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // ── Acceso a registro ──
        AuthSwitchRow(
          prompt: '¿Aún no tienes cuenta?',
          action: 'Crear cuenta',
          color: accent,
          onTap: () {
            Navigator.pushReplacement(
              context,
              authFadeRoute(const RegisterScreen()),
            );
          },
        ),
      ],
    );
  }
}
