import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/bcv_service.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:file_selector/file_selector.dart' as fs;

class ReportPaymentDialog extends StatefulWidget {
  final String studentName;
  final String monthPeriod;
  final double amountUsd;
  final double tasaBcv;
  final String? studentId;

  const ReportPaymentDialog({
    super.key,
    this.studentName = 'Estudiante',
    this.monthPeriod = 'Mensualidad',
    this.amountUsd = 0.0,
    this.tasaBcv = 0.0,
    this.studentId,
  });

  @override
  State<ReportPaymentDialog> createState() => _ReportPaymentDialogState();
}

class _ReportPaymentDialogState extends State<ReportPaymentDialog> {
  String get _familyDisplay {
    final original = widget.studentName.trim();
    if (RegExp(r'^familia\b', caseSensitive: false).hasMatch(original)) {
      final shortName = original
          .replaceFirst(RegExp(r'^(?:familia\s+)+', caseSensitive: false), '')
          .trim();
      return shortName.isEmpty ? 'Mi familia' : 'Familia $shortName';
    }
    return original.isEmpty ? 'Representante' : original;
  }

  bool get _isVes =>
      _selectedMethod == 'Pago Móvil' ||
      _selectedMethod == 'Transferencia Bancaria';
  bool get _needsBank => _isVes;
  String? _stepError; // Solo para errores generales no asociados a un campo.
  String? _bankError;
  String? _dateError;
  String? _amountError;
  String? _proofError;
  String get _originBankValue => _selectedOriginBank ?? '';

  final SupabaseClient _supabase = Supabase.instance.client;
  final BcvService _bcvService = BcvService();

  int _currentStep = 1; // 1: Método, 2: Datos, 3: Comprobante
  bool _isSubmitted = false;
  bool _isSubmitting = false;
  bool _isCheckingRef = false;

  // Tasa BCV en vivo
  // Sin tasa conocida = 0. No se usa una tasa fija "de respaldo": un pago en
  // bolívares calculado con una tasa desactualizada genera diferencias reales.
  double _currentTasaBcv = 0.0;
  bool get _hasRate => _currentTasaBcv > 0;
  double _vesToUsd(double ves) => _hasRate ? ves / _currentTasaBcv : 0.0;

  // Paso 1: Método
  String _selectedMethod = 'Pago Móvil';

  // Paso 2: Datos y Monto
  String? _selectedOriginBank;
  // La cuenta destino no se elige: se muestra exclusivamente la configurada para el método.
  final TextEditingController _refController = TextEditingController();
  final TextEditingController _montoController = TextEditingController();
  final TextEditingController _usdAmountController = TextEditingController();
  // Pago Móvil y Transferencia se registran en VES, pero se puede ingresar
  // el monto tanto en bolívares como en dólares.
  bool _amountInUsd = true;
  bool _amountEditedByUser = false;
  DateTime _selectedDate = DateTime.now();
  bool _isRefValid = false;
  // Una referencia rechazada por el servidor debe corregirse antes de reintentar.
  bool _referenceRejectedByServer = false;
  String? _refErrorMessage;

  // Paso 3: Comprobante
  String? _attachedFileName;
  Uint8List? _attachedFileBytes;
  String _generatedReportCode = '';

  // Buscador del banco: desplegable animado en escritorio y panel inferior
  // en móvil. La búsqueda no modifica el banco seleccionado hasta confirmarlo.
  bool _bankDropdownOpen = false;
  final TextEditingController _bankSearchController = TextEditingController();
  final FocusNode _bankSearchFocus = FocusNode();

  final List<String> _destinationAccounts = [
    'Mercantil 4872',
    'Banesco 0194',
    'BNC 8812',
  ];

  // Datos bancarios oficiales del colegio
  final Map<String, String> _pagoMovilColegio = {
    'Banco': 'Mercantil (0105)',
    'RIF': 'J-30062942-0',
    'Teléfono': '0412-3456789',
    'Titular': 'U.E. Nueva Generación',
  };

  final Map<String, String> _zelleColegio = {
    'Correo': 'pagos@nuevageneracion.edu.ve',
    'Titular': 'U.E. Nueva Generación Inc.',
  };

  final Map<String, String> _transferenciaColegio = {
    'Banco': 'Mercantil',
    'Cuenta': '0105-0123-45-6789012345',
    'RIF': 'J-30062942-0',
    'Titular': 'U.E. Nueva Generación',
  };

  @override
  void initState() {
    super.initState();
    _currentTasaBcv = widget.tasaBcv > 0 ? widget.tasaBcv : 0.0;
    _updateMontoField(widget.amountUsd);
    _initDataAndRate();
  }

  @override
  void dispose() {
    _refController.dispose();
    _montoController.dispose();
    _usdAmountController.dispose();
    _bankSearchController.dispose();
    _bankSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _initDataAndRate() async {
    try {
      final bcvData = await _bcvService.getLatestBcvRate();
      if (mounted && bcvData.rate > 0) {
        setState(() {
          _currentTasaBcv = bcvData.rate;
          if (_amountError ==
              'No hay tasa BCV disponible para registrar este pago.') {
            _amountError = null;
          }
          if (_isVes) {
            // Si aún no escribió nada, actualizamos el monto sugerido.
            // Si ya escribió, respetamos la moneda elegida y solo
            // recalculamos el otro campo, nunca pisamos el campo activo.
            if (!_amountEditedByUser) {
              _updateMontoField(widget.amountUsd);
            } else if (_amountInUsd) {
              _syncConvertedAmount();
            } else {
              _syncUsdFromVes();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error obteniendo tasa BCV en diálogo: $e');
    }
  }

  void _updateMontoField(double usdAmount) {
    _usdAmountController.text = usdAmount
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    if (_isVes) {
      // El monto real del pago se mantiene en Bs., independientemente de
      // la moneda que el usuario use como entrada.
      _syncConvertedAmount();
    } else {
      _montoController.text = usdAmount.toStringAsFixed(2).replaceAll('.', ',');
    }
  }

  void _syncConvertedAmount() {
    final usd =
        double.tryParse(
          _usdAmountController.text.trim().replaceAll(',', '.'),
        ) ??
        0.0;
    final ves = _hasRate && usd.isFinite && usd > 0
        ? usd * _currentTasaBcv
        : 0.0;
    _montoController.text = ves.toStringAsFixed(2).replaceAll('.', ',');
  }

  void _syncUsdFromVes() {
    final ves =
        double.tryParse(_montoController.text.trim().replaceAll(',', '.')) ??
        0.0;
    if (!_hasRate) {
      _usdAmountController.clear();
      return;
    }
    final usd = ves.isFinite && ves > 0 ? ves / _currentTasaBcv : 0.0;
    _usdAmountController.text = usd.toStringAsFixed(2).replaceAll('.', ',');
  }

  void _setAmountInputCurrency(bool inUsd) {
    if (!_isVes || _amountInUsd == inUsd) return;
    setState(() {
      // Conserva el valor del pago ya calculado en bolívares al cambiar
      // de moneda y convierte únicamente el campo de entrada nuevo.
      if (inUsd) {
        _syncUsdFromVes();
      } else {
        _syncConvertedAmount();
      }
      _amountInUsd = inUsd;
      _amountError = null;
      _stepError = null;
    });
  }

  void _onRefChanged(String val) {
    setState(() {
      final reference = val.trim();
      _isRefValid =
          reference.length >= 4 &&
          reference.length <= 80 &&
          (_isVes
              ? RegExp(r'^[0-9]+$').hasMatch(reference)
              : RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(reference));
      _stepError = null;
      _refErrorMessage = null;
      _referenceRejectedByServer = false;
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryBlue,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateError = null;
        _stepError = null;
      });
    }
  }

  Future<void> _pickComprobanteFile() async {
    void msg(String t, {Color c = Colors.redAccent}) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
    }

    try {
      const tipos = fs.XTypeGroup(
        label: 'Comprobantes',
        extensions: ['jpg', 'jpeg', 'png', 'pdf'],
        mimeTypes: ['image/jpeg', 'image/png', 'application/pdf'],
        uniformTypeIdentifiers: ['public.jpeg', 'public.png', 'com.adobe.pdf'],
      );

      final file = await fs.openFile(acceptedTypeGroups: [tipos]);
      if (file == null) return; // el usuario canceló

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        setState(() => _proofError = 'El archivo está vacío. Adjunta otro.');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() => _proofError = 'El comprobante no puede superar 5 MB.');
        return;
      }

      final ext = file.name.split('.').last.toLowerCase();
      final valid =
          (ext == 'png' &&
              bytes.length > 7 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4E &&
              bytes[3] == 0x47) ||
          ((ext == 'jpg' || ext == 'jpeg') &&
              bytes.length > 2 &&
              bytes[0] == 0xFF &&
              bytes[1] == 0xD8 &&
              bytes[2] == 0xFF) ||
          (ext == 'pdf' &&
              bytes.length > 4 &&
              String.fromCharCodes(bytes.take(5)) == '%PDF-');
      if (!valid) {
        setState(
          () => _proofError = 'Selecciona un archivo JPG, PNG o PDF válido.',
        );
        return;
      }
      setState(() {
        _attachedFileName = file.name;
        _attachedFileBytes = bytes;
        _proofError = null;
      });
    } catch (e, st) {
      debugPrint('Error al seleccionar archivo: $e\n$st');
      setState(
        () => _proofError = 'No se pudo adjuntar el archivo. Intenta de nuevo.',
      );
      msg('No se pudo adjuntar: $e');
    }
  }

  /// La unicidad de la referencia la valida el servidor (reportar_pago), que
  /// compara contra TODOS los pagos del colegio por método + banco de origen.
  /// El cliente no puede (ni debe) consultar pagos de otras familias.
  // Valida todos los campos a la vez, no solamente el primero.
  // Cada mensaje se presenta junto al control que debe corregirse.
  bool _validateTransactionFields() {
    final reference = _refController.text.trim();
    final referenceValid =
        reference.length >= 4 &&
        reference.length <= 80 &&
        (_isVes
            ? RegExp(r'^[0-9]+$').hasMatch(reference)
            : RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(reference));
    final monto = _typedAmount;
    final textEntered = _isVes && _amountInUsd
        ? _usdAmountController.text.trim()
        : _montoController.text.trim();
    final numberEntered = double.tryParse(textEntered.replaceAll(',', '.'));

    final bankError = _needsBank && _originBankValue.trim().isEmpty
        ? 'Selecciona el banco desde el que realizaste el pago.'
        : null;
    final referenceError = _referenceRejectedByServer
        ? (_refErrorMessage ?? 'Corrige esta referencia para continuar.')
        : !referenceValid
        ? (_isCash
              ? 'Introduce el número del recibo (mínimo 4 caracteres).'
              : _isVes
              ? 'La referencia debe contener entre 4 y 80 dígitos.'
              : 'Introduce un código de 4 a 80 caracteres válido.')
        : null;
    final dateError = _selectedDate.isAfter(DateTime.now())
        ? 'La fecha del pago no puede ser futura.'
        : null;
    final amountError = _isVes && !_hasRate
        ? 'No hay tasa BCV disponible para registrar este pago.'
        : (numberEntered == null ||
              !numberEntered.isFinite ||
              numberEntered <= 0 ||
              !monto.isFinite ||
              monto <= 0)
        ? 'Introduce un monto válido mayor que cero.'
        : null;

    setState(() {
      _bankError = bankError;
      _refErrorMessage = referenceError;
      _dateError = dateError;
      _amountError = amountError;
      _isRefValid = referenceValid && !_referenceRejectedByServer;
      _stepError = null;
    });

    return bankError == null &&
        referenceError == null &&
        dateError == null &&
        amountError == null;
  }

  Future<bool> _validateReferenceUniqueness() async {
    // La unicidad real se verifica al registrar el pago en el servidor.
    return _validateTransactionFields();
  }

  String _mensajeErrorReporte(String raw) {
    if (raw.contains('REFERENCIA_DUPLICADA')) {
      return 'Esta referencia ya fue registrada previamente en el sistema.';
    }
    if (raw.contains('REPRESENTANTE_NO_ENCONTRADO')) {
      return 'Tu usuario no está vinculado a un representante. Contacta al colegio.';
    }
    if (raw.contains('REFERENCIA_INVALIDA')) {
      return 'La referencia debe tener al menos 4 caracteres.';
    }
    if (raw.contains('FECHA_INVALIDA'))
      return 'La fecha del pago no es válida.';
    if (raw.contains('MONTO_INVALIDO'))
      return 'El monto del pago no es válido.';
    if (raw.contains('TASA_INVALIDA')) {
      return 'No se pudo determinar la tasa BCV. Intenta de nuevo.';
    }
    if (raw.contains('BANCO_ORIGEN_INVALIDO') ||
        raw.contains('BANCO_INVALIDO')) {
      return 'El banco de origen no es válido. Selecciona uno de la lista.';
    }
    if (raw.contains('COMPROBANTE_INVALIDO')) {
      return 'El comprobante no es válido. Adjunta otro archivo.';
    }
    return 'Error al enviar el reporte: $raw';
  }

  Future<void> _submitReport() async {
    if (_isSubmitting) return; // evita doble envío

    void aviso(String msg, {Color color = Colors.orangeAccent}) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
    }

    if (!_validateTransactionFields()) {
      setState(() => _currentStep = 2);
      return;
    }
    if (_attachedFileBytes == null || _attachedFileName == null) {
      setState(() {
        _currentStep = 3;
        _proofError = _isCash
            ? 'Adjunta el recibo oficial emitido por caja.'
            : 'Adjunta el comprobante de la transacción.';
      });
      return;
    }

    final bool isBs =
        _selectedMethod == 'Pago Móvil' ||
        _selectedMethod == 'Transferencia Bancaria';
    final double montoIngresado =
        double.tryParse(_montoController.text.replaceAll(',', '.')) ?? 0.0;
    // Control defensivo por si la tasa cambió durante la operación.
    if (montoIngresado <= 0 || (isBs && !_hasRate)) {
      setState(() {
        _currentStep = 2;
        _amountError = isBs && !_hasRate
            ? 'No hay tasa BCV disponible para registrar este pago.'
            : 'Introduce un monto válido mayor que cero.';
      });
      return;
    }

    setState(() => _isSubmitting = true);
    String? uploadedPath;
    bool pagoRegistrado = false;
    bool uploadAttempted = false;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw const _ReporteException(
          'Tu sesión expiró. Inicia sesión nuevamente.',
        );
      }

      // El representante se identifica por la sesión; nunca se envía '' a una
      // columna UUID. El servidor vuelve a derivarlo de auth.uid().
      final rep = await _supabase
          .from('representantes')
          .select('id')
          .eq('perfil_id', user.id)
          .maybeSingle();
      if (rep == null) {
        throw const _ReporteException(
          'No encontramos tu perfil de representante. Contacta al colegio.',
        );
      }
      final String repId = rep['id'].toString();

      String metodoKey = 'pago_movil';
      if (_selectedMethod == 'Zelle') metodoKey = 'zelle';
      if (_selectedMethod == 'Transferencia Bancaria') {
        metodoKey = 'transferencia_bancaria';
      }
      if (_selectedMethod == 'Efectivo USD') metodoKey = 'efectivo';

      // La referencia de efectivo debe provenir del recibo oficial, no ser inventada.
      final String refStr = _refController.text.trim();

      // 1. Subir el comprobante a la carpeta del representante.
      final String fileExt = _attachedFileName!.split('.').last.toLowerCase();
      final String safeRef = refStr.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      final String storagePath =
          '$repId/${DateTime.now().millisecondsSinceEpoch}_$safeRef.$fileExt';
      uploadAttempted = true;
      await _supabase.storage
          .from('comprobantes')
          .uploadBinary(storagePath, _attachedFileBytes!);
      uploadedPath = storagePath;

      // 2. Registrar el pago (el servidor valida y calcula el equivalente USD).
      //    Se guarda la RUTA del archivo, no una URL pública.
      final dynamic pagoId = await _supabase.rpc(
        'reportar_pago',
        params: {
          'p_metodo': metodoKey,
          'p_moneda': isBs ? 'VES' : 'USD',
          'p_monto': montoIngresado,
          'p_tasa': isBs ? _currentTasaBcv : null,
          'p_referencia': refStr,
          'p_fecha':
              '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
          'p_comprobante_path': storagePath,
          'p_banco_origen': _needsBank ? _originBankValue : null,
        },
      );
      pagoRegistrado = true;

      final String idStr = pagoId.toString();
      final String reportCode =
          'EP-${DateTime.now().year}-${(idStr.length >= 8 ? idStr.substring(0, 8) : idStr).toUpperCase()}';

      if (mounted) {
        setState(() {
          _generatedReportCode = reportCode;
          _isSubmitting = false;
          _isSubmitted = true;
        });
      }
    } catch (e) {
      debugPrint('Error al registrar pago: $e');

      // Si el pago no quedó registrado, no se deja basura en el bucket.
      final String? pathToClean = uploadedPath;
      if (!pagoRegistrado && pathToClean != null) {
        try {
          await _supabase.storage.from('comprobantes').remove([pathToClean]);
        } catch (cleanupError) {
          debugPrint(
            'No se pudo borrar el comprobante huérfano: $cleanupError',
          );
        }
      }

      final String raw = e is PostgrestException
          ? e.message
          : (e is _ReporteException ? e.message : '$e');
      final errorMessage = _mensajeErrorReporte(raw);
      final upper = raw.toUpperCase();
      final referenceError =
          upper.contains('REFERENCIA_DUPLICADA') ||
          upper.contains('REFERENCIA_INVALIDA');
      final dateError = upper.contains('FECHA_INVALIDA');
      final amountError =
          upper.contains('MONTO_INVALIDO') || upper.contains('TASA_INVALIDA');
      final bankError =
          upper.contains('BANCO_ORIGEN_INVALIDO') ||
          upper.contains('BANCO_INVALIDO');
      final proofError =
          upper.contains('COMPROBANTE_INVALIDO') ||
          (uploadAttempted && uploadedPath == null);
      final associatedFieldError =
          referenceError || dateError || amountError || bankError || proofError;

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          if (referenceError) {
            _refErrorMessage = errorMessage;
            _referenceRejectedByServer = true;
            _isRefValid = false;
          }
          if (dateError) _dateError = errorMessage;
          if (amountError) _amountError = errorMessage;
          if (bankError) _bankError = errorMessage;
          if (proofError) {
            _proofError = uploadAttempted && uploadedPath == null
                ? 'No se pudo subir el comprobante. Comprueba tu conexión e inténtalo de nuevo.'
                : errorMessage;
          }
          if (associatedFieldError) {
            _currentStep = proofError ? 3 : 2;
          }
        });
      }
      // Errores sin un campo concreto (sesión, red, permisos, etc.).
      if (!associatedFieldError) aviso(errorMessage, color: Colors.redAccent);
    }
  }

  // ===========================================================================
  // Ayudantes por método de pago
  // ===========================================================================
  bool get _isCash => _selectedMethod == 'Efectivo USD';
  bool get _isZelle => _selectedMethod == 'Zelle';

  Color get _methodColor => switch (_selectedMethod) {
    'Pago Móvil' => AppColors.primaryBlue,
    'Zelle' => const Color(0xFF6D1ED4),
    'Transferencia Bancaria' => const Color(0xFF0E7490),
    _ => AppColors.successGreen,
  };

  /// Variante oscura del color del método, para texto e íconos pequeños
  /// sobre el fondo teñido (mantiene contraste AA).
  Color get _methodDark => switch (_selectedMethod) {
    'Pago Móvil' => AppColors.primaryDark,
    'Zelle' => const Color(0xFF5B21B6),
    'Transferencia Bancaria' => const Color(0xFF155E75),
    _ => const Color(0xFF047857),
  };

  IconData get _methodIcon => switch (_selectedMethod) {
    'Pago Móvil' => Icons.smartphone,
    'Zelle' => Icons.mail_outline,
    'Transferencia Bancaria' => Icons.account_balance_outlined,
    _ => Icons.payments_outlined,
  };

  String get _destinoTitle => switch (_selectedMethod) {
    'Pago Móvil' => 'Pago Móvil del colegio',
    'Zelle' => 'Zelle del colegio',
    'Transferencia Bancaria' => 'Transferencia al colegio',
    _ => 'Pago en caja',
  };

  String get _refLabel => _isCash
      ? 'Número de recibo de caja *'
      : _isZelle
      ? 'Código de confirmación Zelle *'
      : 'Referencia bancaria *';

  String get _refHint => _isCash
      ? 'N.º del recibo oficial'
      : _isZelle
      ? 'Confirmation ID'
      : 'Referencia del comprobante';

  String get _refHelper => _isVes
      ? 'Solo números, mínimo 4 dígitos.'
      : 'Letras y números, mínimo 4 caracteres.';

  double get _typedAmount =>
      double.tryParse(_montoController.text.trim().replaceAll(',', '.')) ?? 0.0;

  /// Monto sugerido en la moneda del método elegido.
  double get _suggestedAmount =>
      _isVes ? widget.amountUsd * _currentTasaBcv : widget.amountUsd;

  String _money(double v) => _isVes ? 'Bs. ${_fmt2(v)}' : '\$${_fmt2(v)} USD';

  void _copy(String text, {String? msg}) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg ?? 'Copiado'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ===========================================================================
  // Estructura del diálogo
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 600;
    // La altura nace del contenido: el diálogo solo usa el alto que necesita
    // cada paso y método. El cuerpo se desplaza únicamente si la pantalla (o
    // el teclado abierto) no alcanza.
    final maxHeight =
        (media.size.height -
                media.padding.top -
                media.padding.bottom -
                media.viewInsets.bottom -
                24)
            .clamp(280.0, double.infinity)
            .toDouble();

    final body = _isSubmitted
        ? _buildSuccessWidget()
        : _currentStep == 1
        ? _buildStep1Widget()
        : _currentStep == 2
        ? _buildStep2Widget()
        : _buildStep3Widget();

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 900,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AnimatedSize(
            alignment: Alignment.topCenter,
            duration: media.disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                if (!_isSubmitted)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                    child: _buildStepperHeader(compact),
                  ),
                const Divider(height: 1, color: AppColors.cardBorder),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      compact ? 14 : 20,
                      compact ? 14 : 16,
                      compact ? 14 : 20,
                      compact ? 14 : 16,
                    ),
                    child: body,
                  ),
                ),
                const Divider(height: 1, color: AppColors.cardBorder),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: _buildBottomActionButtons(compact),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 21,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reportar pago',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkNavy,
                  ),
                ),
                Text(
                  '$_familyDisplay · ${widget.monthPeriod}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            tooltip: 'Cerrar',
            constraints: const BoxConstraints(
              minWidth: AppSizes.minTarget,
              minHeight: AppSizes.minTarget,
            ),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperHeader(bool compact) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStepCircle(1, 'Método', compact),
          _buildStepLine(1, compact),
          _buildStepCircle(2, 'Datos', compact),
          _buildStepLine(2, compact),
          _buildStepCircle(3, 'Comprobante', compact),
        ],
      ),
    );
  }

  Widget _buildStepCircle(int step, String label, bool compact) {
    final bool isCompleted = _isSubmitted || _currentStep > step;
    final bool isActive = !_isSubmitted && _currentStep == step;
    // En pantallas angostas solo el paso activo muestra su nombre: evita que
    // el encabezado se desborde.
    final bool showLabel = !compact || isActive;

    return Semantics(
      label: 'Paso $step: $label',
      selected: isActive,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? AppColors.successGreen
                  : isActive
                  ? AppColors.primaryBlue
                  : AppColors.cardBorder,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 15)
                  : Text(
                      '$step',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : AppColors.textMuted,
                      ),
                    ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isActive || isCompleted
                    ? FontWeight.bold
                    : FontWeight.w500,
                color: isActive || isCompleted
                    ? AppColors.darkNavy
                    : AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepLine(int afterStep, bool compact) {
    final bool isCompleted = _isSubmitted || _currentStep > afterStep;
    return Container(
      width: compact ? 16 : 32,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isCompleted ? AppColors.successGreen : AppColors.cardBorder,
    );
  }

  // Título + subtítulo común a los tres pasos.
  Widget _stepTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.darkNavy,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      ),
      const SizedBox(height: 12),
    ],
  );

  // ===========================================================================
  // PASO 1 · MÉTODO
  // ===========================================================================
  Widget _buildStep1Widget() {
    const methods = [
      ('Pago Móvil', 'VES', 'Conversión BCV\nautomática'),
      ('Transferencia Bancaria', 'VES', 'Conversión BCV\nautomática'),
      ('Zelle', 'USD', 'Monto directo\nen dólares'),
      ('Efectivo USD', 'USD', 'Entrega directa\nen caja'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(
          'Selecciona el método de pago',
          'Elige la opción con la que realizaste tu pago.',
        ),
        LayoutBuilder(
          builder: (context, bounds) {
            final w = bounds.maxWidth;
            // Las cuatro tarjetas caben sin comprimir textos en escritorio.
            final columns = w >= 760 ? 4 : (w >= 450 ? 2 : 1);
            final horizontalTile = columns == 1;
            const spacing = 10.0;
            final itemWidth = (w - (columns - 1) * spacing) / columns;
            // El alto contempla logo, título, moneda y dos líneas de ayuda.
            final cardHeight = columns == 4
                ? 174.0
                : (columns == 2 ? 158.0 : 80.0);
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in methods)
                  SizedBox(
                    width: itemWidth,
                    height: cardHeight,
                    child: _buildMethodCard(
                      item.$1,
                      item.$2,
                      item.$3,
                      compactTile: horizontalTile,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _buildMethodGuide(),
      ],
    );
  }

  /// Tarjeta informativa del método elegido: qué hacer, en tres pasos.
  /// Usa el mismo color que la tarjeta de datos del paso 2.
  Widget _buildMethodGuide() {
    final color = _methodColor;
    final dark = _methodDark;
    final heading = switch (_selectedMethod) {
      'Pago Móvil' => 'Pago Móvil en bolívares',
      'Transferencia Bancaria' => 'Transferencia en bolívares',
      'Zelle' => 'Zelle en dólares',
      _ => 'Efectivo en dólares',
    };
    final description = switch (_selectedMethod) {
      'Pago Móvil' =>
        'El monto en bolívares se calcula con la tasa BCV vigente.',
      'Transferencia Bancaria' =>
        'Transfiere a la cuenta del colegio y conserva el comprobante.',
      'Zelle' =>
        'Guarda el código de confirmación para comprobar tu transferencia.',
      _ => 'El colegio entrega un recibo numerado como constancia del pago.',
    };
    final messages = switch (_selectedMethod) {
      'Pago Móvil' => [
        'Realiza el Pago Móvil al colegio.',
        'Anota la referencia y el banco de origen.',
        'Adjunta la captura del comprobante.',
      ],
      'Transferencia Bancaria' => [
        'Realiza la transferencia a la cuenta del colegio.',
        'Conserva la referencia y el banco de origen.',
        'Adjunta el comprobante bancario.',
      ],
      'Zelle' => [
        'Envía el monto a la cuenta Zelle del colegio.',
        'Guarda el código de confirmación.',
        'Adjunta la captura con los datos del pago.',
      ],
      _ => [
        'Entrega el efectivo en la caja del colegio.',
        'Solicita el recibo oficial numerado.',
        'Adjunta una foto legible del recibo.',
      ],
    };
    const stepIcons = [
      Icons.account_balance_outlined,
      Icons.receipt_long_outlined,
      Icons.camera_alt_outlined,
    ];

    Widget instruction(int i, bool wide) => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.tint(color, 0.18),
          child: Text(
            '${i + 1}',
            style: TextStyle(fontWeight: FontWeight.w800, color: dark),
          ),
        ),
        const SizedBox(width: 10),
        Icon(stepIcons[i], size: 24, color: dark),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            messages[i],
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.darkNavy,
            ),
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.07),
        border: Border.all(color: AppColors.tint(color, 0.38)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          final pills = _isVes
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.tint(color, 0.35)),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.currency_exchange_rounded,
                        size: 17,
                        color: dark,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _hasRate
                            ? 'Tasa BCV: 1 USD = Bs. ${_fmt2(_currentTasaBcv)}'
                            : 'Tasa BCV no disponible',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: dark,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _methodLogo(_selectedMethod, size: 44),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          heading,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkNavy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (wide && _isVes) ...[const SizedBox(width: 12), pills],
                ],
              ),
              if (!wide && _isVes) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: pills),
              ],
              const SizedBox(height: 11),
              if (constraints.maxWidth >= 700)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      Expanded(child: instruction(i, true)),
                      if (i < 2)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          height: 46,
                          width: 1,
                          color: AppColors.cardBorder,
                        ),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      instruction(i, false),
                      if (i < 2) const SizedBox(height: 13),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  /// Logo auténtico en los métodos que tienen asset; alternativa visual en otros.
  Widget _methodLogo(String method, {double size = 68}) {
    final String? asset = switch (method) {
      'Pago Móvil' => 'assets/images/logo_pago_movil.png',
      'Transferencia Bancaria' =>
        'assets/images/logo_transferencia_bancaria.png',
      'Zelle' => 'assets/images/logo_zelle.png',
      'Efectivo USD' => 'assets/images/logo_efectivo.png',
      _ => null,
    };
    final cash = method == 'Efectivo USD';
    final color = method == 'Zelle'
        ? const Color(0xFF741DCC)
        : cash
        ? const Color(0xFF008760)
        : AppColors.primaryBlue;
    final icon = method == 'Transferencia Bancaria'
        ? Icons.account_balance_rounded
        : cash
        ? Icons.payments_rounded
        : Icons.account_balance_wallet_outlined;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(asset == null ? size * 0.20 : size * 0.11),
      decoration: BoxDecoration(
        color: cash
            ? const Color(0xFFDCF5E8)
            : method == 'Zelle'
            ? const Color(0xFFF3E9FF)
            : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: asset == null
          ? Icon(icon, color: color, size: size * 0.6)
          : Image.asset(
              asset,
              fit: BoxFit.contain,
              semanticLabel: method,
              errorBuilder: (_, __, ___) =>
                  Icon(icon, color: color, size: size * 0.6),
            ),
    );
  }

  Widget _buildMethodCard(
    String title,
    String badge,
    String subtitle, {
    bool compactTile = false,
  }) {
    final selected = _selectedMethod == title;
    final displayTitle = switch (title) {
      'Efectivo USD' => 'Efectivo',
      'Transferencia Bancaria' => 'Transferencia',
      _ => title,
    };

    void select() {
      setState(() {
        _selectedMethod = title;
        _selectedOriginBank = null;
        _bankDropdownOpen = false;
        _bankSearchController.clear();
        _refController.clear();
        _isRefValid = false;
        _referenceRejectedByServer = false;
        _stepError = null;
        _bankError = null;
        _refErrorMessage = null;
        _dateError = null;
        _amountError = null;
        _proofError = null;
        _attachedFileBytes = null;
        _attachedFileName = null;
        _amountEditedByUser = false;
        _updateMontoField(widget.amountUsd);
      });
    }

    final badgeWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        badge,
        style: const TextStyle(
          color: AppColors.primaryBlue,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: '$displayTitle, moneda $badge',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: select,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.all(compactTile ? 10 : 11),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFF0F6FF) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : AppColors.cardBorder,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.08),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: compactTile
                ? Row(
                    children: [
                      _methodLogo(title, size: 51),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppColors.darkNavy,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              badge,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? AppColors.primaryBlue
                            : const Color(0xFF9AABC2),
                        size: 23,
                      ),
                    ],
                  )
                : Stack(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selected
                              ? AppColors.primaryBlue
                              : const Color(0xFF9AABC2),
                          size: 24,
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _methodLogo(title, size: 52),
                            const SizedBox(height: 7),
                            Text(
                              displayTitle,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.darkNavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            badgeWidget,
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.18,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PASO 2 · DATOS
  // ===========================================================================
  Widget _buildStep2Widget() {
    final subtitle = _isCash
        ? 'Registra los datos que aparecen en el recibo del colegio.'
        : _isZelle
        ? 'Utiliza el código y los datos de tu comprobante de Zelle.'
        : 'Escribe la información tal como aparece en el comprobante bancario.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle('Datos de la transacción', subtitle),
        _isCash ? _buildCashStepsCard() : _buildDestinoCard(),
        const SizedBox(height: 22),
        _buildTransactionForm(),
      ],
    );
  }

  /// Estructura común de la tarjeta superior: encabezado, filas y monto.
  /// Una sola columna, sin recuadros dentro de recuadros.
  Widget _dataCard({required List<Widget> rows, String? copyAllText}) {
    final color = _methodColor;
    final dark = _methodDark;
    final line = AppColors.tint(color, 0.22);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.07),
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        border: Border.all(color: AppColors.tint(color, 0.4), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_methodIcon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _destinoTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkNavy,
                    ),
                  ),
                ),
                if (copyAllText != null)
                  TextButton.icon(
                    onPressed: () =>
                        _copy(copyAllText, msg: 'Datos del colegio copiados'),
                    style: TextButton.styleFrom(
                      foregroundColor: dark,
                      minimumSize: const Size(0, AppSizes.minTarget),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.copy_all_rounded, size: 17),
                    label: const Text(
                      'Copiar todo',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          for (final r in rows) ...[Divider(height: 1, color: line), r],
          Divider(height: 1, color: line),
          _buildMontoCard(),
        ],
      ),
    );
  }

  /// Pago Móvil, Transferencia Bancaria o Zelle: lista simple etiqueta/valor.
  /// Tocar una fila copia ese dato.
  Widget _buildDestinoCard() {
    final Map<String, String> items = switch (_selectedMethod) {
      'Pago Móvil' => _pagoMovilColegio,
      'Zelle' => _zelleColegio,
      _ => _transferenciaColegio,
    };
    final allText = [
      ...items.entries.map((e) => '${e.key}: ${e.value}'),
      'Monto a pagar: ${_money(_suggestedAmount)}',
    ].join('\n');

    return _dataCard(
      copyAllText: allText,
      rows: [for (final e in items.entries) _dataRow(e.key, e.value)],
    );
  }

  Widget _dataRow(String label, String value) {
    return Semantics(
      button: true,
      label: 'Copiar $label: $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _copy(value, msg: '$label copiado'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkNavy,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.copy_rounded, size: 16, color: _methodDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Efectivo: tres pasos en lista vertical, mismo estilo que las filas.
  Widget _buildCashStepsCard() {
    const steps = [
      'Entrega el efectivo en la caja del colegio.',
      'Solicita tu recibo oficial numerado.',
      'Registra el número y adjunta una foto del recibo.',
    ];
    return _dataCard(
      rows: [
        for (var i = 0; i < steps.length; i++)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.minTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: AppColors.tint(_methodColor, 0.22),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Pie de la tarjeta: monto sugerido, destacado sobre fondo suave.
  Widget _buildMontoCard() {
    final suggested = _suggestedAmount;
    final unavailable = _isVes && !_hasRate;
    final none = suggested <= 0 || unavailable;

    return Container(
      color: AppColors.tint(_methodColor, 0.13),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Monto a pagar',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                if (_isVes && _hasRate && !none)
                  Text(
                    '≈ USD ${_fmt2(widget.amountUsd)} · Tasa BCV ${_fmt2(_currentTasaBcv)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Sin Flexible: compartía el espacio 50/50 con el Expanded de la
          // izquierda y el monto quedaba a mitad de la tarjeta.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              unavailable
                  ? 'Tasa BCV no disponible'
                  : none
                  ? 'Sin monto sugerido'
                  : _money(suggested),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: none ? 14 : 20,
                fontWeight: FontWeight.w800,
                color: unavailable ? AppColors.errorRed : AppColors.darkNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, Widget field, {String? helper, String? error}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkNavy,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          field,
          if (error != null) _fieldError(error),
          if (helper != null) ...[
            const SizedBox(height: 4),
            Text(
              helper,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      );

  Widget _fieldError(String error) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 15,
          color: AppColors.errorRed,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            error,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: AppColors.errorRed,
            ),
          ),
        ),
      ],
    ),
  );

  /// Dos campos por fila en pantallas anchas, apilados en estrechas.
  Widget _formRow(Widget first, Widget second) => LayoutBuilder(
    builder: (_, constraints) => constraints.maxWidth >= 440
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 14),
              Expanded(child: second),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 14), second],
          ),
  );

  // Abre el selector. En móviles se presenta una hoja inferior, igual a
  // las aplicaciones bancarias; en escritorio se despliega debajo del campo.
  Future<void> _openOriginBankSelector() async {
    if (MediaQuery.sizeOf(context).width < 650) {
      FocusScope.of(context).unfocus();
      final result = await showModalBottomSheet<_OriginBankOption>(
        context: context,
        isScrollControlled: true,
        sheetAnimationStyle: const AnimationStyle(
          duration: Duration.zero,
          reverseDuration: Duration.zero,
        ),
        useSafeArea: true,
        backgroundColor: Colors.white,
        barrierColor: Colors.black54,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        constraints: const BoxConstraints(maxWidth: 680),
        // Flutter anima el panel al aparecer y al bajar para cerrarse.
        builder: (sheetContext) {
          final mq = MediaQuery.of(sheetContext);
          final availableHeight =
              mq.size.height - mq.viewInsets.bottom - mq.padding.top - 16;
          final preferredHeight = mq.size.height * 0.70;
          final sheetHeight = preferredHeight < availableHeight
              ? preferredHeight
              : availableHeight;
          return Padding(
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
            child: SizedBox(
              height: sheetHeight.clamp(240.0, 670.0).toDouble(),
              child: _OriginBankSheet(selectedValue: _selectedOriginBank),
            ),
          );
        },
      );
      if (result != null && mounted) _selectOriginBank(result);
      return;
    }

    setState(() {
      _bankDropdownOpen = !_bankDropdownOpen;
      _bankSearchController.clear();
    });
    if (_bankDropdownOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _bankDropdownOpen) _bankSearchFocus.requestFocus();
      });
    } else {
      _bankSearchFocus.unfocus();
    }
  }

  void _selectOriginBank(_OriginBankOption bank) {
    _bankSearchFocus.unfocus();
    setState(() {
      _selectedOriginBank = bank.value;
      _bankDropdownOpen = false;
      _bankSearchController.clear();
      _bankError = null;
      _stepError = null;
    });
  }

  Widget _buildOriginBankSelector() {
    _OriginBankOption? selected;
    for (final bank in _originBankOptions) {
      if (bank.value == _selectedOriginBank) {
        selected = bank;
        break;
      }
    }
    final matches = _filterOriginBanks(_bankSearchController.text);
    final isCompact = MediaQuery.sizeOf(context).width < 650;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: selected == null
              ? 'Seleccionar banco de origen'
              : 'Banco de origen: ${selected.name}',
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusControl),
              side: BorderSide(
                color: _bankError != null
                    ? AppColors.errorRed
                    : _bankDropdownOpen
                    ? AppColors.primaryBlue
                    : AppColors.cardBorder,
                width: _bankError != null || _bankDropdownOpen ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSizes.radiusControl),
              onTap: _openOriginBankSelector,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSizes.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_outlined,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          selected == null
                              ? 'Buscar banco de origen'
                              : selected.code.isEmpty
                              ? selected.name
                              : '${selected.code} - ${selected.value}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: selected == null
                                ? AppColors.textMuted
                                : AppColors.darkNavy,
                            fontWeight: selected == null
                                ? FontWeight.w400
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _bankDropdownOpen && !isCompact
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primaryBlue,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!isCompact)
          ClipRect(
            child: !_bankDropdownOpen
                ? const SizedBox(width: double.infinity, height: 0)
                : Container(
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: TextField(
                            controller: _bankSearchController,
                            focusNode: _bankSearchFocus,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.search,
                            decoration:
                                _inputDecoration(
                                  'Buscar por banco o código (ej. 0105)',
                                ).copyWith(
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    color: AppColors.primaryBlue,
                                  ),
                                  suffixIcon: _bankSearchController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Limpiar búsqueda',
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () => setState(
                                            _bankSearchController.clear,
                                          ),
                                        ),
                                ),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.cardBorder),
                        SizedBox(
                          height: 265,
                          child: _buildOriginBankResults(
                            matches,
                            onSelected: _selectOriginBank,
                            selectedValue: _selectedOriginBank,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _amountCurrencyOption(String label, bool inUsd) {
    final selected = _amountInUsd == inUsd;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Ingresar monto en ${inUsd ? 'dólares' : 'bolívares'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _setAmountInputCurrency(inUsd),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 47),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryBlue : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : AppColors.cardBorder,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.darkNavy,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionForm() {
    const inputText = TextStyle(fontSize: 14, color: AppColors.darkNavy);

    final bank = _field(
      'Banco de origen *',
      _buildOriginBankSelector(),
      error: _bankError,
    );

    final reference = _field(
      _refLabel,
      TextField(
        controller: _refController,
        style: inputText,
        onChanged: _onRefChanged,
        keyboardType: _isVes ? TextInputType.number : TextInputType.text,
        inputFormatters: _isVes
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        maxLength: 80,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                null,
        decoration:
            _inputDecoration(
              _refHint,
              hasError: _refErrorMessage != null,
            ).copyWith(
              suffixIcon: _isRefValid && _refErrorMessage == null
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.successGreen,
                      size: 20,
                    )
                  : null,
            ),
      ),
      helper: _refErrorMessage == null ? _refHelper : null,
      error: _refErrorMessage,
    );

    // Fecha y monto comparten un encabezado de la misma altura.
    // De este modo, los dos controles comienzan exactamente en la misma línea.
    final date = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _isVes ? 36 : 18,
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Fecha del pago *',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.darkNavy,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectDate(context),
            borderRadius: BorderRadius.circular(AppSizes.radiusControl),
            child: Container(
              height: AppSizes.control,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusControl),
                border: Border.all(
                  color: _dateError != null
                      ? AppColors.errorRed
                      : AppColors.cardBorder,
                  width: _dateError == null ? 1 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 18,
                    color: _dateError != null
                        ? AppColors.errorRed
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fmtDate(_selectedDate),
                      maxLines: 1,
                      style: inputText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_dateError != null) _fieldError(_dateError!),
      ],
    );

    final amountFormatter = TextInputFormatter.withFunction(
      (oldValue, newValue) =>
          RegExp(r'^\d{0,10}([.,]\d{0,2})?$').hasMatch(newValue.text)
          ? newValue
          : oldValue,
    );

    // Pago Móvil y Transferencia: el usuario elige la moneda para introducir
    // el importe, pero el monto enviado al servidor siempre es en bolívares.
    final amount = _isVes
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Monto del pago *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkNavy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _amountCurrencyOption('Bs.', false),
                    const SizedBox(width: 5),
                    _amountCurrencyOption('USD', true),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: AppSizes.control,
                child: TextField(
                  key: ValueKey(_amountInUsd ? 'monto-usd' : 'monto-bs'),
                  controller: _amountInUsd
                      ? _usdAmountController
                      : _montoController,
                  style: inputText,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [amountFormatter],
                  onChanged: (_) => setState(() {
                    _amountEditedByUser = true;
                    if (_amountInUsd) {
                      _syncConvertedAmount();
                    } else {
                      _syncUsdFromVes();
                    }
                    _amountError = null;
                    _stepError = null;
                  }),
                  decoration:
                      _inputDecoration(
                        _amountInUsd ? 'USD 0,00' : 'Bs. 0,00',
                        hasError: _amountError != null,
                      ).copyWith(
                        prefixIconConstraints: const BoxConstraints(
                          minHeight: AppSizes.control,
                          minWidth: 42,
                        ),
                        prefixIcon: Icon(
                          _amountInUsd
                              ? Icons.attach_money_rounded
                              : Icons.currency_exchange_rounded,
                          size: 19,
                          color: _amountError != null
                              ? AppColors.errorRed
                              : AppColors.primaryBlue,
                        ),
                      ),
                ),
              ),
              if (_amountError != null) _fieldError(_amountError!),
            ],
          )
        : _field(
            'Monto (USD) *',
            SizedBox(
              height: AppSizes.control,
              child: TextField(
                controller: _montoController,
                style: inputText,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [amountFormatter],
                onChanged: (_) => setState(() {
                  _amountError = null;
                  _stepError = null;
                }),
                decoration: _inputDecoration(
                  'USD 0,00',
                  hasError: _amountError != null,
                ),
              ),
            ),
            error: _amountError,
          );

    final conversion = _isVes
        ? Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.currency_exchange_rounded,
                  color: AppColors.primaryBlue,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _amountInUsd
                            ? 'Total a registrar en bolívares'
                            : 'Equivalente aproximado en dólares',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        !_hasRate
                            ? 'Tasa BCV no disponible'
                            : _amountInUsd
                            ? 'Bs. ${_fmt2(_typedAmount)}'
                            : 'USD ${_fmt2(_vesToUsd(_typedAmount))}',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _hasRate
                              ? AppColors.darkNavy
                              : AppColors.errorRed,
                        ),
                      ),
                      if (_hasRate) ...[
                        const SizedBox(height: 2),
                        Text(
                          '1 USD = Bs. ${_fmt2(_currentTasaBcv)} · Tasa BCV',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (!_amountInUsd)
                          Text(
                            'Se registrarán Bs. ${_fmt2(_typedAmount)}.',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_needsBank) ...[bank, const SizedBox(height: 14)],
        reference,
        const SizedBox(height: 14),
        _formRow(date, amount),
        if (_isVes) conversion,
        ..._buildAmountHints(),
        if (_stepError != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.tint(AppColors.errorRed),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.tint(AppColors.errorRed, 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 18,
                  color: AppColors.errorRed,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _stepError!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _hint(String text, Color color, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _buildAmountHints() {
    final typed = _typedAmount;
    final suggested = _suggestedAmount;
    return [
      if (_isVes && !_hasRate)
        _hint(
          'No hay tasa BCV disponible.',
          AppColors.errorRed,
          Icons.error_outline,
        ),
      if (typed > 0 && suggested > 0 && (typed - suggested).abs() > 0.009)
        _hint(
          typed < suggested
              ? 'El monto es menor al sugerido (${_money(suggested)}).'
              : 'El monto es mayor al sugerido (${_money(suggested)}).',
          AppColors.textMuted,
          Icons.info_outline,
        ),
    ];
  }

  // ===========================================================================
  // PASO 3 · COMPROBANTE
  // ===========================================================================
  Widget _buildStep3Widget() {
    final info = _isCash
        ? 'Adjunta el recibo numerado con fecha, monto y sello de caja.'
        : _isZelle
        ? 'Verifica que se distingan la confirmación, remitente, fecha y monto.'
        : 'Asegúrate de que se vean la referencia, fecha, monto y bancos.';

    final upload = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(
          _isCash ? 'Adjunta el recibo de caja' : 'Adjunta el comprobante',
          info,
        ),
        _buildUploadZone(),
        if (_proofError != null) _fieldError(_proofError!),
        const SizedBox(height: 12),
        _buildProofChecklist(),
      ],
    );
    final summary = _buildSummaryCard();

    return LayoutBuilder(
      builder: (_, bounds) {
        final wide = bounds.maxWidth >= 710;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [upload, const SizedBox(height: 16), summary],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 12, child: upload),
              const SizedBox(width: 24),
              Expanded(flex: 10, child: summary),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUploadZone() {
    final bytes = _attachedFileBytes;
    final has = bytes != null;
    final name = _attachedFileName ?? '';
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImage = ext == 'png' || ext == 'jpg' || ext == 'jpeg';
    final color = _proofError != null
        ? AppColors.errorRed
        : has
        ? AppColors.successGreen
        : AppColors.primaryBlue;

    final content = has
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    bytes,
                    height: 104,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 58,
                  color: AppColors.errorRed,
                ),
              const SizedBox(height: 12),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _fmtSize(bytes.length),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickComprobanteFile,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Cambiar archivo'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _attachedFileBytes = null;
                      _attachedFileName = null;
                      _proofError = null;
                    }),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Quitar'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.errorRed,
                    ),
                  ),
                ],
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFDCEAFF),
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  size: 35,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _isCash
                    ? 'Adjunta tu recibo de caja'
                    : 'Adjunta tu comprobante',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'JPG, PNG o PDF · Máximo 5 MB',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 11),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Text(
                  'Seleccionar archivo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Haz clic aquí para buscar tu archivo',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            ],
          );

    return Semantics(
      button: !has,
      label: has ? 'Comprobante adjunto: $name' : 'Seleccionar comprobante',
      child: Material(
        color: has ? const Color(0xFFF0FDF4) : const Color(0xFFF8FBFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.tint(color, 0.5), width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: has ? null : _pickComprobanteFile,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 242),
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }

  /// Qué debe verse en el comprobante, según el método.
  Widget _buildProofChecklist() {
    final List<String> items = switch (_selectedMethod) {
      'Zelle' => ['Remitente', 'Destinatario', 'Confirmación', 'Fecha y monto'],
      'Efectivo USD' => ['N.º de recibo', 'Fecha', 'Monto', 'Sello'],
      _ => ['Referencia', 'Fecha', 'Monto', 'Bancos'],
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FD),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          const Text(
            'Debe verse:',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.darkNavy,
            ),
          ),
          for (final item in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: AppColors.successGreen,
                ),
                const SizedBox(width: 5),
                Text(
                  item,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.darkNavy,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final typed = _typedAmount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen del reporte',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.darkNavy,
            ),
          ),
          const SizedBox(height: 13),
          _buildSummaryRow('Método', _selectedMethod),
          if (_needsBank) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Banco de origen',
              _originBankValue.isEmpty ? '—' : _originBankValue,
            ),
          ],
          const SizedBox(height: 8),
          _buildSummaryRow(
            _isCash
                ? 'Recibo'
                : _isZelle
                ? 'Código Zelle'
                : 'Referencia',
            _refController.text.trim().isEmpty
                ? '—'
                : _refController.text.trim(),
          ),
          const SizedBox(height: 8),
          _buildSummaryRow('Fecha', _fmtDate(_selectedDate)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Divider(height: 1, color: AppColors.cardBorder),
          ),
          _buildSummaryRow('Monto', _money(typed), emphasis: true),
          if (_isVes && _hasRate) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Equivalente',
              'USD ${_fmt2(typed / _currentTasaBcv)}',
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Tasa BCV',
              '1 USD = Bs. ${_fmt2(_currentTasaBcv)}',
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Divider(height: 1, color: AppColors.cardBorder),
          ),
          _buildSummaryRow('Cuenta', _familyDisplay),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'La aprobación y la aplicación a las cuotas se realizan después de la conciliación.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.darkNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool emphasis = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: emphasis ? 16 : 13,
              fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
              color: AppColors.darkNavy,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: Color(0xFF059669),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '¡Reporte enviado!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.darkNavy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tu pago fue enviado para conciliación. Te notificaremos cuando sea verificado.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Reporte #$_generatedReportCode',
              style: const TextStyle(
                color: AppColors.primaryBlue,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ===========================================================================
  // Botones inferiores
  // ===========================================================================
  Widget _buildBottomActionButtons(bool compact) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusControl),
    );
    const labelStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 14);

    if (_isSubmitted) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: shape,
              minimumSize: const Size(0, AppSizes.control),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: const Text('Volver a mi portal', style: labelStyle),
          ),
        ],
      );
    }

    final back = OutlinedButton(
      onPressed: _isSubmitting
          ? null
          : (_currentStep == 1
                ? () => Navigator.pop(context)
                : () => setState(() => _currentStep--)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.darkNavy,
        side: const BorderSide(color: AppColors.cardBorder),
        shape: shape,
        minimumSize: const Size(0, AppSizes.control),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
      child: Text(_currentStep == 1 ? 'Cancelar' : 'Atrás', style: labelStyle),
    );

    final primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryBlue,
      disabledBackgroundColor: const Color(0xFFBFDBFE),
      disabledForegroundColor: Colors.white,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: shape,
      minimumSize: const Size(0, AppSizes.control),
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 26),
    );

    final Widget next;
    if (_currentStep < 3) {
      next = ElevatedButton(
        onPressed: _isSubmitting
            ? null
            : () async {
                if (_currentStep == 2) {
                  final bool isUnique = await _validateReferenceUniqueness();
                  if (!isUnique) return;
                  setState(() => _currentStep++);
                } else {
                  if (_isVes && !_hasRate) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No hay tasa BCV disponible. Intenta más tarde.',
                        ),
                      ),
                    );
                    return;
                  }
                  setState(() => _currentStep++);
                }
              },
        style: primaryStyle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isCheckingRef ? 'Verificando...' : 'Continuar',
              style: labelStyle,
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      );
    } else {
      next = ElevatedButton(
        onPressed: _isSubmitting ? null : _submitReport,
        style: primaryStyle,
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      compact
                          ? 'Enviar reporte'
                          : 'Enviar reporte para conciliación',
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        back,
        const SizedBox(width: 12),
        Flexible(child: next),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, {bool hasError = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      isDense: false,
      constraints: const BoxConstraints(minHeight: AppSizes.control),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusControl),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusControl),
        borderSide: BorderSide(
          color: hasError ? AppColors.errorRed : AppColors.cardBorder,
          width: hasError ? 1.5 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusControl),
        borderSide: BorderSide(
          color: hasError ? AppColors.errorRed : AppColors.primaryBlue,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusControl),
        borderSide: const BorderSide(color: AppColors.errorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusControl),
        borderSide: const BorderSide(color: AppColors.errorRed, width: 1.5),
      ),
    );
  }
}

// Bancos mostrados en el selector (código, nombre visible, valor persistido).
// Listado ordenado por código bancario ascendente.
class _OriginBankOption {
  final String code;
  final String name;
  final String value;
  const _OriginBankOption(this.code, this.name, this.value);
}

const List<_OriginBankOption> _originBankOptions = [
  _OriginBankOption(
    '0102',
    'Banco de Venezuela, S.A.C.A., Banco Universal',
    'Banco de Venezuela',
  ),
  _OriginBankOption(
    '0104',
    'Venezolano de Crédito, S.A., Banco Universal',
    'Venezolano de Crédito',
  ),
  _OriginBankOption(
    '0105',
    'Banco Mercantil, C.A., Banco Universal',
    'Mercantil',
  ),
  _OriginBankOption(
    '0108',
    'Banco Provincial, S.A., Banco Universal',
    'Provincial',
  ),
  _OriginBankOption(
    '0114',
    'Banco del Caribe, C.A., Banco Universal',
    'Bancaribe',
  ),
  _OriginBankOption(
    '0115',
    'Banco Exterior, C.A., Banco Universal',
    'Banco Exterior',
  ),
  _OriginBankOption(
    '0128',
    'Banco Caroní, C.A., Banco Universal',
    'Banco Caroní',
  ),
  _OriginBankOption('0134', 'Banesco Banco Universal, C.A.', 'Banesco'),
  _OriginBankOption(
    '0137',
    'Banco Sofitasa, Banco Universal, C.A.',
    'Sofitasa',
  ),
  _OriginBankOption('0138', 'Banco Plaza, C.A.', 'Banco Plaza'),
  _OriginBankOption(
    '0146',
    'Banco de la Gente Emprendedora, Bangente, C.A.',
    'Bangente',
  ),
  _OriginBankOption(
    '0151',
    'BFC Banco Fondo Común, C.A., Banco Universal',
    'BFC',
  ),
  _OriginBankOption('0156', '100% Banco, Banco Comercial, C.A.', '100% Banco'),
  _OriginBankOption('0157', 'Del Sur Banco Universal, C.A.', 'Del Sur'),
  _OriginBankOption(
    '0163',
    'Banco del Tesoro, C.A., Banco Universal',
    'Banco del Tesoro',
  ),
  _OriginBankOption(
    '0166',
    'Banco Agrícola de Venezuela, C.A., Banco Universal',
    'Banco Agrícola de Venezuela',
  ),
  _OriginBankOption(
    '0168',
    'Bancrecer, S.A., Banco de Desarrollo',
    'Bancrecer',
  ),
  _OriginBankOption('0169', 'R4, Banco Microfinanciero, C.A.', 'R4'),
  _OriginBankOption(
    '0171',
    'Banco Activo, C.A., Banco Comercial',
    'Banco Activo',
  ),
  _OriginBankOption('0172', 'Bancamiga, Banco Universal', 'Bancamiga'),
  _OriginBankOption('0174', 'Banplus Banco Comercial, C.A.', 'Banplus'),
  _OriginBankOption(
    '0175',
    'Banco Digital de los Trabajadores',
    'Banco Digital de los Trabajadores',
  ),
  _OriginBankOption(
    '0177',
    'Banco de la Fuerza Armada Nacional Bolivariana, Banco Universal, C.A.',
    'BANFANB',
  ),
  _OriginBankOption('0178', 'N58 Banco Digital', 'N58'),
  _OriginBankOption(
    '0191',
    'Banco Nacional de Crédito, C.A., Banco Universal',
    'BNC',
  ),
];

String _normalizeBankSearch(String term) => term
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[áàâä]'), 'a')
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[íìîï]'), 'i')
    .replaceAll(RegExp(r'[óòôö]'), 'o')
    .replaceAll(RegExp(r'[úùûü]'), 'u');

List<_OriginBankOption> _filterOriginBanks(String query) {
  final search = _normalizeBankSearch(query);
  if (search.isEmpty) return _originBankOptions;
  return _originBankOptions.where((bank) {
    return _normalizeBankSearch(
      '${bank.code} ${bank.name} ${bank.value}',
    ).contains(search);
  }).toList();
}

Widget _buildOriginBankResults(
  List<_OriginBankOption> banks, {
  required ValueChanged<_OriginBankOption> onSelected,
  String? selectedValue,
}) {
  if (banks.isEmpty) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'No se encontraron bancos. Prueba con otro nombre o código.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      ),
    );
  }
  return ListView.separated(
    primary: false,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: EdgeInsets.zero,
    itemCount: banks.length,
    separatorBuilder: (_, __) => const Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: AppColors.cardBorder,
    ),
    itemBuilder: (context, i) {
      final bank = banks[i];
      final selected = bank.value == selectedValue;
      final label = bank.code.isEmpty
          ? bank.name
          : '${bank.code} - ${bank.name}';
      return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: () => onSelected(bank),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 19,
                      color: AppColors.primaryBlue,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Selector inferior para dispositivos móviles: filtro y listado con scroll.
class _OriginBankSheet extends StatefulWidget {
  final String? selectedValue;
  const _OriginBankSheet({this.selectedValue});

  @override
  State<_OriginBankSheet> createState() => _OriginBankSheetState();
}

class _OriginBankSheetState extends State<_OriginBankSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banks = _filterOriginBanks(_search.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            height: 4,
            width: 38,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        // Igual que en la referencia: buscador limpio arriba del listado.
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 7),
          child: Semantics(
            label: 'Buscar banco de origen por nombre o código',
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 16, color: AppColors.darkNavy),
              decoration: InputDecoration(
                hintText: 'Buscar...',
                hintStyle: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textMuted,
                ),
                suffixIcon: _search.text.isEmpty
                    ? const Icon(
                        Icons.search_rounded,
                        color: AppColors.primaryBlue,
                        size: 27,
                      )
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_search.clear),
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.cardBorder),
        Expanded(
          child: _buildOriginBankResults(
            banks,
            onSelected: (bank) => Navigator.of(context).pop(bank),
            selectedValue: widget.selectedValue,
          ),
        ),
      ],
    );
  }
}

/// Error de validación con un mensaje apto para mostrar al usuario.
class _ReporteException implements Exception {
  final String message;
  const _ReporteException(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Formato (coma decimal y punto de miles, como el resto de la app)
// ---------------------------------------------------------------------------
String _fmt2(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final fromEnd = intPart.length - i;
    buf.write(intPart[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1 && intPart[i] != '-') buf.write('.');
  }
  return '$buf,${parts[1]}';
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtSize(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(0)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
