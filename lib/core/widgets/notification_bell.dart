import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';

// Ubicación: lib/core/widgets/notification_bell.dart

/// Campana del encabezado: contador de no leídas, panel con la lista y aviso
/// emergente cuando llega una notificación nueva en tiempo real.
class NotificationBell extends StatefulWidget {
  /// Se ejecuta al tocar una notificación (p. ej. para cambiar de pestaña).
  final ValueChanged<AppNotification>? onOpen;

  const NotificationBell({super.key, this.onOpen});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final NotificationService _service;

  @override
  void initState() {
    super.initState();
    _service = NotificationService()..onNew = _onNew;
    _service.start();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _onNew(AppNotification n) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        backgroundColor: AppColors.darkNavy,
        content: Text(
          '${n.titulo}: ${n.mensaje}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _openPanel() async {
    final box = context.findRenderObject() as RenderBox;
    final bell = box.localToGlobal(Offset.zero) & box.size;
    _service.refresh(silent: true); // al abrir, siempre datos frescos

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar notificaciones',
      barrierColor: Colors.black.withOpacity(0.12),
      transitionDuration: const Duration(milliseconds: 120),
      transitionBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (ctx, _, __) {
        final screen = MediaQuery.sizeOf(ctx);
        final width = math.min(380.0, screen.width - 24);
        final left = (bell.right - width).clamp(
          12.0,
          screen.width - width - 12,
        );
        final top = bell.bottom + 8;
        final maxHeight = math.max(
          200.0,
          math.min(480.0, screen.height - top - 12),
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: _NotificationPanel(
                service: _service,
                maxHeight: maxHeight,
                onOpen: (n) {
                  _service.markAsRead(n.id);
                  Navigator.of(ctx).pop();
                  widget.onOpen?.call(n);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final unread = _service.unreadCount;
        return Tooltip(
          message: unread > 0
              ? '$unread notificaciones sin leer'
              : 'Notificaciones',
          child: InkWell(
            onTap: _openPanel,
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.cardBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.notifications_none,
                    size: 18,
                    color: AppColors.darkNavy,
                  ),
                ),
                if (unread > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
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
}

class _NotificationPanel extends StatelessWidget {
  final NotificationService service;
  final double maxHeight;
  final ValueChanged<AppNotification> onOpen;

  const _NotificationPanel({
    required this.service,
    required this.maxHeight,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 32,
            spreadRadius: 1,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListenableBuilder(
            listenable: service,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: const Color(0xFFF1F5F9),
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Notificaciones',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: service.unreadCount == 0
                              ? null
                              : service.markAllAsRead,
                          child: const Text(
                            'Marcar todas como leídas',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.cardBorder),
                  Flexible(child: _body()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (service.loading && service.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (service.hasError && service.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No se pudieron cargar las notificaciones.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            TextButton(
              onPressed: service.refresh,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (service.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 28,
              color: AppColors.textMuted,
            ),
            SizedBox(height: 8),
            Text(
              'No tienes notificaciones.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: service.items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.cardBorder),
      itemBuilder: (_, i) => _NotificationTile(
        n: service.items[i],
        onTap: () => onOpen(service.items[i]),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification n;
  final VoidCallback onTap;

  const _NotificationTile({required this.n, required this.onTap});

  (IconData, Color) get _style => switch (n.tipo) {
    'pago_reportado' => (Icons.receipt_long, AppColors.primaryBlue),
    'pago_aprobado' => (Icons.check_circle, const Color(0xFF059669)),
    'pago_rechazado' => (Icons.cancel, Colors.redAccent),
    'cuota_nueva' => (Icons.description_outlined, const Color(0xFFD97706)),
    _ => (Icons.notifications, AppColors.textMuted),
  };

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Ahora';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    if (d.inDays < 7) return 'hace ${d.inDays} d';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.leida ? Colors.white : const Color(0xFFEFF6FF),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.titulo,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: n.leida ? FontWeight.w600 : FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    n.mensaje,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ago(n.creadaAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (!n.leida)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
