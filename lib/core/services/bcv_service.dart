import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class BcvRateData {
  final double rate;
  final String dateFormatted;
  final bool isCached;

  BcvRateData({
    required this.rate,
    required this.dateFormatted,
    required this.isCached,
  });
}

class BcvService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Endpoint 1: DolarAPI (Soporte CORS nativo para Web)
  final String _primaryApiUrl = 'https://ve.dolarapi.com/v1/dolares/oficial';
  // Endpoint 2: PyDolarVE (Respaldo directo de API)
  final String _secondaryApiUrl = 'https://pydolarvenezuela-api.vercel.app/api/v1/dollar/unit/bcv';

  Future<BcvRateData> getLatestBcvRate() async {
    // 1. Intentar consumir API Principal
    try {
      debugPrint('Consultando API oficial DolarAPI BCV...');
      final response = await http
          .get(Uri.parse(_primaryApiUrl))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final double apiRate = (data['promedio'] as num).toDouble();
        
        DateTime apiDate = DateTime.now();
        if (data['fechaActualizacion'] != null) {
          apiDate = DateTime.tryParse(data['fechaActualizacion'].toString()) ?? DateTime.now();
        }

        final String todayStr = DateFormat('yyyy-MM-dd').format(apiDate);
        final String formattedDate = DateFormat('dd/MM/yyyy hh:mm a').format(apiDate);

        debugPrint('Tasa BCV obtenida en vivo desde API: $apiRate VES ($formattedDate)');

        // Actualizar la base de datos en segundo plano para respaldar la consulta
        _updateRateInSupabase(todayStr, apiRate);

        return BcvRateData(
          rate: apiRate,
          dateFormatted: 'Tasa BCV oficial ($formattedDate)',
          isCached: false,
        );
      }
    } catch (e) {
      debugPrint('Error en API Principal: $e. Probando API secundaria...');
    }

    // 2. Intentar consumir API Secundaria
    try {
      final response = await http
          .get(Uri.parse(_secondaryApiUrl))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final double apiRate = (data['price'] as num).toDouble();
        final DateTime now = DateTime.now();
        final String todayStr = DateFormat('yyyy-MM-dd').format(now);
        final String formattedDate = DateFormat('dd/MM/yyyy hh:mm a').format(now);

        _updateRateInSupabase(todayStr, apiRate);

        return BcvRateData(
          rate: apiRate,
          dateFormatted: 'Tasa BCV oficial ($formattedDate)',
          isCached: false,
        );
      }
    } catch (e) {
      debugPrint('Error en API Secundaria: $e');
    }

    // 3. Si ambas APIs externas fallan, recurrir a la base de datos
    debugPrint('APIs no disponibles. Usando lectura de contingencia en Supabase...');
    return await _getRateFromCache();
  }

  Future<void> _updateRateInSupabase(String fecha, double tasa) async {
    try {
      await _supabase.from('tasas_cambio').upsert({
        'fecha': fecha,
        'usd_ves': tasa,
        'fuente': 'API_BCV_AUTOMATICO',
        'creado_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fecha');
    } catch (e) {
      debugPrint('Error al guardar en BD: $e');
    }
  }

  Future<BcvRateData> _getRateFromCache() async {
    try {
      final response = await _supabase
          .from('tasas_cambio')
          .select('usd_ves, fecha, creado_at')
          .order('fecha', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null && response['usd_ves'] != null) {
        final double cachedRate = (response['usd_ves'] as num).toDouble();
        final DateTime rawDate = DateTime.parse(response['creado_at'] ?? response['fecha']);
        final String formattedDate = DateFormat('dd/MM/yyyy hh:mm a').format(rawDate);

        return BcvRateData(
          rate: cachedRate,
          dateFormatted: 'Tasa BCV del $formattedDate (Caché)',
          isCached: true,
        );
      }
    } catch (e) {
      debugPrint('Error leyendo caché de Supabase: $e');
    }

    return BcvRateData(
      rate: 64.25,
      dateFormatted: 'Tasa BCV de respaldo',
      isCached: true,
    );
  }
}