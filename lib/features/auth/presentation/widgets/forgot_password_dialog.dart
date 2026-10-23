import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';

class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({super.key});

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  /// Supabase solo permite pedir un correo de recuperación por usuario cada
  /// ~60 s; el botón de reenvío espera ese tiempo para evitar errores.
  static const int _cooldownSeconds = 60;

  // Mismo criterio que el registro: cualquier correo real, con subdominios.
  static final RegExp _emailRegex = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
    r"@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
  );

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isSent = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _sentTo = '';
  int _cooldown = 0;
  Timer? _cooldownTimer;

  /// A dónde vuelve el usuario al pulsar el botón del correo. Debe estar en
  /// Authentication > URL Configuration > Redirect URLs (para producción:
  /// https://edupago-2026.vercel.app/** ). La app lee ahí el token del enlace.
  String get _redirectUrl =>
      kIsWeb ? '${Uri.base.origin}/' : 'https://edupago-2026.vercel.app/';

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Lógica
  // ---------------------------------------------------------------------
  Future<void> _sendResetLink({bool resend = false}) async {
    if (_isLoading) return;
    if (!resend && !(_formKey.currentState?.validate() ?? false)) return;

    final email = resend ? _sentTo : _emailController.text.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: _redirectUrl,
      );

      if (!mounted) return;
      setState(() {
        _isSent = true;
        _isLoading = false;
        _sentTo = email;
      });
      _startCooldown();
    } on AuthException catch (e) {
      // El detalle real queda en consola; al usuario se le muestra un
      // mensaje claro en vez del JSON del servidor.
      debugPrint('Auth error (${e.statusCode}): ${e.message}');
      _showError(_friendlyError(e));
    } catch (e) {
      debugPrint('Error inesperado al enviar recuperación: $e');
      _showError(
        'No pudimos enviar el correo. Revisa tu conexión e intenta de nuevo.',
      );
    }
  }

  String _friendlyError(AuthException e) {
    final msg = e.message.toLowerCase();
    final status = e.statusCode ?? '';

    if (status == '429' ||
        msg.contains('rate limit') ||
        msg.contains('security purposes')) {
      return 'Ya enviamos un enlace hace poco. Espera un minuto antes de '
          'volver a intentarlo.';
    }
    if (status.startsWith('5') ||
        msg.contains('unexpected_failure') ||
        msg.contains('error sending')) {
      return 'No pudimos enviar el correo en este momento. Intenta de nuevo '
          'en unos minutos; si el problema continúa, contacta a soporte.';
    }
    return 'No pudimos procesar la solicitud. Verifica el correo e intenta '
        'de nuevo.';
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _isSent ? _buildSuccess() : _buildForm(),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppColors.textMuted,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PASO 1: pedir el correo
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heroIcon(Icons.lock_reset_rounded, AppColors.primaryBlue),
          const SizedBox(height: 20),
          const Text(
            '¿Olvidaste tu contraseña?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.darkNavy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Escribe el correo de tu cuenta y te enviaremos un enlace seguro '
            'para crear una nueva contraseña.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Correo electrónico',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.darkNavy,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            enabled: !_isLoading,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _sendResetLink(),
            style: const TextStyle(fontSize: 14, color: AppColors.darkNavy),
            decoration: _inputDecoration('nombre@correo.com'),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Ingresa tu correo electrónico';
              if (v.length > 254 || !_emailRegex.hasMatch(v)) {
                return 'Ingresa un correo válido';
              }
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            _buildErrorBanner(_errorMessage!),
          ],
          const SizedBox(height: 20),
          _primaryButton(
            label: 'Enviar enlace',
            icon: Icons.arrow_forward,
            loading: _isLoading,
            onPressed: _sendResetLink,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text(
              'Volver al inicio de sesión',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 14,
                color: AppColors.textMuted,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'El enlace vence en 15 minutos y solo se puede usar una vez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // PASO 2: confirmación de envío
  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('sent'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heroIcon(Icons.mark_email_read_outlined, AppColors.successGreen),
        const SizedBox(height: 20),
        const Text(
          'Revisa tu correo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Si ese correo está registrado, te enviamos un enlace para '
          'restablecer tu contraseña a:',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.email_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _sentTo,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TipRow(
                icon: Icons.timer_outlined,
                text: 'El enlace vence en 15 minutos y solo funciona una vez.',
              ),
              SizedBox(height: 10),
              _TipRow(
                icon: Icons.inbox_outlined,
                text:
                    '¿No lo ves? Revisa tu carpeta de spam o correo no deseado.',
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _buildErrorBanner(_errorMessage!),
        ],
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Entendido',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: (_cooldown > 0 || _isLoading)
              ? null
              : () => _sendResetLink(resend: true),
          child: Text(
            _isLoading
                ? 'Enviando...'
                : _cooldown > 0
                ? 'Reenviar enlace en ${_cooldown}s'
                : 'Reenviar enlace',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Piezas reutilizables
  // ---------------------------------------------------------------------
  Widget _heroIcon(IconData icon, Color color) {
    return Center(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.08),
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Color(0xFFB91C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    bool loading = false,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primaryBlue.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 18),
                  ],
                ],
              ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      prefixIcon: const Icon(
        Icons.email_outlined,
        color: AppColors.textMuted,
        size: 20,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(AppColors.cardBorder),
      enabledBorder: border(AppColors.cardBorder),
      disabledBorder: border(AppColors.cardBorder),
      focusedBorder: border(AppColors.primaryBlue, 1.5),
      errorBorder: border(const Color(0xFFDC2626)),
      focusedErrorBorder: border(const Color(0xFFDC2626), 1.5),
      errorStyle: const TextStyle(fontSize: 11.5),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.primaryBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
