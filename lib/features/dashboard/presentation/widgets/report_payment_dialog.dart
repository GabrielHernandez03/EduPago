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
  final TextEditingController _otherBankController = TextEditingController();
  String? _stepError;
  String get _originBankValue => _selectedOriginBank == 'Otro banco'
      ? _otherBankController.text.trim()
      : (_selectedOriginBank ?? '');

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
  DateTime _selectedDate = DateTime.now();
  bool _isRefValid = false;
  String? _refErrorMessage;

  // Paso 3: Comprobante
  String? _attachedFileName;
  Uint8List? _attachedFileBytes;
  String _generatedReportCode = '';

  final List<String> _banks = [
    'Banesco',
    'Mercantil',
    'Provincial',
    'Banco de Venezuela',
    'BNC',
    'BFC',
    'Bancaribe',
    'Bancamiga',
    'Banco Exterior',
    'Banco del Tesoro',
    'Banco Plaza',
    'Otro banco',
  ];

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
    _initDataAndRate();
  }

  @override
  void dispose() {
    _refController.dispose();
    _montoController.dispose();
    _otherBankController.dispose();
    super.dispose();
  }

  Future<void> _initDataAndRate() async {
    try {
      final bcvData = await _bcvService.getLatestBcvRate();
      if (mounted && bcvData.rate > 0) {
        setState(() => _currentTasaBcv = bcvData.rate);
      }
    } catch (e) {
      debugPrint('Error obteniendo tasa BCV en diálogo: $e');
    }

    // El monto sugerido (deuda familiar menos pagos en revisión) lo calcula
    // quien abre el diálogo. El representante puede cambiarlo libremente.
    final double initialUsd = widget.amountUsd;

    if (mounted) {
      // setState: refresca también el "equivalente" y las tarjetas del paso 2.
      setState(() => _updateMontoField(initialUsd));
    }
  }

  void _updateMontoField(double usdAmount) {
    final bool isBs =
        _selectedMethod == 'Pago Móvil' ||
        _selectedMethod == 'Transferencia Bancaria';
    if (isBs) {
      final double totalVes = usdAmount * _currentTasaBcv;
      _montoController.text = totalVes.toStringAsFixed(2).replaceAll('.', ',');
    } else {
      _montoController.text = usdAmount.toStringAsFixed(2).replaceAll('.', ',');
    }
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
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
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
        msg('El archivo llegó vacío.');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        msg('El archivo supera los 5 MB.');
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
        msg('El archivo debe ser un JPG, PNG o PDF válido.');
        return;
      }
      setState(() {
        _attachedFileName = file.name;
        _attachedFileBytes = bytes;
      });
    } catch (e, st) {
      debugPrint('Error al seleccionar archivo: $e\n$st');
      msg('No se pudo adjuntar: $e');
    }
  }

  /// La unicidad de la referencia la valida el servidor (reportar_pago), que
  /// compara contra TODOS los pagos del colegio por método + banco de origen.
  /// El cliente no puede (ni debe) consultar pagos de otras familias.
  String? _validateTransaction() {
    if (_needsBank && _originBankValue.length < 3)
      return 'Indica el banco de origen del pago.';
    if (!_isRefValid)
      return _selectedMethod == 'Efectivo USD'
          ? 'Escribe el número real del recibo de caja (mínimo 4 caracteres).'
          : 'Introduce una referencia válida de 4 a 80 caracteres.';
    final monto =
        double.tryParse(_montoController.text.trim().replaceAll(',', '.')) ?? 0;
    if (!monto.isFinite || monto <= 0)
      return 'Ingresa un monto mayor que cero.';
    if (_isVes && !_hasRate)
      return 'No hay una tasa BCV válida para pagos en bolívares.';
    if (_selectedDate.isAfter(DateTime.now()))
      return 'La fecha no puede ser futura.';
    return null;
  }

  Future<bool> _validateReferenceUniqueness() async {
    final message = _validateTransaction();
    if (message == null) return true;
    if (mounted) setState(() => _stepError = message);
    return false;
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

    final transactionError = _validateTransaction();
    if (transactionError != null) {
      setState(() {
        _currentStep = 2;
        _stepError = transactionError;
      });
      aviso(transactionError);
      return;
    }
    if (_attachedFileBytes == null || _attachedFileName == null) {
      aviso(
        _selectedMethod == 'Efectivo USD'
            ? 'Adjunta el recibo oficial emitido por caja.'
            : 'Adjunta el comprobante de la transacción.',
      );
      return;
    }

    final bool isBs =
        _selectedMethod == 'Pago Móvil' ||
        _selectedMethod == 'Transferencia Bancaria';
    final double montoIngresado =
        double.tryParse(_montoController.text.replaceAll(',', '.')) ?? 0.0;
    if (montoIngresado <= 0) {
      aviso('Ingresa un monto válido mayor a cero.');
      return;
    }
    if (isBs && !_hasRate) {
      aviso(
        'No se pudo obtener la tasa BCV. Intenta de nuevo en unos minutos.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    String? uploadedPath;
    bool pagoRegistrado = false;

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
      final bool duplicada = raw.contains('REFERENCIA_DUPLICADA');

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          if (duplicada) {
            _refErrorMessage = _mensajeErrorReporte(raw);
            _isRefValid = false;
            _currentStep = 2; // vuelve al paso de la referencia
          }
        });
      }
      aviso(_mensajeErrorReporte(raw), color: Colors.redAccent);
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
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 820,
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
                      compact ? 16 : 22,
                      16,
                      compact ? 16 : 22,
                      16,
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
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
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
                    fontSize: 18,
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
      width: compact ? 22 : 34,
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
          fontSize: 18,
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
    final methods = <Widget>[
      _buildMethodCard(
        'Pago Móvil',
        'VES',
        'Conversión BCV automática',
        Icons.smartphone,
      ),
      _buildMethodCard(
        'Zelle',
        'USD',
        'Monto directo en dólares',
        Icons.mail_outline,
      ),
      _buildMethodCard(
        'Transferencia Bancaria',
        'VES',
        'Conversión BCV automática',
        Icons.account_balance_outlined,
      ),
      _buildMethodCard(
        'Efectivo USD',
        'USD',
        'Entrega directa en caja',
        Icons.payments_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(
          '¿Cómo realizaste el pago?',
          'Selecciona la moneda y el método utilizado.',
        ),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 500) {
              return Column(
                children: [
                  for (var i = 0; i < methods.length; i++) ...[
                    SizedBox(height: 72, child: methods[i]),
                    if (i < methods.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: SizedBox(height: 80, child: methods[0])),
                    const SizedBox(width: 12),
                    Expanded(child: SizedBox(height: 80, child: methods[1])),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: SizedBox(height: 80, child: methods[2])),
                    const SizedBox(width: 12),
                    Expanded(child: SizedBox(height: 80, child: methods[3])),
                  ],
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
    final line = AppColors.tint(color, 0.22);

    final String title = switch (_selectedMethod) {
      'Pago Móvil' => 'Pago Móvil en bolívares',
      'Zelle' => 'Zelle en dólares',
      'Transferencia Bancaria' => 'Transferencia en bolívares',
      _ => 'Efectivo en dólares',
    };
    final String subtitle = switch (_selectedMethod) {
      'Zelle' => 'El monto se registra directamente en USD.',
      'Efectivo USD' =>
        'Se paga en la caja del colegio. Conserva tu recibo numerado.',
      _ =>
        _hasRate
            ? 'El equivalente en bolívares se calcula con la tasa BCV vigente.'
            : 'La tasa BCV no está disponible por ahora.',
    };
    final List<String> steps = switch (_selectedMethod) {
      'Pago Móvil' => [
        'Paga desde tu banco al Pago Móvil del colegio.',
        'Anota la referencia y el banco de origen.',
        'Adjunta la captura del comprobante.',
      ],
      'Transferencia Bancaria' => [
        'Transfiere a la cuenta bancaria del colegio.',
        'Anota la referencia y el banco de origen.',
        'Adjunta el comprobante de la transferencia.',
      ],
      'Zelle' => [
        'Envía el pago a la cuenta Zelle del colegio.',
        'Copia el código de confirmación de la operación.',
        'Adjunta la captura de la confirmación.',
      ],
      _ => [
        'Entrega el efectivo en la caja del colegio.',
        'Solicita un recibo oficial numerado.',
        'Ten a mano el número y una foto del recibo.',
      ],
    };

    Widget step(int i) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: AppColors.tint(color, 0.22),
          child: Text(
            '${i + 1}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.darkNavy,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              steps[i],
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.darkNavy,
              ),
            ),
          ),
        ),
      ],
    );

    final bool rateBad = _isVes && !_hasRate;

    final Widget? ratePill = (_isVes && _hasRate)
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.currency_exchange_rounded, size: 14, color: dark),
                const SizedBox(width: 6),
                Text(
                  'Tasa BCV: 1 USD = Bs. ${_fmt2(_currentTasaBcv)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: dark,
                  ),
                ),
              ],
            ),
          )
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.07),
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        border: Border.all(color: AppColors.tint(color, 0.4), width: 1.2),
      ),
      child: LayoutBuilder(
        builder: (_, c) {
          final bool wide = c.maxWidth >= 560;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkNavy,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: rateBad
                                ? AppColors.errorRed
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (wide && ratePill != null) ...[
                    const SizedBox(width: 12),
                    ratePill,
                  ],
                ],
              ),
              if (!wide && ratePill != null) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: ratePill),
              ],
              const SizedBox(height: 12),
              c.maxWidth >= 520
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < steps.length; i++) ...[
                          Expanded(child: step(i)),
                          if (i < steps.length - 1) const SizedBox(width: 14),
                        ],
                      ],
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < steps.length; i++) ...[
                          step(i),
                          if (i < steps.length - 1) const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMethodCard(
    String title,
    String badge,
    String subtitle,
    IconData icon,
  ) {
    final selected = _selectedMethod == title;
    final displayTitle = switch (title) {
      'Efectivo USD' => 'Efectivo',
      'Transferencia Bancaria' => 'Transferencia',
      _ => title,
    };
    final asset = title == 'Pago Móvil'
        ? 'assets/images/logo_pago_movil.png'
        : title == 'Zelle'
        ? 'assets/images/logo_zelle.png'
        : null;
    final cash = title == 'Efectivo USD';
    return Semantics(
      button: true,
      selected: selected,
      label: '$displayTitle, moneda $badge',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            _selectedMethod = title;
            _selectedOriginBank = null;
            _otherBankController.clear();
            _refController.clear();
            _isRefValid = false;
            _stepError = null;
            _refErrorMessage = null;
            _attachedFileBytes = null;
            _attachedFileName = null;
            _updateMontoField(widget.amountUsd);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AppColors.cardBorder,
              width: selected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                padding: EdgeInsets.all(asset == null ? 8 : 6),
                decoration: BoxDecoration(
                  color: cash
                      ? const Color(0xFFE4F6ED)
                      : selected
                      ? const Color(0xFFDCEAFF)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: asset != null
                    ? Image.asset(
                        asset,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            Icon(icon, color: AppColors.primaryBlue, size: 28),
                      )
                    : Icon(
                        cash ? Icons.payments_rounded : icon,
                        color: cash
                            ? const Color(0xFF047857)
                            : AppColors.primaryBlue,
                        size: 28,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: AppColors.darkNavy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tint(AppColors.primaryBlue),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primaryBlue : Colors.white,
                  border: Border.all(
                    color: selected
                        ? AppColors.primaryBlue
                        : const Color(0xFF94A3B8),
                    width: 1.4,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 15)
                    : null,
              ),
            ],
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

  Widget _field(String label, Widget field, {String? helper}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.darkNavy,
        ),
      ),
      const SizedBox(height: 6),
      field,
      if (helper != null) ...[
        const SizedBox(height: 4),
        Text(
          helper,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    ],
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

  Widget _buildTransactionForm() {
    const inputText = TextStyle(fontSize: 14, color: AppColors.darkNavy);

    final bank = _field(
      'Banco de origen *',
      DropdownButtonFormField<String>(
        value: _selectedOriginBank,
        isExpanded: true,
        style: inputText,
        hint: const Text(
          'Seleccionar banco',
          style: TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
        decoration: _inputDecoration('Banco emisor'),
        items: _banks
            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
            .toList(),
        onChanged: (val) => setState(() {
          _selectedOriginBank = val;
          if (val != 'Otro banco') _otherBankController.clear();
          _stepError = null;
        }),
      ),
    );

    final otherBank = _field(
      'Nombre del banco *',
      TextField(
        controller: _otherBankController,
        style: inputText,
        onChanged: (_) => setState(() => _stepError = null),
        decoration: _inputDecoration('Ej. Banco Plaza'),
      ),
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
        decoration: _inputDecoration(_refHint).copyWith(
          errorText: _refErrorMessage,
          suffixIcon: _isRefValid
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.successGreen,
                  size: 20,
                )
              : null,
        ),
      ),
      helper: _refErrorMessage == null ? _refHelper : null,
    );

    final date = _field(
      'Fecha del pago *',
      InkWell(
        onTap: () => _selectDate(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusControl),
        child: Container(
          height: AppSizes.control,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusControl),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: AppColors.textMuted,
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
    );

    final amount = _field(
      'Monto (${_isVes ? 'VES' : 'USD'}) *',
      TextField(
        controller: _montoController,
        style: inputText,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          TextInputFormatter.withFunction(
            (oldValue, newValue) =>
                RegExp(r'^\d{0,10}([.,]\d{0,2})?$').hasMatch(newValue.text)
                ? newValue
                : oldValue,
          ),
        ],
        onChanged: (_) => setState(() => _stepError = null),
        decoration: _inputDecoration(_isVes ? 'Bs. 0,00' : 'USD 0,00'),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_needsBank) ...[
          if (_selectedOriginBank == 'Otro banco')
            _formRow(bank, otherBank)
          else
            bank,
          const SizedBox(height: 14),
        ],
        reference,
        const SizedBox(height: 14),
        _formRow(date, amount),
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
    const green = Color(0xFF047857);
    final typed = _typedAmount;
    final suggested = _suggestedAmount;
    return [
      if (_isVes)
        _hasRate
            ? _hint(
                'Equivalente estimado: USD ${_fmt2(typed / _currentTasaBcv)}',
                green,
                Icons.currency_exchange_rounded,
              )
            : _hint(
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
        ? 'Adjunta el recibo oficial con número, fecha, monto y sello de caja.'
        : _isZelle
        ? 'La constancia debe mostrar remitente, destinatario, confirmación, fecha y monto.'
        : 'Asegúrate de que se vean la referencia, fecha, monto y bancos.';

    final upload = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildUploadZone(),
        const SizedBox(height: 12),
        _buildProofChecklist(),
      ],
    );
    final summary = _buildSummaryCard();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepTitle(_isCash ? 'Recibo de caja' : 'Adjunta el comprobante', info),
        LayoutBuilder(
          builder: (_, c) => c.maxWidth >= 640
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: upload),
                    const SizedBox(width: 20),
                    Expanded(flex: 10, child: summary),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [summary, const SizedBox(height: 16), upload],
                ),
        ),
      ],
    );
  }

  Widget _buildUploadZone() {
    final bytes = _attachedFileBytes;
    final has = bytes != null;
    final name = _attachedFileName ?? '';
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImage = ext == 'png' || ext == 'jpg' || ext == 'jpeg';
    final color = has ? AppColors.successGreen : AppColors.primaryBlue;

    final Widget content = has
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    bytes,
                    height: 110,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_outlined,
                      size: 44,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 52,
                  color: AppColors.errorRed,
                ),
              const SizedBox(height: 10),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkNavy,
                ),
              ),
              Text(
                _fmtSize(bytes.length),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickComprobanteFile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.darkNavy,
                      minimumSize: const Size(0, AppSizes.minTarget),
                      side: const BorderSide(color: AppColors.cardBorder),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Cambiar'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _attachedFileBytes = null;
                      _attachedFileName = null;
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.errorRed,
                      minimumSize: const Size(0, AppSizes.minTarget),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Quitar'),
                  ),
                ],
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.primaryBlue),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  size: 30,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _isCash ? 'Adjuntar recibo de caja' : 'Adjuntar comprobante',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'JPG, PNG o PDF · Máximo 5 MB',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(AppSizes.radiusControl),
                ),
                child: const Text(
                  'Seleccionar archivo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: !has,
      label: has ? 'Comprobante adjunto: $name' : 'Adjuntar comprobante',
      child: Material(
        color: has ? const Color(0xFFF0FDF4) : AppColors.primaryLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusCard),
          side: BorderSide(color: AppColors.tint(color, 0.5), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: has ? null : _pickComprobanteFile,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 190),
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
      'Efectivo USD' => ['N.º de recibo', 'Fecha', 'Monto', 'Sello de caja'],
      _ => ['Referencia', 'Fecha', 'Monto', 'Bancos'],
    };
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Debe verse:',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        for (final i in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 15,
                color: AppColors.successGreen,
              ),
              const SizedBox(width: 4),
              Text(
                i,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.darkNavy,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final typed = _typedAmount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen del reporte',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.darkNavy,
            ),
          ),
          const SizedBox(height: 12),
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
            padding: EdgeInsets.symmetric(vertical: 10),
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
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.cardBorder),
          ),
          _buildSummaryRow('Cuenta', _familyDisplay),
          const SizedBox(height: 12),
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
                    'La aprobación y la aplicación a las cuotas ocurren después de la conciliación.',
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
        onPressed: (_isSubmitting || _attachedFileBytes == null)
            ? null
            : _submitReport,
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

  InputDecoration _inputDecoration(String hint) {
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
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusControl),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
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
