import 'dart:async';
import 'dart:math' as math;
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

/// Carga las notificaciones del usuario y escucha las nuevas en tiempo real
/// (Supabase Realtime). Las notificaciones las crean triggers en la base de
/// datos; este servicio solo las lee y las marca como leídas. La RLS garantiza
/// que cada usuario únicamente reciba las suyas.
class NotificationService extends ChangeNotifier {
  NotificationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const _table = 'notificaciones_app';
  static const _pageSize = 20;

  final SupabaseClient _client;
  RealtimeChannel? _channel;
  bool _disposed = false;
  bool _firstSubscribe = true;

  List<AppNotification> _items = const [];
  bool _loading = true;
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;

  /// Se llama cuando llega una notificación nueva en vivo (para un aviso).
  void Function(AppNotification n)? onNew;

  List<AppNotification> get items => _items;
  bool get loading => _loading;
  bool get hasError => _error;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;
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
          table: _table,
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

  List<AppNotification> _parse(dynamic rows) => (rows as List)
      .whereType<Map>()
      .map((m) => AppNotification.fromMap(Map<String, dynamic>.from(m)))
      .toList();

  /// Recarga lo ya cargado (como mínimo la primera página).
  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = false;
      _notify();
    }
    try {
      final limit = math.max(_pageSize, _items.length);
      final rows = await _client
          .from(_table)
          .select()
          .order('creada_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);
      _items = _parse(rows);
      _hasMore = _items.length >= limit;
      _error = false;
    } catch (e) {
      debugPrint('Error cargando notificaciones: $e');
      _error = true;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Carga la siguiente página (las más antiguas).
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    _notify();
    try {
      final from = _items.length;
      final rows = await _client
          .from(_table)
          .select()
          .order('creada_at', ascending: false)
          .order('id', ascending: false)
          .range(from, from + _pageSize - 1);
      final more = _parse(rows);
      final known = _items.map((n) => n.id).toSet();
      _items = [..._items, ...more.where((n) => !known.contains(n.id))];
      _hasMore = more.length >= _pageSize;
    } catch (e) {
      debugPrint('Error cargando más notificaciones: $e');
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  Future<void> markAsRead(String id) async {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx < 0 || _items[idx].leida) return;
    _items = [..._items]..[idx] = _items[idx].copyWith(leida: true);
    _notify();
    try {
      await _client.from(_table).update({'leida': true}).eq('id', id);
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
          .from(_table)
          .update({'leida': true})
          .eq('leida', false); // la RLS limita a las del propio usuario
    } catch (e) {
      debugPrint('Error marcando todas como leídas: $e');
      refresh(silent: true);
    }
  }

  /// Borra una notificación (se quita al instante; si el servidor no la
  /// borró, se recarga la lista real).
  Future<void> delete(String id) async {
    if (!_items.any((n) => n.id == id)) return;
    _items = _items.where((n) => n.id != id).toList();
    _notify();
    try {
      final res = await _client.from(_table).delete().eq('id', id).select('id');
      if ((res as List).isEmpty) {
        debugPrint(
          'No se pudo borrar la notificación (¿falta la política DELETE?)',
        );
        refresh(silent: true);
      }
    } catch (e) {
      debugPrint('Error borrando notificación: $e');
      refresh(silent: true);
    }
  }

  /// Borra todas las notificaciones del usuario.
  Future<void> deleteAll() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || _items.isEmpty) return;
    _items = const [];
    _hasMore = false;
    _notify();
    try {
      await _client.from(_table).delete().eq('perfil_id', uid).select('id');
    } catch (e) {
      debugPrint('Error borrando notificaciones: $e');
    }
    refresh(silent: true); // refleja el estado real del servidor
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
