// lib/features/support/presentation/widgets/support_chat_dialog.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';

class SupportChatDialog extends StatefulWidget {
  const SupportChatDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => const SupportChatDialog(),
  );

  @override
  State<SupportChatDialog> createState() => _SupportChatDialogState();
}

class _ChatMessage {
  final bool fromUser;
  final String text;
  final bool isError;
  const _ChatMessage({
    required this.fromUser,
    required this.text,
    this.isError = false,
  });
}

class _SupportChatDialogState extends State<SupportChatDialog> {
  static const _suggestions = <String>[
    '¿Cómo reporto un pago?',
    '¿Qué métodos de pago puedo usar?',
    '¿Cómo se aplica mi pago a las cuotas?',
    '¿Por qué no veo el boletín de mi hijo?',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      fromUser: false,
      text:
          '¡Hola! Soy el asistente virtual de EduPago. Puedo explicarte cómo '
          'reportar pagos, qué métodos se aceptan o cómo funcionan los '
          'documentos. ¿En qué te ayudo?',
    ),
  ];

  String? _conversationId;
  bool _sending = false;

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

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _add(_ChatMessage m) {
    if (!mounted) return;
    setState(() => _messages.add(m));
    _scrollToEnd();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    _input.clear();
    setState(() {
      _messages.add(_ChatMessage(fromUser: true, text: text));
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
          const _ChatMessage(
            fromUser: false,
            isError: true,
            text: 'No pude responder ahora. Intenta de nuevo en un momento.',
          ),
        );
      }
    } on FunctionException catch (e) {
      var msg = 'No pude responder ahora. Intenta de nuevo en un momento.';
      final d = e.details;
      if (e.status == 401) {
        msg =
            'Tu sesión expiró. Vuelve a iniciar sesión para usar el asistente.';
      } else if (d is Map && d['mensaje'] is String) {
        msg = d['mensaje'] as String;
      }
      debugPrint('support-chat ${e.status}: ${e.details}');
      _add(_ChatMessage(fromUser: false, isError: true, text: msg));
    } catch (e) {
      debugPrint('support-chat error: $e');
      _add(
        const _ChatMessage(
          fromUser: false,
          isError: true,
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // max(0, ...) evita constraints negativas si la ventana se achica de golpe.
    final width = math.max(0.0, math.min(460.0, size.width - 32));
    final height = math.max(0.0, math.min(640.0, size.height * 0.86));
    final onlyWelcome = _messages.length == 1;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  for (final m in _messages) _bubble(m),
                  if (_sending) _typing(),
                  if (onlyWelcome && !_sending) _suggestionChips(),
                ],
              ),
            ),
            _disclaimer(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
    color: AppColors.darkNavy,
    padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
    child: Row(
      children: [
        const Icon(Icons.support_agent_rounded, color: Colors.white),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Asistente EduPago',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text(
                'Asistente con IA',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ],
    ),
  );

  Widget _bubble(_ChatMessage m) {
    final user = m.fromUser;
    final bg = user
        ? AppColors.primaryBlue
        : (m.isError ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9));
    final fg = user ? Colors.white : AppColors.darkNavy;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(user ? 16 : 4),
            bottomRight: Radius.circular(user ? 4 : 16),
          ),
        ),
        child: SelectableText(
          m.text,
          style: TextStyle(color: fg, fontSize: 14, height: 1.4),
        ),
      ),
    );
  }

  Widget _typing() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Escribiendo…',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    ),
  );

  Widget _suggestionChips() => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in _suggestions)
          ActionChip(
            label: Text(s, style: const TextStyle(fontSize: 12.5)),
            onPressed: () => _send(s),
          ),
      ],
    ),
  );

  Widget _disclaimer() => const Padding(
    padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
    child: Text(
      'Puede equivocarse. Para montos y estados oficiales, revisa '
      '"Estado de cuenta" o consulta con la administración.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
    ),
  );

  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: const BoxDecoration(
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
            decoration: InputDecoration(
              hintText: 'Escribe tu pregunta…',
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: AppColors.cardBorder),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Enviar',
          onPressed: _sending ? null : _send,
          style: IconButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          icon: const Icon(Icons.send_rounded, size: 20),
        ),
      ],
    ),
  );
}
