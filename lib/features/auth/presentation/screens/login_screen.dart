import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';
import '../widgets/forgot_password_dialog.dart';
import 'register_screen.dart';
import '../../../dashboard/presentation/screens/representative_dashboard_screen.dart';
import '../../../dashboard/presentation/screens/admin_dashboard_screen.dart';

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
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _isLogoHovered = false; // Estado para el efecto hover del logo

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
        final role = user.userMetadata?['role'] ?? 'representante';
        final bool esCuentaAdmin = role == 'admin';

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

        setState(() {
          _isLoading = false;
        });

        if (!mounted) return;

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
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al iniciar sesión: ${e.message}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error inesperado: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
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
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 900;

    // Color dinámico para diferenciar visualmente el rol activo
    final Color activeColor = _isRepresentanteRole
        ? AppColors.primaryBlue
        : AppColors.darkNavy;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          if (isDesktop)
            Expanded(
              flex: 6,
              child: Container(
                color: AppColors.darkNavy,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.15,
                        child: Image.asset(
                          'assets/images/login_img1.webp',
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
                          // Logo y nombre interactivos con hover de escala y sin marco
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
                                '¿Ya tienes cuenta?',
                                style: TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontSize: 48,
                                  height: 0.8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 15),
                              const Text(
                                'Administrar la educación\ntambién puede sentirse simple.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Todo lo que necesitas para mantener las cuentas claras y la\ncomunidad conectada.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.location_city,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'U.E. Nueva Generación',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Caracas, Venezuela',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                    Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                    Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                    Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                    Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Botón Volver al inicio
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
                      const SizedBox(height: 10),

                      // Icono superior animado según el rol seleccionado
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: activeColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _isRepresentanteRole
                              ? Icons.lock_outline
                              : Icons.admin_panel_settings_outlined,
                          color: activeColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 10),
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
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Selector de portal animado
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
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _isRepresentanteRole = true),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isRepresentanteRole
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _isRepresentanteRole
                                        ? [
                                            BoxShadow(
                                              color: AppColors.primaryBlue
                                                  .withValues(alpha: 0.15),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person_outline,
                                        size: 17,
                                        color: _isRepresentanteRole
                                            ? AppColors.primaryBlue
                                            : AppColors.textMuted,
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'Portal Representante',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _isRepresentanteRole
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: _isRepresentanteRole
                                              ? AppColors.primaryBlue
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(
                                  () => _isRepresentanteRole = false,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !_isRepresentanteRole
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: !_isRepresentanteRole
                                        ? [
                                            BoxShadow(
                                              color: AppColors.darkNavy
                                                  .withValues(alpha: 0.15),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.account_balance_outlined,
                                        size: 17,
                                        color: !_isRepresentanteRole
                                            ? AppColors.darkNavy
                                            : AppColors.textMuted,
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        'Administrativo',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: !_isRepresentanteRole
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: !_isRepresentanteRole
                                              ? AppColors.darkNavy
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
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
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) {
                                FocusScope.of(
                                  context,
                                ).requestFocus(_passwordFocusNode);
                              },
                              decoration: InputDecoration(
                                hintText: 'nombre@correo.com',
                                hintStyle: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.email_outlined,
                                  color: AppColors.textMuted,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.cardBorder,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.cardBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: activeColor,
                                    width: 1.5,
                                  ),
                                ),
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
                            const SizedBox(height: 12),
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
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) {
                                _submitLogin();
                              },
                              decoration: InputDecoration(
                                hintText: 'Mínimo 8 caracteres',
                                hintStyle: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: AppColors.textMuted,
                                  size: 20,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  color: AppColors.textMuted,
                                  iconSize: 20,
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.cardBorder,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.cardBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: activeColor,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Ingresa tu contraseña';
                                }
                                if (value.length < 6) {
                                  return 'La contraseña debe tener al menos 6 caracteres';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Checkbox(
                                        value: _rememberMe,
                                        activeColor: activeColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        onChanged: (val) {
                                          setState(
                                            () => _rememberMe = val ?? false,
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Recordar mi cuenta',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                InkWell(
                                  onTap: _showForgotPasswordModal,
                                  child: Text(
                                    '¿Olvidó su contraseña?',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: activeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '¿Aún no tienes cuenta? ',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'Créala aquí',
                              style: TextStyle(
                                color: activeColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
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
                                'Sesión JWT / HttpOnly',
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
}
