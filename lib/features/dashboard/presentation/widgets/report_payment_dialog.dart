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
  String _selectedDestinationBank = 'Mercantil 4872';
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
      _updateMontoField(initialUsd);
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
      _isRefValid = val.trim().length >= 6;
      _refErrorMessage = null;
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
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
  Future<bool> _validateReferenceUniqueness() async => true;

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

    if (_attachedFileBytes == null || _attachedFileName == null) {
      aviso('Por favor, adjunta la captura o imagen del comprobante.');
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
        metodoKey = 'transferencia';
      }
      if (_selectedMethod == 'Efectivo USD') metodoKey = 'efectivo';

      final String refStr = _selectedMethod == 'Efectivo USD'
          ? 'EFECTIVO_${DateTime.now().millisecondsSinceEpoch}'
          : _refController.text.trim();

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
          'p_banco_origen': _selectedOriginBank,
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

  @override
  Widget build(BuildContext context) {
    final double heightScreen = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 580,
        constraints: BoxConstraints(maxHeight: heightScreen * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildStepperHeader(),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.cardBorder),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _isSubmitted
                    ? _buildSuccessWidget()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_currentStep == 1) _buildStep1Widget(),
                          if (_currentStep == 2) _buildStep2Widget(),
                          if (_currentStep == 3) _buildStep3Widget(),
                        ],
                      ),
              ),
            ),
            const Divider(height: 1, color: AppColors.cardBorder),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildBottomActionButtons(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reportar pago multimoneda',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  Text(
                    '${widget.studentName} • ${widget.monthPeriod}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStepCircle(1, 'Método'),
          _buildStepLine(1),
          _buildStepCircle(2, 'Datos'),
          _buildStepLine(2),
          _buildStepCircle(3, 'Comprobante'),
        ],
      ),
    );
  }

  Widget _buildStepCircle(int step, String label) {
    final bool isCompleted = _isSubmitted || _currentStep > step;
    final bool isActive = !_isSubmitted && _currentStep == step;

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? const Color(0xFF059669)
                : isActive
                ? AppColors.primaryBlue
                : const Color(0xFFE2E8F0),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : Text(
                    '$step',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.white : AppColors.textMuted,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive || isCompleted
                ? FontWeight.bold
                : FontWeight.w500,
            color: isActive || isCompleted
                ? AppColors.darkNavy
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int afterStep) {
    final bool isCompleted = _isSubmitted || _currentStep > afterStep;
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: isCompleted ? const Color(0xFF059669) : AppColors.cardBorder,
    );
  }

  // PASO 1: SELECCIONAR MÉTODO
  Widget _buildStep1Widget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿Cómo realizaste el pago?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Selecciona la moneda y el método utilizado.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
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
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.access_time, color: Color(0xFF166534), size: 18),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tasa BCV oficial: 1 USD = ${_currentTasaBcv.toStringAsFixed(2).replaceAll('.', ',')} VES',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF166534),
                    ),
                  ),
                  const Text(
                    'Sincronizada automáticamente vía API',
                    style: TextStyle(fontSize: 10, color: Color(0xFF15803D)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMethodCard(
    String title,
    String badge,
    String subtitle,
    IconData icon,
  ) {
    final bool isSelected = _selectedMethod == title;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedMethod = title;
          _updateMontoField(widget.amountUsd);
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : AppColors.cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFDBEAFE)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primaryBlue : AppColors.textMuted,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        badge,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primaryBlue : Colors.white,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryBlue
                      : AppColors.cardBorder,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PASO 2: DATOS DEL COLEGIO + FORMULARIO
  Widget _buildStep2Widget() {
    final bool isBs =
        _selectedMethod == 'Pago Móvil' ||
        _selectedMethod == 'Transferencia Bancaria';
    final double rawMonto =
        double.tryParse(_montoController.text.replaceAll(',', '.')) ?? 0.0;
    final double equivalenteUsd = isBs ? _vesToUsd(rawMonto) : rawMonto;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDatosColegioInfoCard(),
        const SizedBox(height: 16),

        const Text(
          'Datos de la transacción',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ingresa los datos tal como aparecen en tu comprobante.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Banco de origen',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedOriginBank,
                    hint: const Text(
                      'Seleccionar banco',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                    decoration: _inputDecoration(''),
                    items: _banks
                        .map(
                          (b) => DropdownMenuItem(
                            value: b,
                            child: Text(
                              b,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedOriginBank = val),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cuenta destino',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedDestinationBank,
                    decoration: _inputDecoration(''),
                    items: _destinationAccounts
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedDestinationBank = val!),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),
        const Text(
          'Referencia bancaria',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _refController,
          onChanged: _onRefChanged,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Mínimo 6 dígitos',
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
            prefixIcon: const Icon(
              Icons.description_outlined,
              color: AppColors.textMuted,
              size: 18,
            ),
            suffixIcon: _isCheckingRef
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_isRefValid
                      ? const Icon(
                          Icons.check_circle,
                          color: Color(0xFF16A34A),
                          size: 20,
                        )
                      : null),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _isRefValid
                    ? const Color(0xFF16A34A)
                    : AppColors.cardBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _isRefValid
                    ? const Color(0xFF16A34A)
                    : AppColors.cardBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _isRefValid
                    ? const Color(0xFF16A34A)
                    : AppColors.primaryBlue,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (_refErrorMessage != null) ...[
          const SizedBox(height: 4),
          Text(
            _refErrorMessage!,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ] else if (_isRefValid) ...[
          const SizedBox(height: 4),
          const Text(
            'Referencia válida y disponible para conciliación.',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF16A34A),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],

        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fecha de transacción',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.darkNavy,
                                ),
                              ),
                            ],
                          ),
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Monto pagado (${isBs ? 'VES' : 'USD'})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _montoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+[\.,]?\d{0,2}'),
                      ),
                    ],
                    onChanged: (val) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                    decoration: InputDecoration(
                      prefixText: isBs ? 'Bs. ' : '\$ ',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primaryBlue,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Equivalente estimado',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              Row(
                children: [
                  Text(
                    '\$${equivalenteUsd.toStringAsFixed(2).replaceAll('.', ',')} USD',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Calculado a tasa BCV ${_currentTasaBcv.toStringAsFixed(2).replaceAll('.', ',')} VES/USD',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Tarjeta dinámica con datos del Colegio + Monto a Pagar + Copiar Todo
  Widget _buildDatosColegioInfoCard() {
    final bool isBs =
        _selectedMethod == 'Pago Móvil' ||
        _selectedMethod == 'Transferencia Bancaria';
    double rawMonto =
        double.tryParse(_montoController.text.replaceAll(',', '.')) ?? 0.0;
    if (rawMonto == 0.0) {
      rawMonto = isBs ? (widget.amountUsd * _currentTasaBcv) : widget.amountUsd;
    }

    final String montoStr = isBs
        ? 'Bs. ${rawMonto.toStringAsFixed(2).replaceAll('.', ',')}'
        : '\$${rawMonto.toStringAsFixed(2).replaceAll('.', ',')} USD';

    switch (_selectedMethod) {
      case 'Pago Móvil':
        final Map<String, String> mapPM = {
          'Banco': _pagoMovilColegio['Banco']!,
          'RIF': _pagoMovilColegio['RIF']!,
          'Teléfono': _pagoMovilColegio['Teléfono']!,
          'Titular': _pagoMovilColegio['Titular']!,
          'Monto a pagar': montoStr,
        };
        return _buildInfoBox(
          titulo: 'Datos para Pago Móvil (Colegio)',
          icon: Icons.smartphone,
          color: Colors.blue,
          items: mapPM,
        );

      case 'Zelle':
        final Map<String, String> mapZelle = {
          'Correo': _zelleColegio['Correo']!,
          'Titular': _zelleColegio['Titular']!,
          'Monto a pagar': montoStr,
        };
        return _buildInfoBox(
          titulo: 'Datos para Zelle (Colegio)',
          icon: Icons.mail_outline,
          color: Colors.purple,
          items: mapZelle,
        );

      case 'Transferencia Bancaria':
        final Map<String, String> mapTransf = {
          'Banco': _transferenciaColegio['Banco']!,
          'Cuenta': _transferenciaColegio['Cuenta']!,
          'RIF': _transferenciaColegio['RIF']!,
          'Titular': _transferenciaColegio['Titular']!,
          'Monto a pagar': montoStr,
        };
        return _buildInfoBox(
          titulo: 'Datos para Transferencia Bancaria',
          icon: Icons.account_balance_outlined,
          color: Colors.indigo,
          items: mapTransf,
        );

      default:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            children: [
              Icon(
                Icons.payments_outlined,
                color: Colors.amber.shade900,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'El pago en efectivo se entrega en la caja del colegio. Monto exacto: \$${widget.amountUsd.toStringAsFixed(2).replaceAll('.', ',')} USD.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildInfoBox({
    required String titulo,
    required IconData icon,
    required Color color,
    required Map<String, String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  final String textoCompleto = items.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: textoCompleto));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Todos los datos copiados al portapapeles'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.copy_all, size: 14, color: color),
                      const SizedBox(width: 4),
                      Text(
                        'Copiar todo',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.entries.map((e) {
            final bool isMonto = e.key == 'Monto a pagar';
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Text(
                    '${e.key}: ',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: isMonto
                            ? const Color(0xFF16A34A)
                            : AppColors.darkNavy,
                        fontWeight: isMonto
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: e.value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copiado: ${e.value}'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.copy,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // PASO 3: COMPROBANTE
  Widget _buildStep3Widget() {
    final bool isBs =
        _selectedMethod == 'Pago Móvil' ||
        _selectedMethod == 'Transferencia Bancaria';
    final double rawMonto =
        double.tryParse(_montoController.text.replaceAll(',', '.')) ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Adjunta el comprobante',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Asegúrate de que la referencia, fecha y monto sean legibles.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: _pickComprobanteFile,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _attachedFileBytes != null
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFBFDBFE),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _attachedFileBytes != null
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _attachedFileBytes != null
                        ? Icons.check_circle_outline
                        : Icons.cloud_upload_outlined,
                    color: _attachedFileBytes != null
                        ? const Color(0xFF16A34A)
                        : AppColors.primaryBlue,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _attachedFileName ?? 'Adjuntar captura o comprobante',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _attachedFileBytes != null
                        ? const Color(0xFF16A34A)
                        : AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                    children: [
                      TextSpan(
                        text: _attachedFileBytes != null
                            ? 'Haz clic para '
                            : 'Haz clic aquí para ',
                      ),
                      TextSpan(
                        text: _attachedFileBytes != null
                            ? 'cambiar archivo'
                            : 'seleccionar archivo',
                        style: const TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'JPG, PNG o PDF • Máximo 5 MB',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildSummaryRow('Método', _selectedMethod),
              const SizedBox(height: 8),
              _buildSummaryRow(
                'Monto reportado',
                isBs
                    ? 'Bs. ${rawMonto.toStringAsFixed(2).replaceAll('.', ',')}'
                    : '\$${rawMonto.toStringAsFixed(2).replaceAll('.', ',')} USD',
              ),
              const SizedBox(height: 8),
              _buildSummaryRow('Cuenta', widget.studentName),
              const SizedBox(height: 8),
              _buildSummaryRow(
                'Aplicación',
                'Automática: primero la cuota más antigua',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
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

  Widget _buildBottomActionButtons() {
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text(
              'Volver a mi portal',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_currentStep == 1)
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkNavy,
              side: const BorderSide(color: AppColors.cardBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          )
        else
          OutlinedButton(
            onPressed: () => setState(() => _currentStep--),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkNavy,
              side: const BorderSide(color: AppColors.cardBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text(
              'Atrás',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        if (_currentStep < 3)
          ElevatedButton(
            onPressed:
                (_currentStep == 2 &&
                    !_isRefValid &&
                    _selectedMethod != 'Efectivo USD')
                ? null
                : () async {
                    if (_currentStep == 2) {
                      final bool isUnique =
                          await _validateReferenceUniqueness();
                      if (!isUnique) return;
                      setState(() => _currentStep++);
                    } else {
                      setState(() => _currentStep++);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              disabledBackgroundColor: const Color(0xFFBFDBFE),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: Row(
              children: [
                Text(
                  _isCheckingRef ? 'Verificando...' : 'Continuar',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          )
        else
          ElevatedButton(
            onPressed: (_isSubmitting || _attachedFileBytes == null)
                ? null
                : _submitReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              disabledBackgroundColor: const Color(0xFFBFDBFE),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    children: [
                      Text(
                        'Enviar reporte para conciliación',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
          ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
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
