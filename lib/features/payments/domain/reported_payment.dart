/// Suma real aplicada a las cuotas de un estudiante por un pago aprobado.
class StudentPaymentAllocation {
  const StudentPaymentAllocation({
    required this.name,
    required this.amountUsd,
    required this.quotaCount,
  });

  final String name;
  final double? amountUsd;
  final int quotaCount;
}

/// Modelo flexible: el backend puede incluir columnas adicionales o distintas
/// versiones de nombres sin bloquear la pantalla.
class ReportedPayment {
  final Map<String, dynamic> raw;
  final List<Map<String, dynamic>> _notifications = [];
  List<String> _appliedQuotaLabels = const [];
  int _appliedQuotaCount = 0;
  bool _quotaEstimate = false;
  List<StudentPaymentAllocation> _studentAllocations = const [];

  ReportedPayment(this.raw);

  void setStudentAllocations(List<StudentPaymentAllocation> allocations) {
    _studentAllocations = allocations;
  }

  List<StudentPaymentAllocation> get studentAllocations =>
      List.unmodifiable(_studentAllocations);

  void setAppliedQuotaLabels(
    List<String> labels,
    int quotaCount, {
    List<String> concepts = const [],
    List<String> periods = const [],
    bool estimated = false,
  }) {
    _appliedQuotaLabels = labels;
    _quotaEstimate = estimated;
    _appliedQuotaCount = quotaCount;
  }

  bool get hasQuotaDetails => _appliedQuotaLabels.isNotEmpty;
  bool get quotaEstimate => _quotaEstimate;
  List<String> get quotaDetails => List.unmodifiable(_appliedQuotaLabels);

  String get installmentHeading {
    return 'CONCEPTO';
  }

  String get installmentCardValue {
    if (_appliedQuotaLabels.isEmpty) {
      return normalizedStatus == 'pendiente'
          ? 'Se asignará al aprobar'
          : installmentLabel;
    }
    final first = _appliedQuotaLabels.first;
    if (_appliedQuotaLabels.length == 1) {
      return first;
    }
    final extra = _appliedQuotaLabels.length - 1;
    return '$first (+$extra ${extra == 1 ? 'concepto' : 'conceptos'})';
  }

  String _get(List<String> keys) {
    for (final k in keys) {
      final str = raw[k]?.toString().trim() ?? '';
      if (str.isNotEmpty && str.toLowerCase() != 'null') {
        return str;
      }
    }
    return '';
  }

  String get id => _get(['id']);
  String get shortId => id.length > 8 ? id.substring(0, 8) : id;
  String get displayReference =>
      reference.isEmpty ? '#$shortId' : '· $reference';
  String get reference => _get([
    'referencia',
    'referencia_pago',
    'referencia_bancaria',
    'numero_referencia',
    'nro_referencia',
    'numero_operacion',
  ]);
  String get method {
    final rawMethod = _get([
      'metodo_pago',
      'metodo',
      'medio_pago',
      'tipo_pago',
    ]);
    return switch (rawMethod.toLowerCase()) {
      'pago_movil' || 'pago móvil' || 'pago movil' => 'Pago móvil',
      'transferencia_bancaria' => 'Transferencia bancaria',
      'efectivo_usd' => 'Efectivo USD',
      _ => rawMethod,
    };
  }

  String get bank =>
      _get(['banco_origen', 'banco', 'banco_emisor', 'entidad_bancaria']);
  String get concept =>
      _get([
        'concepto',
        'descripcion',
        'periodo',
        'observacion_concepto',
      ]).isEmpty
      ? 'Pago escolar'
      : _get(['concepto', 'descripcion', 'periodo', 'observacion_concepto']);

  /// Prioriza los conceptos reales de pago_aplicaciones -> cuotas y
  /// conceptos_cobro. Si no hay aplicaciones, usa campos explícitos de pagos.
  /// Nunca infiere la mensualidad según la fecha o el monto depositado.
  String get installmentLabel {
    if (_appliedQuotaLabels.isNotEmpty) {
      final label = _appliedQuotaLabels.join(' · ');
      // Una familia puede pagar la misma mensualidad de varios estudiantes.
      return _appliedQuotaCount > _appliedQuotaLabels.length
          ? '$label ($_appliedQuotaCount cuotas)'
          : label;
    }

    final named = _get([
      'nombre_cuota',
      'cuota_nombre',
      'nombre_mensualidad',
      'mensualidad',
      'concepto_cuota',
      'periodo_cuota',
      'cuota_periodo',
      'periodo_pagado',
      'mes_correspondiente',
    ]);
    if (named.isNotEmpty) {
      return named;
    }

    // Si el backend conserva las cuotas en un JSON o arreglo, mostramos los
    // nombres disponibles; nunca mostramos UUIDs como si fueran cuotas.
    final assigned = <String>[];
    for (final key in ['cuotas', 'mensualidades', 'detalle_cuotas']) {
      final data = raw[key];
      if (data is! List) {
        continue;
      }
      for (final entry in data) {
        if (entry is! Map) {
          continue;
        }
        final detail = Map<String, dynamic>.from(entry);
        for (final candidate in [
          'nombre_cuota',
          'concepto',
          'periodo',
          'nombre',
          'mes',
        ]) {
          final value = detail[candidate]?.toString().trim() ?? '';
          if (value.isNotEmpty && !assigned.contains(value)) {
            assigned.add(value);
            break;
          }
        }
      }
    }
    if (assigned.isNotEmpty) {
      return assigned.join(' · ');
    }

    final month = _get(['mes_cuota', 'mes_mensualidad', 'mes_pagado', 'mes']);
    final year = _get(['anio_cuota', 'ano_cuota', 'anio', 'ano', 'año']);
    if (month.isNotEmpty) {
      const months = [
        'enero',
        'febrero',
        'marzo',
        'abril',
        'mayo',
        'junio',
        'julio',
        'agosto',
        'septiembre',
        'octubre',
        'noviembre',
        'diciembre',
      ];
      final n = int.tryParse(month);
      final name = n != null && n >= 1 && n <= 12 ? months[n - 1] : month;
      return year.isEmpty ? name : '$name $year';
    }

    final number = _get(['numero_cuota', 'nro_cuota', 'cuota_numero']);
    if (number.isNotEmpty) {
      return 'Cuota $number';
    }

    final period = _get(['periodo']);
    if (period.isNotEmpty) {
      return period;
    }

    // Algunas instalaciones solo guardan la cuota dentro del concepto.
    final description = _get([
      'concepto',
      'descripcion',
      'observacion_concepto',
    ]);
    if (RegExp(
      r'\b(mensualidad|cuota|inscripci[oó]n|matr[ií]cula|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\b',
      caseSensitive: false,
    ).hasMatch(description)) {
      return description;
    }
    return normalizedStatus == 'pendiente'
        ? 'Se asignará al aprobar'
        : 'Cuotas sin detalle disponible';
  }

  DateTime? _date(List<String> keys) {
    for (final k in keys) {
      final result = DateTime.tryParse(raw[k]?.toString() ?? '');
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  DateTime? get createdAt => _date(['creado_at', 'created_at']);
  DateTime? get paymentDate => _date(['fecha_pago']);
  DateTime? get confirmedAt =>
      _date(['revisado_at', 'fecha_revision', 'aprobado_at', 'actualizado_at']);

  String get normalizedStatus {
    final status = _get(['estado', 'status']).toLowerCase().trim();
    if (['aprobado', 'aprobada', 'validado', 'confirmado'].contains(status)) {
      return 'aprobado';
    }
    if (['rechazado', 'rechazada', 'denegado', 'invalidado'].contains(status)) {
      return 'rechazado';
    }
    if ([
      'pendiente',
      'en_revision',
      'en revisión',
      'en_espera',
      'reportado',
      'espera',
      'en espera',
    ].contains(status)) {
      return 'pendiente';
    }
    return status.isEmpty ? 'pendiente' : status;
  }

  String get statusLabel => switch (normalizedStatus) {
    'pendiente' => 'En espera',
    'aprobado' => 'Aprobado',
    'rechazado' => 'Rechazado',
    final other => other,
  };

  /// Valor contable estimado en USD, solo para previsualizar FIFO.
  /// La aplicación definitiva del pago la determina la base de datos.
  double get amountUsdEquivalent {
    final converted = raw['monto_usd_equivalente'];
    if (converted != null) {
      return converted is num
          ? converted.toDouble()
          : (double.tryParse(converted.toString()) ?? 0);
    }
    final rawAmount = raw['monto'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : (double.tryParse(rawAmount?.toString() ?? '') ?? 0);
    final currency = _get(['moneda']).toUpperCase();
    if (currency == 'USD') {
      return amount;
    }
    final tasa = raw['tasa_aplicada'];
    final rate = tasa is num
        ? tasa.toDouble()
        : (double.tryParse(tasa?.toString() ?? '') ?? 0);
    return rate > 0 ? amount / rate : 0;
  }

  String get displayAmount {
    final rawAmount = raw['monto'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse('$rawAmount') ?? 0;
    final fixed = amount.abs().toStringAsFixed(2).split('.');
    final n = fixed[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final text = '${amount < 0 ? '-' : ''}$n,${fixed[1]}';
    final currency = _get(['moneda']).toUpperCase();
    return currency == 'VES' || currency == 'BS' || currency == 'BS.'
        ? 'Bs. $text'
        : '\$$text ${currency.isEmpty ? 'USD' : currency}';
  }

  void addNotification(Map<String, dynamic> item) => _notifications.add(item);

  static void _append(List<String> output, Set<String> seen, dynamic value) {
    if (value == null) {
      return;
    }
    if (value is List) {
      for (final sub in value) {
        _append(output, seen, sub);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        _append(output, seen, entry.value);
      }
      return;
    }
    final text = value.toString().trim();
    if (text.isEmpty || ['null', 'false', 'true'].contains(text.toLowerCase())) {
      return;
    }
    if (seen.add(text.toLowerCase())) {
      output.add(text);
    }
  }

  List<String> get rejectionReasons {
    final values = <String>[];
    final seen = <String>{};
    for (final entry in raw.entries) {
      final k = entry.key.toLowerCase();
      if (k.contains('motivo') ||
          k.contains('razon_rechazo') ||
          k.contains('razón') ||
          k.contains('justificacion') ||
          k.contains('causa_rechazo') ||
          k.contains('detalle_rechazo') ||
          (normalizedStatus == 'rechazado' &&
              (k.contains('observ') ||
                  k.contains('comentario') ||
                  k.contains('nota_rechazo') ||
                  k.contains('nota_admin')))) {
        _append(values, seen, entry.value);
      }
    }
    if (normalizedStatus == 'rechazado') {
      for (final k in [
        'observaciones',
        'observacion',
        'observacion_admin',
        'observaciones_admin',
        'comentario_admin',
        'comentarios_admin',
        'nota_admin',
      ]) {
        _append(values, seen, raw[k]);
      }
    }
    for (final note in _notifications) {
      if (note['tipo']?.toString() != 'pago_rechazado') {
        continue;
      }
      final data = note['datos'];
      if (data is Map) {
        for (final item in data.entries) {
          final name = item.key.toString().toLowerCase();
          if (name.contains('motivo') ||
              name.contains('razon') ||
              name.contains('observacion') ||
              name.contains('comentario')) {
            _append(values, seen, item.value);
          }
        }
      }
      // Solo tratamos el mensaje como motivo si explicita alguna causa.
      // Una notificación genérica «Pago rechazado» NO es un motivo.
      final message = note['mensaje']?.toString() ?? '';
      if (RegExp(
        r'motivo|raz[oó]n|debido|porque|causa|inconsisten|incorrect|inv[aá]lid',
        caseSensitive: false,
      ).hasMatch(message)) {
        _append(values, seen, message);
      }
    }
    return values;
  }

  List<String> get otherNotes {
    final result = <String>[];
    final seen = <String>{};
    if (normalizedStatus != 'rechazado') {
      for (final key in [
        'observaciones',
        'observacion',
        'comentario_admin',
        'nota_admin',
      ]) {
        _append(result, seen, raw[key]);
      }
    } else {
      for (final note in _notifications) {
        if (note['tipo']?.toString() == 'pago_rechazado') {
          final message = note['mensaje']?.toString().trim() ?? '';
          if (message.isNotEmpty && !rejectionReasons.contains(message)) {
            _append(result, seen, 'Mensaje de notificación: $message');
          }
        }
      }
    }
    return result;
  }
}
