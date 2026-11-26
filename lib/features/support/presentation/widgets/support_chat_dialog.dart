// lib/features/support/presentation/widgets/support_chat_dialog.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';

const String _logoAsset = 'assets/images/logo_edupago.png';

// Degradados tomados del bloque de marca del sidebar (dashboard_shell.dart).
const _brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF254B7F), Color(0xFF1B3868)],
);
const _headerGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF254B7F), Color(0xFF152E58), Color(0xFF0E2144)],
);
const _bodyGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFF6FAFF), Color(0xFFE7F0FF)],
);

class SupportChatDialog extends StatefulWidget {
  const SupportChatDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: AppColors.darkNavy.withValues(alpha: 0.45),
    builder: (_) => const SupportChatDialog(),
  );

  @override
  State<SupportChatDialog> createState() => _SupportChatDialogState();
}

class _ChatMessage {
  final bool fromUser;
  final String text;
  final bool isError;
  final String? retryText;
  final DateTime at;

  _ChatMessage({
    required this.fromUser,
    required this.text,
    this.isError = false,
    this.retryText,
  }) : at = DateTime.now();
}

class _Suggestion {
  final String text;
  final IconData icon;
  final Color bg;
  final Color fg;
  const _Suggestion(this.text, this.icon, this.bg, this.fg);
}

class _SupportChatDialogState extends State<SupportChatDialog> {
  // Colores de las baldosas: los mismos pasteles de las tarjetas del inicio.
  static const _suggestions = <_Suggestion>[
    _Suggestion(
      '¿Cuánto debo actualmente?',
      Icons.account_balance_wallet_rounded,
      Color(0xFFE0EAFF),
      Color(0xFF2563EB),
    ),
    _Suggestion(
      '¿Ya aprobaron mi último pago?',
      Icons.task_alt_rounded,
      Color(0xFFDDF4E7),
      Color(0xFF16794A),
    ),
    _Suggestion(
      '¿Cómo reporto un pago?',
      Icons.credit_card_rounded,
      Color(0xFFEDE4FF),
      Color(0xFF7C3AED),
    ),
    _Suggestion(
      '¿Por qué no veo el boletín de mi hijo?',
      Icons.description_rounded,
      Color(0xFFFEE2E2),
      Color(0xFFDC2626),
    ),
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  late List<_ChatMessage> _messages = [_welcome()];
  String? _conversationId;
  bool _sending = false;

  _ChatMessage _welcome() => _ChatMessage(
    fromUser: false,
    text:
        '¡Hola! Soy el asistente virtual de EduPago. Puedo consultar tu '
        'saldo, tus cuotas y el estado de tus pagos, y explicarte cómo '
        'funciona la plataforma. ¿En qué te ayudo?',
  );

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Red de seguridad: si el modelo devuelve Markdown, lo convierte a texto plano.
  static String _plain(String t) => t
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll('`', '')
      .replaceAllMapped(
        RegExp(r'^[ \t]*[*\-][ \t]+', multiLine: true),
        (_) => '• ',
      )
      .trim();

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _add(_ChatMessage m) {
    if (!mounted) return;
    setState(() => _messages.add(m));
    _scrollToEnd();
  }

  void _newConversation() {
    if (_sending) return;
    setState(() {
      _messages = [_welcome()];
      _conversationId = null;
    });
    _focus.requestFocus();
  }

  Future<void> _send([String? preset, bool retry = false]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    if (!retry) _input.clear();
    setState(() {
      if (retry && _messages.isNotEmpty && _messages.last.isError) {
        _messages.removeLast();
      }
      if (!retry) _messages.add(_ChatMessage(fromUser: true, text: text));
      _sending = true;
    });
    _scrollToEnd();

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'support-chat',
        body: {
          'mensaje': text,
          if (_conversationId != null) 'conversacion_id': _conversationId,
        },
      );
      final data = res.data;
      if (data is Map && data['reply'] is String) {
        _conversationId = data['conversacion_id'] as String? ?? _conversationId;
        _add(
          _ChatMessage(fromUser: false, text: _plain(data['reply'] as String)),
        );
      } else {
        _add(
          _ChatMessage(
            fromUser: false,
            isError: true,
            retryText: text,
            text: 'No pude responder ahora. Intenta de nuevo en un momento.',
          ),
        );
      }
    } on FunctionException catch (e) {
      var msg = 'No pude responder ahora. Intenta de nuevo en un momento.';
      final d = e.details;
      var canRetry = true;
      if (e.status == 401) {
        msg =
            'Tu sesión expiró. Vuelve a iniciar sesión para usar el asistente.';
        canRetry = false;
      } else if (d is Map && d['mensaje'] is String) {
        msg = d['mensaje'] as String;
        if (e.status == 429) canRetry = false;
      }
      debugPrint('support-chat ${e.status}: ${e.details}');
      _add(
        _ChatMessage(
          fromUser: false,
          isError: true,
          retryText: canRetry ? text : null,
          text: msg,
        ),
      );
    } catch (e) {
      debugPrint('support-chat error: $e');
      _add(
        _ChatMessage(
          fromUser: false,
          isError: true,
          retryText: text,
          text:
              'No hay conexión con el asistente. Revisa tu internet e intenta de nuevo.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _focus.requestFocus();
      }
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // max(0, ...) evita constraints negativas si la ventana se achica de golpe.
    final width = math.max(0.0, math.min(460.0, size.width - 32));
    final height = math.max(0.0, math.min(680.0, size.height * 0.88));
    final onlyWelcome = _messages.length == 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.88),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkNavy.withValues(alpha: 0.28),
              blurRadius: 32,
              spreadRadius: 1,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: AppColors.darkNavy.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: _bodyGradient),
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                    children: [
                      for (final m in _messages)
                        _Appear(key: ObjectKey(m), child: _messageRow(m)),
                      if (_sending) _Appear(child: _typingRow()),
                      if (onlyWelcome && !_sending) _suggestionList(),
                    ],
                  ),
                ),
                _disclaimer(),
                _inputBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo(double size) => Image.asset(
    _logoAsset,
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'Logo de EduPago',
    errorBuilder: (_, __, ___) =>
        Icon(Icons.school_rounded, color: Colors.white, size: size * 0.8),
  );

  Widget _header(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: _headerGradient),
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Círculo decorativo, como el de las tarjetas del inicio.
        Positioned(
          right: -34,
          top: -48,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  gradient: _brandGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: _logo(38),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Asistente EduPago',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF34D399),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'En línea · Asistente con IA',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.onDarkMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Nueva conversación',
                onPressed: _sending ? null : _newConversation,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: Colors.white.withValues(alpha: _sending ? 0.35 : 0.9),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ------------------------------------------------------------- mensajes

  Widget _botAvatar() => Container(
    width: 32,
    height: 32,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      gradient: _brandGradient,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      boxShadow: [
        BoxShadow(
          color: AppColors.darkNavy.withValues(alpha: 0.18),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: _logo(26),
  );

  Widget _messageRow(_ChatMessage m) {
    if (m.fromUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primaryBlue, Color(0xFF1E5BDB)],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.28,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SelectableText(
                        m.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  _time(m),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isError = m.isError;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _botAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: isError ? const Color(0xFFFEF2F2) : Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(5),
                        bottomRight: Radius.circular(18),
                      ),
                      border: Border.all(
                        color: isError
                            ? const Color(0xFFFECACA)
                            : AppColors.cardBorder,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.darkNavy.withValues(alpha: 0.035),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isError)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: AppColors.errorRed,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  m.text,
                                  style: const TextStyle(
                                    color: AppColors.darkNavy,
                                    fontSize: 13.5,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          SelectableText(
                            m.text,
                            style: const TextStyle(
                              color: AppColors.darkNavy,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                        if (isError && m.retryText != null) ...[
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: _sending
                                ? null
                                : () => _send(m.retryText, true),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Reintentar'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primaryBlue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              minimumSize: const Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                _time(m),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _time(_ChatMessage m) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      _hhmm(m.at),
      style: TextStyle(
        fontSize: 10.5,
        color: AppColors.textMuted.withValues(alpha: 0.8),
      ),
    ),
  );

  Widget _typingRow() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        _botAvatar(),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: const _TypingDots(),
        ),
      ],
    ),
  );

  // --------------------------------------------------------- sugerencias

  Widget _suggestionList() => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'PREGUNTAS FRECUENTES',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.primaryBlue.withValues(alpha: 0.9),
            ),
          ),
        ),
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SuggestionTile(s: s, onTap: () => _send(s.text)),
          ),
      ],
    ),
  );

  // ------------------------------------------------------ pie e ingreso

  Widget _disclaimer() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: AppColors.primaryBlue,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Puede equivocarse. Para montos y estados oficiales, revisa '
              '"Estado de cuenta" o consulta con la administración.',
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.cardBorder)),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _focus,
            enabled: !_sending,
            maxLength: 1000,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: const TextStyle(fontSize: 14, color: AppColors.darkNavy),
            decoration: InputDecoration(
              hintText: 'Escribe tu pregunta…',
              hintStyle: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.85),
                fontSize: 14,
              ),
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF4F7FC),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 13,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: const BorderSide(color: AppColors.cardBorder),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: const BorderSide(color: AppColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: const BorderSide(
                  color: AppColors.primaryBlue,
                  width: 1.6,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _sendButton(),
      ],
    ),
  );

  Widget _sendButton() {
    final disabled = _sending;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryBlue, Color(0xFF1E5BDB)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: Tooltip(
            message: 'Enviar',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: disabled ? null : _send,
              child: const Center(
                child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================== widgets auxiliares

/// Aparición suave (fundido + leve desplazamiento) de cada mensaje nuevo.
class _Appear extends StatelessWidget {
  const _Appear({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
    builder: (_, v, c) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: c),
    ),
    child: child,
  );
}

/// Tres puntos animados mientras el asistente responde.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final phase = (_c.value - i * 0.16) % 1.0;
        final lift = phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0.0;
        return Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
          child: Transform.translate(
            offset: Offset(0, -4 * lift),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryBlue.withValues(
                  alpha: 0.35 + 0.65 * lift,
                ),
              ),
            ),
          ),
        );
      }),
    ),
  );
}

/// Pregunta sugerida con el mismo estilo que las tarjetas de acciones del inicio.
class _SuggestionTile extends StatefulWidget {
  const _SuggestionTile({required this.s, required this.onTap});
  final _Suggestion s;
  final VoidCallback onTap;

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? s.fg.withValues(alpha: 0.55)
                  : AppColors.cardBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkNavy.withValues(
                  alpha: _hover ? 0.08 : 0.035,
                ),
                blurRadius: _hover ? 14 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: s.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(s.icon, size: 20, color: s.fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.text,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkNavy,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: s.bg, shape: BoxShape.circle),
                child: Icon(Icons.arrow_forward_rounded, size: 16, color: s.fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
