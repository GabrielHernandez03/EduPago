import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';

// Ubicación: lib/core/widgets/notification_bell.dart

/// Campana del encabezado: contador de no leídas, panel desplegable con la
/// lista, aviso emergente al llegar una notificación nueva en tiempo real,
/// borrado individual / total y "Ver más" para listas largas.
///
/// El panel es una capa flotante (Overlay) SIN fondo bloqueante: la página de
/// atrás sigue haciendo scroll y recibiendo clics mientras está abierto. Se
/// cierra al tocar fuera de él, al tocar de nuevo la campana o al abrir una
/// notificación.
class NotificationBell extends StatefulWidget {
  /// Se ejecuta al tocar una notificación (p. ej. para cambiar de pestaña).
  final ValueChanged<AppNotification>? onOpen;

  const NotificationBell({super.key, this.onOpen});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final NotificationService _service;
  // El panel y la campana tienen controladores independientes para que abrir
  // las notificaciones no interrumpa la animación de aviso.
  late final AnimationController _anim;
  late final AnimationController _bellAnim;
  final Object _tapGroup = Object();
  final GlobalKey _buttonKey = GlobalKey();

  static const Color _amber = Color(0xFFB45309);
  static const Color _amberLight = Color(0xFFFFF7ED);
  static const Color _amberBorder = Color(0xFFFCD34D);
  static const Duration _hoverDuration = Duration(milliseconds: 180);

  // Posición de la campana con respecto al Overlay.
  Rect _anchor = Rect.zero;
  Size _overlaySize = Size.zero;

  OverlayEntry? _entry;
  OverlayEntry? _closingEntry;

  bool _hovered = false;
  bool _ringing = false;
  bool _checkedInitialUnread = false;
  bool _pendingRing = false;
  bool _initialDelayElapsed = false;
  Timer? _initialDelayTimer;

  static const Duration _initialRingDelay = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bellAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    // El aviso solo puede sonar a partir de los 5 segundos de abrir el panel,
    // independientemente de si el dashboard ya terminó su carga inicial.
    _initialDelayTimer = Timer(_initialRingDelay, () {
      if (!mounted) return;
      _initialDelayElapsed = true;
      if (_pendingRing) _requestRing();
    });
    _service = NotificationService()..onNew = _onNew;
    _service.addListener(_onServiceChanged);
    // Se invoca al entrar al dashboard tras login; no hace falta alterar el
    // flujo de autenticación de LoginScreen.
    _service.start();
  }

  void _requestRing() {
    if (!mounted) return;
    if (!_initialDelayElapsed) {
      // Varias notificaciones durante los 5 segundos producen un solo aviso.
      _pendingRing = true;
      return;
    }
    _pendingRing = false;
    _ringBell();
  }

  // La primera carga puede tardar; esperamos a que Supabase devuelva el
  // estado real, evitando que una campana sin notificaciones se anime.
  void _onServiceChanged() {
    if (_checkedInitialUnread || _service.loading || _service.hasError) return;
    _checkedInitialUnread = true;
    if (_service.unreadCount == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestRing();
    });
  }

  @override
  void dispose() {
    _initialDelayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _entry?.remove();
    _entry = null;
    _closingEntry?.remove();
    _closingEntry = null;
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    _anim.dispose();
    _bellAnim.dispose();
    super.dispose();
  }

  // También anima la campana si entra una notificación mediante Realtime.
  void _onNew(AppNotification n) {
    if (!mounted) return;
    _requestRing();
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

  Future<void> _ringBell() async {
    if (!mounted || _ringing) return;
    // Respeta la configuración de accesibilidad del usuario.
    // El icono y el contador siguen indicando las no leídas sin animación.
    if (MediaQuery.disableAnimationsOf(context)) return;
    setState(() => _ringing = true);
    try {
      await _bellAnim.forward(from: 0);
    } catch (_) {
      // El controlador se puede cancelar al abandonar la pantalla.
    } finally {
      if (mounted) setState(() => _ringing = false);
    }
  }

  void _toggle() => _entry == null ? _open() : _close();

  /// Mide la campana respecto al Overlay. Se llama fuera del layout.
  void _measure() {
    final bell = context.findRenderObject();
    final overlayBox = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    if (bell is! RenderBox || overlayBox is! RenderBox) return;
    if (!bell.attached || !bell.hasSize || !overlayBox.hasSize) return;
    _anchor = bell.localToGlobal(Offset.zero, ancestor: overlayBox) & bell.size;
    _overlaySize = overlayBox.size;
  }

  @override
  void didChangeMetrics() {
    if (_entry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entry == null) return;
      _measure();
      _entry?.markNeedsBuild();
    });
  }

  void _open() {
    _closingEntry?.remove();
    _closingEntry = null;

    _measure();
    _service.refresh(silent: true);

    final entry = OverlayEntry(
      builder: (ctx) {
        final screen = MediaQuery.sizeOf(ctx);
        final width = math.min(380.0, screen.width - 24);
        final maxHeight = math.max(220.0, math.min(520.0, screen.height - 90));
        final right = math.max(12.0, _overlaySize.width - _anchor.right);
        return Positioned(
          right: right,
          top: _anchor.bottom + 8,
          width: width,
          child: TapRegion(
            groupId: _tapGroup,
            onTapOutside: (_) => _close(),
            child: AnimatedBuilder(
              animation: _anim,
              child: _NotificationPanel(
                service: _service,
                maxHeight: maxHeight,
                onOpen: (n) {
                  _service.markAsRead(n.id);
                  _close();
                  widget.onOpen?.call(n);
                },
              ),
              builder: (context, child) {
                final reversing = _anim.status == AnimationStatus.reverse;
                final v = (reversing ? Curves.easeInCubic : Curves.easeOutCubic)
                    .transform(_anim.value.clamp(0.0, 1.0).toDouble());
                return Opacity(
                  opacity: v,
                  child: Transform.translate(
                    offset: Offset(0, (1 - v) * -12),
                    child: ClipRect(clipper: _RevealClipper(v), child: child),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _anim.forward(from: 0);
    setState(() {});
  }

  Future<void> _close() async {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    _closingEntry = entry;
    if (mounted) setState(() {});
    try {
      await _anim.reverse();
    } catch (_) {}
    if (identical(_closingEntry, entry)) {
      entry.remove();
      _closingEntry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final unread = _service.unreadCount;
        // Solo la campana gira. Ni el badge ni el área clicable se mueven.
        // Cuando existen no leídas, el icono sigue ámbar como recordatorio.
        final isHighlighted = _hovered || _ringing;
        final iconColor = (isHighlighted || unread > 0)
            ? _amber
            : AppColors.darkNavy;

        final button = Semantics(
          button: true,
          label: unread == 0
              ? 'Notificaciones, ninguna sin leer'
              : 'Notificaciones, $unread sin leer',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedScale(
              scale: _hovered ? 1.045 : 1.0,
              duration: _hoverDuration,
              curve: Curves.easeOutCubic,
              child: InkWell(
                key: _buttonKey,
                onTap: _toggle,
                borderRadius: BorderRadius.circular(12),
                hoverColor: Colors.transparent,
                splashColor: _amber.withValues(alpha: 0.10),
                focusColor: _amberLight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      width: 46,
                      height: 46,
                      duration: _hoverDuration,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: isHighlighted ? _amberLight : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isHighlighted
                              ? _amberBorder
                              : AppColors.cardBorder,
                        ),
                        boxShadow: isHighlighted
                            ? [
                                BoxShadow(
                                  color: _amber.withValues(alpha: 0.15),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : const [],
                      ),
                      alignment: Alignment.center,
                      child: AnimatedBuilder(
                        animation: _bellAnim,
                        builder: (context, child) {
                          final t = _bellAnim.value;
                          // Oscilación más prolongada (2,6 s) que se
                          // amortigua de forma progresiva hasta detenerse.
                          final angle = _ringing
                              ? math.sin(t * math.pi * 14) *
                                    0.30 *
                                    (1 - t) *
                                    (1 - 0.35 * t)
                              : 0.0;
                          return Transform.rotate(
                            alignment: Alignment.topCenter,
                            angle: angle,
                            child: child,
                          );
                        },
                        child: Icon(
                          Icons.notifications_none_rounded,
                          size: 22,
                          color: iconColor,
                        ),
                      ),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -5,
                        top: -5,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: AppColors.errorRed,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );

        return TapRegion(
          groupId: _tapGroup,
          child: _entry != null
              ? button
              : Tooltip(
                  message: unread > 0
                      ? '$unread notificaciones sin leer'
                      : 'Notificaciones',
                  child: button,
                ),
        );
      },
    );
  }
}

class _NotificationPanel extends StatefulWidget {
  final NotificationService service;
  final double maxHeight;
  final ValueChanged<AppNotification> onOpen;

  const _NotificationPanel({
    required this.service,
    required this.maxHeight,
    required this.onOpen,
  });

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  static const _step = 5; // cuántas se muestran al inicio y por cada "Ver más"

  int _visible = _step;
  bool _confirmClear = false;

  NotificationService get _s => widget.service;

  Future<void> _showMore() async {
    setState(() => _visible += _step);
    if (_visible > _s.items.length && _s.hasMore) {
      await _s.loadMore();
    }
  }

  Future<void> _clearAll() async {
    setState(() {
      _confirmClear = false;
      _visible = _step;
    });
    await _s.deleteAll();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF94A3B8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: ListenableBuilder(
            listenable: _s,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
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

  Widget _header() {
    final hasItems = _s.items.isNotEmpty;
    final disabledOnBlue = AppColors.tint(Colors.white, 0.55);
    return Container(
      color: AppColors.primaryBlue,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: _confirmClear
          ? Row(
              children: [
                const Expanded(
                  child: Text(
                    '¿Borrar todas?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _confirmClear = false),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: _clearAll,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.errorRed,
                  ),
                  child: const Text(
                    'Borrar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                const Expanded(
                  child: Text(
                    'Notificaciones',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _s.unreadCount == 0 ? null : _s.markAllAsRead,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: disabledOnBlue,
                  ),
                  child: const Text(
                    'Marcar todas como leídas',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: 'Borrar todas',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: Colors.white,
                  disabledColor: disabledOnBlue,
                  onPressed: hasItems
                      ? () => setState(() => _confirmClear = true)
                      : null,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
    );
  }

  Widget _body() {
    if (_s.loading && _s.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_s.hasError && _s.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No se pudieron cargar las notificaciones.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            TextButton(onPressed: _s.refresh, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_s.items.isEmpty) {
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

    final items = _s.items;
    final shown = math.min(_visible, items.length);
    final showMore = _visible < items.length || _s.hasMore;

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: shown + (showMore ? 1 : 0),
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.cardBorder),
      itemBuilder: (_, i) {
        if (i == shown) {
          return SizedBox(
            height: 44,
            child: _s.loadingMore
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: _showMore,
                    child: const Text(
                      'Ver más',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          );
        }
        final n = items[i];
        return _NotificationTile(
          n: n,
          onTap: () => widget.onOpen(n),
          onDelete: () => _s.delete(n.id),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification n;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.n,
    required this.onTap,
    required this.onDelete,
  });

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
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          n.titulo,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: n.leida
                                ? FontWeight.w600
                                : FontWeight.bold,
                            color: AppColors.darkNavy,
                          ),
                        ),
                      ),
                      if (!n.leida)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
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
            IconButton(
              tooltip: 'Borrar',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              color: AppColors.textMuted,
              onPressed: onDelete,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Revela el panel de arriba hacia abajo. El margen de 40 px evita recortar
/// la sombra mientras se anima.
class _RevealClipper extends CustomClipper<Rect> {
  final double progress;
  const _RevealClipper(this.progress);

  @override
  Rect getClip(Size size) {
    const m = 40.0;
    return Rect.fromLTRB(
      -m,
      -m,
      size.width + m,
      progress >= 1.0 ? size.height + m : size.height * progress,
    );
  }

  @override
  bool shouldReclip(_RevealClipper old) => old.progress != progress;
}
