import 'package:shared_preferences/shared_preferences.dart';

// Ubicación sugerida: lib/core/session/idle_session_store.dart

/// Guarda la última actividad del usuario en el almacenamiento local para
/// detectar inactividad AUNQUE se cierre la pestaña o el navegador: al volver,
/// la sesión que Supabase restauró se invalida si pasó el tiempo límite.
class IdleSessionStore {
  static const _key = 'ultima_actividad_ms';

  static Future<void> touch([DateTime? at]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, (at ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Última actividad registrada (también por otras pestañas), o null.
  static Future<DateTime?> last() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // lee lo escrito por otras pestañas
      final ms = prefs.getInt(_key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
