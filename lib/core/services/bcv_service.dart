import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tasa USD/VES consultada y validada; nunca contiene una tasa inventada.
class BcvRateData {
  final double rate;
  final String dateFormatted;
  final bool isCached;

  const BcvRateData({
    required this.rate,
    required this.dateFormatted,
    required this.isCached,
  });
}

/// Lee una referencia BCV reciente desde APIs de terceros o desde Supabase.
/// IMPORTANTE: este cliente solo LEE tasas_cambio. Las escrituras deben hacerse
/// desde una Edge Function/servicio programado con autorización del servidor.
class BcvService {
  BcvService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _primaryApiUrl =
      'https://ve.dolarapi.com/v1/dolares/oficial';
  static const String _secondaryApiUrl =
      'https://pydolarvenezuela-api.vercel.app/api/v1/dollar/unit/bcv';

  /// Margen de contingencia explícito, ajustable según el calendario BCV.
  /// Incluye fines de semana y algunos feriados, pero no permite datos
  /// indefinidamente antiguos.
  static const int _maxDaysOld = 5;

  Future<BcvRateData> getLatestBcvRate() async {
    final primary = await _readPrimary();
    if (primary != null) return primary;

    final secondary = await _readSecondary();
    if (secondary != null) return secondary;

    final cached = await _readSupabaseCache();
    if (cached != null) return cached;

    // Se propaga al llamador. NUNCA devolver 64,25 ni otro número ficticio.
    throw StateError(
      'No hay una tasa BCV reciente y verificable disponible. '
      'No es seguro realizar conversiones VES/USD en este momento.',
    );
  }

  Future<BcvRateData?> _readPrimary() async {
    try {
      final response = await http
          .get(Uri.parse(_primaryApiUrl))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final amount = _validRate(decoded['promedio']);
      final date = _parseDate(decoded['fechaActualizacion']);
      if (amount == null || date == null || !_isRecent(date)) return null;

      return BcvRateData(
        rate: amount,
        // DolarAPI es un agregador, no el servidor del BCV.
        dateFormatted:
            'Referencia BCV vía DolarAPI (${_formatDate(date)})',
        isCached: false,
      );
    } catch (error) {
      debugPrint('DolarAPI no disponible: $error');
      return null;
    }
  }

  Future<BcvRateData?> _readSecondary() async {
    try {
      final response = await http
          .get(Uri.parse(_secondaryApiUrl))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final amount = _validRate(decoded['price']);
      // No asumir que una API está actualizada solo porque respondió hoy.
      final date = _parseDate(
        decoded['last_update'] ??
            decoded['fechaActualizacion'] ??
            decoded['updated_at'],
      );
      if (amount == null || date == null || !_isRecent(date)) return null;

      return BcvRateData(
        rate: amount,
        dateFormatted:
            'Referencia BCV vía fuente alternativa (${_formatDate(date)})',
        isCached: false,
      );
    } catch (error) {
      debugPrint('API secundaria no disponible: $error');
      return null;
    }
  }

  Future<BcvRateData?> _readSupabaseCache() async {
    try {
      final row = await _supabase
          .from('tasas_cambio')
          .select('usd_ves, fecha, fuente')
          .order('fecha', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) return null;
      final amount = _validRate(row['usd_ves']);
      // Usar fecha de vigencia, NO creado_at (una fila antigua puede
      // reinsertarse hoy y seguir conteniendo una tasa obsoleta).
      final date = _parseDate(row['fecha']);
      if (amount == null || date == null || !_isRecent(date)) return null;

      return BcvRateData(
        rate: amount,
        dateFormatted: 'Tasa almacenada (${DateFormat('dd/MM/yyyy').format(date)})',
        isCached: true,
      );
    } catch (error) {
      debugPrint('No fue posible leer tasas_cambio: $error');
      return null;
    }
  }

  static double? _validRate(dynamic raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value.isFinite && value > 0 ? value : null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  static bool _isRecent(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final daysOld = today.difference(day).inDays;
    // No aceptar fechas futuras; el backend debe determinar la vigencia
    // aplicable de publicaciones anticipadas por el BCV.
    return daysOld >= 0 && daysOld <= _maxDaysOld;
  }

  static String _formatDate(DateTime date) =>
      DateFormat('dd/MM/yyyy hh:mm a').format(date);
}
