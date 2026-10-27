import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Ubicación: lib/core/services/notification_service.dart

/// Una notificación de la tabla `notificaciones_app`.
class AppNotification {
  final String id;
  final String
  tipo; // pago_reportado | pago_aprobado | pago_rechazado | cuota_nueva
  final String titulo;
  final String mensaje;
  final Map<String, dynamic> datos;
  final bool leida;
  final DateTime creadaAt;

  const AppNotification({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.datos,
    required this.leida,
    required this.creadaAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    final d = m['datos'];
    return AppNotification(
      id: m['id'].toString(),
      tipo: (m['tipo'] ?? '').toString(),
      titulo: (m['titulo'] ?? '').toString(),
      mensaje: (m['mensaje'] ?? '').toString(),
      datos: d is Map ? Map<String, dynamic>.from(d) : const {},
      leida: m['leida'] == true,
      creadaAt:
          DateTime.tryParse((m['creada_at'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
    );
  }

  AppNotification copyWith({bool? leida}) => AppNotification(
    id: id,
    tipo: tipo,
    titulo: titulo,
    mensaje: mensaje,
    datos: datos,
    leida: leida ?? this.leida,
    creadaAt: creadaAt,
  );
}

/// Carga las notificaciones_app del usuario y escucha las nuevas en tiempo real
/// (Supabase Realtime). Las notificaciones_app las crean triggers en la base de
/// datos; este servicio solo las lee y las marca como leídas. La RLS garantiza
/// que cada usuario únicamente reciba las suyas.
class NotificationService extends ChangeNotifier {
  NotificationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  RealtimeChannel? _channel;
  bool _disposed = false;
  bool _firstSubscribe = true;

  List<AppNotification> _items = const [];
  bool _loading = true;
  bool _error = false;

  /// Se llama cuando llega una notificación nueva en vivo (para un aviso).
  void Function(AppNotification n)? onNew;

  List<AppNotification> get items => _items;
  bool get loading => _loading;
  bool get hasError => _error;
  int get unreadCount => _items.where((n) => !n.leida).length;

  Future<void> start() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      _loading = false;
      _notify();
      return;
    }

    await refresh();
    if (_disposed) return;

    _channel = _client
        .channel('notificaciones_app-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificaciones_app',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'perfil_id',
            value: uid,
          ),
          callback: _onInsert,
        )
        .subscribe((status, [error]) {
          if (status != RealtimeSubscribeStatus.subscribed) return;
          // Tras una reconexión se pudo perder algo: se vuelve a cargar.
          if (_firstSubscribe) {
            _firstSubscribe = false;
          } else {
            refresh(silent: true);
          }
        });
  }

  void _onInsert(PostgresChangePayload payload) {
    final rec = payload.newRecord;
    if (rec.isEmpty) return;
    final n = AppNotification.fromMap(Map<String, dynamic>.from(rec));
    if (_items.any((x) => x.id == n.id)) return;
    _items = [n, ..._items];
    _notify();
    onNew?.call(n);
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = false;
      _notify();
    }
    try {
      final rows = await _client
          .from('notificaciones_app')
          .select()
          .order('creada_at', ascending: false)
          .limit(50);
      _items = (rows as List)
          .whereType<Map>()
          .map((m) => AppNotification.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      _error = false;
    } catch (e) {
      debugPrint('Error cargando notificaciones_app: $e');
      _error = true;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> markAsRead(String id) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx < 0 || _items[idx].leida) return;
    _items = [..._items]..[idx] = _items[idx].copyWith(leida: true);
    _notify();
    try {
      await _client
          .from('notificaciones_app')
          .update({'leida': true})
          .eq('id', id);
    } catch (e) {
      debugPrint('Error marcando notificación como leída: $e');
      refresh(silent: true); // revierte al estado real del servidor
    }
  }

  Future<void> markAllAsRead() async {
    if (unreadCount == 0) return;
    _items = _items.map((n) => n.copyWith(leida: true)).toList();
    _notify();
    try {
      await _client
          .from('notificaciones_app')
          .update({'leida': true})
          .eq('leida', false); // la RLS limita a las del propio usuario
    } catch (e) {
      debugPrint('Error marcando todas como leídas: $e');
      refresh(silent: true);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final ch = _channel;
    if (ch != null) _client.removeChannel(ch);
    super.dispose();
  }
}
