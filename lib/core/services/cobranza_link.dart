import 'package:flutter/foundation.dart';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Enlace profundo de los correos de cobranza:
/// ?action=cobranza&cuota_id=...&tipo=...&opcion=ver|reportar|convenio
/// Se captura al arrancar (antes del login) y se consume una sola vez.
class CobranzaLink {
  final String cuotaId;
  final String tipo;
  final String opcion;
  const CobranzaLink({
    required this.cuotaId,
    required this.tipo,
    required this.opcion,
  });

  static const _storageKey = 'edupago_cobranza_link';
  static const _tipos = {'recordatorio_3_dias', 'corte_dia_0', 'mora_dia_5'};
  static const _opciones = {'ver', 'reportar', 'convenio'};
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static CobranzaLink? _pending;

  static CobranzaLink? _validated(String id, String tipo, String opcion) {
    if (!_uuid.hasMatch(id) ||
        !_tipos.contains(tipo) ||
        !_opciones.contains(opcion)) {
      return null;
    }
    return CobranzaLink(cuotaId: id, tipo: tipo, opcion: opcion);
  }

  /// Llamar en main() antes de runApp.
  static void captureFromUrl() {
    if (!kIsWeb) return;
    final uri = Uri.base;
    if (uri.queryParameters['action'] != 'cobranza') return;

    final link = _validated(
      uri.queryParameters['cuota_id'] ?? '',
      uri.queryParameters['tipo'] ?? '',
      uri.queryParameters['opcion'] ?? 'ver',
    );
    if (link == null) return;

    _pending = link;
    try {
      html.window.sessionStorage[_storageKey] =
          '${link.cuotaId}|${link.tipo}|${link.opcion}';
    } catch (_) {}

    // Limpia la barra de direcciones para no reprocesar el enlace.
    final fragment = uri.fragment.isNotEmpty ? '#${uri.fragment}' : '';
    html.window.history.replaceState(null, '', '${uri.path}$fragment');
  }

  /// Devuelve el enlace pendiente (si hay) y lo elimina.
  static CobranzaLink? take() {
    var link = _pending;
    _pending = null;
    if (kIsWeb) {
      try {
        final raw = html.window.sessionStorage[_storageKey];
        html.window.sessionStorage.remove(_storageKey);
        if (link == null && raw != null) {
          final p = raw.split('|');
          if (p.length == 3) link = _validated(p[0], p[1], p[2]);
        }
      } catch (_) {}
    }
    return link;
  }
}