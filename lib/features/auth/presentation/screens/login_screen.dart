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

  static const List<AuthSegment> _segments = [
    AuthSegment(
      label: 'Portal Representante',
      icon: Icons.person_outline,
      color: AppColors.primaryBlue,
    ),
    AuthSegment(
      label: 'Administrativo',
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

  // Inicio de sesión con Supabase Auth y redirección basada en roles
  Future<void> _submitLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final response = await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (response.user == null || !mounted) {
          setState(() => _isLoading = false);
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
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tu cuenta no tiene un perfil activo. Contacta a la administración.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }

        final bool esCuentaAdmin = perfil['rol'] == 'administrador';

        if (_isRepresentanteRole && esCuentaAdmin) {
          await supabase.auth.signOut();
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Esta cuenta pertenece al portal Administrativo. Selecciona esa opción para continuar.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }

        if (!_isRepresentanteRole && !esCuentaAdmin) {
          await supabase.auth.signOut();
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Esta cuenta pertenece al Portal Representante. Selecciona esa opción para continuar.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }

        // Auditoría: todas las validaciones pasaron, el inicio de sesión es
        // exitoso -> se guarda fecha, hora e IP antes de entrar al panel.
        await _registrarInicioSesion();
        await IdleSessionStore.touch(); // reinicia el reloj de inactividad

        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });

        _passwordController.clear();

        if (esCuentaAdmin) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const AdminDashboardScreen(),
            ),
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
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loginErrorMessage(e.message)),
            backgroundColor: Colors.redAccent,
          ),
        );
      } catch (e) {
        debugPrint('login error: $e');
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ocurrió un error inesperado. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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

  /// Mensaje claro sin revelar si el correo existe: el servidor responde lo
  /// mismo para "correo inexistente" y "contraseña incorrecta".
  String _loginErrorMessage(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.contains('email not confirmed')) {
      return 'Debes confirmar tu correo antes de iniciar sesión. Revisa tu bandeja de entrada.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Demasiados intentos. Espera unos minutos antes de volver a intentarlo.';
    }
    return 'No pudimos iniciar sesión. Intenta de nuevo.';
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

  // Decoración común de los campos (evita repetir 40 líneas por input)
  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    required Color activeColor,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(AppColors.cardBorder),
      enabledBorder: border(AppColors.cardBorder),
      focusedBorder: border(activeColor, 1.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 900;
    final Color targetColor = _isRepresentanteRole
        ? AppColors.primaryBlue
        : AppColors.darkNavy;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          if (isDesktop)
            Expanded(
              flex: 5,
              child: AuthBrandPanel(
                imageAsset: 'assets/images/login_img1.webp',
                onLogoTap: () => Navigator.pop(context),
                headline: '¿Ya tienes cuenta?',
                subtitle:
                    'Administrar la educación\ntambién puede sentirse simple.',
                description:
                    'Todo lo que necesitas para mantener las cuentas claras y la comunidad conectada.',
                features: const [
                  AuthFeature(
                    Icons.person_outline,
                    'Portal Representante',
                    description: 'Tus hijos y tus cuentas en un solo lugar.',
                  ),
                  AuthFeature(
                    Icons.account_balance_outlined,
                    'Portal Administrativo',
                    description: 'La gestión escolar de toda la institución.',
                  ),
                ],
              ),
            ),
          Expanded(
            flex: 5,
            child: AuthFormPanel(
              isDesktop: isDesktop,
              maxWidth: 560,
              onBack: () => Navigator.pop(context),
              child: _buildFormContent(targetColor),
            ),
          ),
        ],
      ),
    );
  }

  // Cambia un color con una transición corta, pero solo en el widget pequeño
  // que lo usa (antes se animaba y reconstruía el formulario completo).
  Widget _accent(Color target, Widget Function(Color color) builder) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      builder: (context, color, _) => builder(color ?? target),
    );
  }

  Widget _buildFormContent(Color activeColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Cabecera ──
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey(_isRepresentanteRole),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isRepresentanteRole
                  ? Icons.lock_outline
                  : Icons.admin_panel_settings_outlined,
              color: activeColor,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Bienvenido de nuevo',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ingresa a tu espacio de gestión escolar.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
        ),
        const SizedBox(height: 22),

        // ── Selector líquido de portal ──
        LiquidSegmentedSelector(
          segments: _segments,
          selectedIndex: _isRepresentanteRole ? 0 : 1,
          onChanged: (i) => setState(() => _isRepresentanteRole = i == 0),
        ),
        const SizedBox(height: 20),

        // ── Formulario ──
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Correo electrónico',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(_passwordFocusNode),
                decoration: _fieldDecoration(
                  hint: 'nombre@correo.com',
                  icon: Icons.email_outlined,
                  activeColor: activeColor,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa tu correo electrónico';
                  }
                  if (!value.contains('@')) {
                    return 'Ingresa un correo válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'Contraseña',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submitLogin(),
                decoration: _fieldDecoration(
                  hint: 'Mínimo 8 caracteres',
                  icon: Icons.lock_outline,
                  activeColor: activeColor,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    color: AppColors.textMuted,
                    iconSize: 20,
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: _showForgotPasswordModal,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: _accent(
                      activeColor,
                      (c) => Text(
                        '¿Olvidó su contraseña?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: c,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeColor,
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
                              'Iniciar sesión',
                              style: TextStyle(
                                fontSize: 15,
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
        const SizedBox(height: 16),

        // ── Enlace a registro ──
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '¿Aún no tienes cuenta? ',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            InkWell(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  authFadeRoute(const RegisterScreen()),
                );
              },
              child: _accent(
                activeColor,
                (c) => Text(
                  'Créala aquí',
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
