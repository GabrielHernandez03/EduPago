// lib/features/auth/presentation/screens/email_confirmed_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import 'login_screen.dart';

enum _ConfirmState { verifying, success, failure }

/// Pantalla a la que llega el usuario desde el enlace del correo de
/// confirmación (…/?token_hash=XXXX&type=email).
///
/// Valida el token, confirma el correo y ofrece ir al inicio de sesión.
class EmailConfirmedScreen extends StatefulWidget {
  /// `token_hash` que trae el enlace del correo.
  final String? tokenHash;

  const EmailConfirmedScreen({super.key, this.tokenHash});

  /// Devuelve el `token_hash` si la URL actual viene del correo de
  /// confirmación de cuenta; si no, null.
  static String? tokenHashFromUrl() {
    final q = Uri.base.queryParameters;
    final type = q['type'];
    return (type == 'email' || type == 'signup') ? q['token_hash'] : null;
  }

  @override
  State<EmailConfirmedScreen> createState() => _EmailConfirmedScreenState();
}

class _EmailConfirmedScreenState extends State<EmailConfirmedScreen> {
  _ConfirmState _state = _ConfirmState.verifying;

  @override
  void initState() {
    super.initState();
    _confirm();
  }

  Future<void> _confirm() async {
    final hash = widget.tokenHash;
    var ok = false;
    final auth = Supabase.instance.client.auth;

    // 1. Si Supabase ya procesó automáticamente el token al cargar la web,
    // el usuario ya estará autenticado y currentUser no será null.
    if (auth.currentUser != null) {
      ok = true;
    } else if (hash != null && hash.isNotEmpty) {
      // 2. Si no se procesó automáticamente, intentamos verificarlo manualmente.
      try {
        await auth.verifyOTP(tokenHash: hash, type: OtpType.email);
        ok = true;
      } catch (_) {
        ok = false;
      }
    }

    // Si la confirmación fue exitosa, cerramos sesión de forma limpia
    // para obligar al usuario a entrar con sus credenciales desde el login.
    if (ok) {
      try {
        await auth.signOut();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _state = ok ? _ConfirmState.success : _ConfirmState.failure;
    });
  }

  void _goToLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: switch (_state) {
              _ConfirmState.verifying => _buildVerifying(),
              _ConfirmState.success => _buildResult(
                icon: Icons.check,
                color: AppColors.successGreen,
                circle: true,
                title: '¡Correo confirmado!',
                message:
                    'Tu cuenta de EduPago fue verificada correctamente. '
                    'Ya puedes iniciar sesión.',
              ),
              _ConfirmState.failure => _buildResult(
                icon: Icons.link_off,
                color: Colors.redAccent,
                circle: false,
                title: 'Enlace no válido',
                message:
                    'Este enlace venció o ya fue utilizado. Si ya confirmaste '
                    'tu correo, puedes iniciar sesión normalmente.',
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVerifying() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppColors.primaryBlue),
        SizedBox(height: 16),
        Text(
          'Confirmando tu correo...',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildResult({
    required IconData icon,
    required Color color,
    required bool circle,
    required String title,
    required String message,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(18),
          ),
          child: Icon(icon, color: color, size: 36),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _goToLogin,
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
                  'Ir al inicio de sesión',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
