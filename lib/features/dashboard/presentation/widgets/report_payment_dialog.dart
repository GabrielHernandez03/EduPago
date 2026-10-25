// lib/features/dashboard/presentation/widgets/report_payment_dialog.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/bcv_service.dart';
import '../../../../core/theme/app_colors.dart';

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
    this.tasaBcv = 886.23,
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
  double _currentTasaBcv = 886.23;

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

  final List<String> banks = [
    'Banesco',
    'Mercantil',
    'Provincial',
    'Banco de Venezuela',
    'BNC',
    'BFC',
    'Bancaribe',
  ];

  final List<String> destinationAccounts = [
    'Mercantil 4872',
    'Banesco 0194',
    'BNC 8812',
  ];

  @override
  void initState() {
    super.initState();
    _currentTasaBcv = widget.tasaBcv > 0 ? widget.tasaBcv : 886.23;
    _initDataAndRate();
  }

  @override
  void dispose() {
    _refController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  /// Carga la tasa BCV real y la deuda pendiente real del estudiante
  Future<void> _initDataAndRate() async {
    // 1. Obtener Tasa BCV en vivo de la API
    try {
      final bcvData = await _bcvService.getLatestBcvRate();
      if (mounted && bcvData.rate > 0) {
        setState(() => _currentTasaBcv = bcvData.rate);
      }
    } catch (e) {
      debugPrint('Error obteniendo tasa BCV en diálogo: $e');
    }

    // 2. Consultar deuda pendiente real en v_saldo_cuotas
    double initialUsd = widget.amountUsd;
    if (widget.studentId != null && widget.studentId!.isNotEmpty) {
      try {
        final res = await _supabase
            .from('v_saldo_cuotas')
            .select('saldo_usd')
            .eq('estudiante_id', widget.studentId!)
            .maybeSingle();

        if (res != null && res['saldo_usd'] != null) {
          final double saldoReal = (res['saldo_usd'] as num).toDouble();
          if (saldoReal > 0) initialUsd = saldoReal;
        }
      } catch (e) {
        debugPrint('Error consultando saldo del estudiante: $e');
      }
    }

    // Pre-llenar campo de monto editable
    if (mounted) {
      _updateMontoField(initialUsd);
    }
  }

  void _updateMontoField(double usdAmount) {
    final bool isBs = _selectedMethod == 'Pago Móvil' || _selectedMethod == 'Transferencia Bancaria';
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
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        setState(() {
          _attachedFileName = file.name;
          _attachedFileBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Error al seleccionar archivo: $e');
    }
  }

  /// Validación anti-fraude: Verifica referencia en Supabase
  Future<bool> _validateReferenceUniqueness() async {
    final ref = _refController.text.trim();
    if (_selectedMethod == 'Efectivo USD') return true;

    setState(() => _isCheckingRef = true);
    try {
      final response = await _supabase
          .from('pagos')
          .select('id')
          .eq('referencia', ref)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _refErrorMessage = 'Esta referencia ya fue registrada previamente en el sistema.';
          _isRefValid = false;
        });
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error verificando referencia: $e');
      return true;
    } finally {
      if (mounted) setState(() => _isCheckingRef = false);
    }
  }

  /// Registro final del pago obligatorio con subida a Supabase Storage
  Future<void> _submitReport() async {
    if (_attachedFileBytes == null || _attachedFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, adjunta la captura o imagen del comprobante.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = _supabase.auth.currentUser;
      String repId = '';
      String colegioId = '';

      if (user != null) {
        final rep = await _supabase
            .from('representantes')
            .select('id, colegio_id')
            .eq('perfil_id', user.id)
            .maybeSingle();

        if (rep != null) {
          repId = rep['id'].toString();
          colegioId = rep['colegio_id']?.toString() ?? '';
        }
      }

      if (colegioId.isEmpty && widget.studentId != null) {
        final est = await _supabase
            .from('estudiantes')
            .select('colegio_id')
            .eq('id', widget.studentId!)
            .maybeSingle();
        if (est != null && est['colegio_id'] != null) {
          colegioId = est['colegio_id'].toString();
        }
      }

      final bool isBs = _selectedMethod == 'Pago Móvil' || _selectedMethod == 'Transferencia Bancaria';
      final double montoIngresado = double.tryParse(_montoController.text.replaceAll(',', '.')) ?? 0.0;
      final double montoUsdEquivalente = isBs ? (montoIngresado / _currentTasaBcv) : montoIngresado;

      // 1. Subida del comprobante a Supabase Storage
      final String fileExt = _attachedFileName!.split('.').last;
      final String storagePath = '${DateTime.now().millisecondsSinceEpoch}_${_refController.text.trim()}.$fileExt';

      await _supabase.storage.from('comprobantes').uploadBinary(
        storagePath,
        _attachedFileBytes!,
      );

      final String comprobanteUrl = _supabase.storage.from('comprobantes').getPublicUrl(storagePath);

      String metodoKey = 'pago_movil';
      if (_selectedMethod == 'Zelle') metodoKey = 'zelle';
      if (_selectedMethod == 'Transferencia Bancaria') metodoKey = 'transferencia';
      if (_selectedMethod == 'Efectivo USD') metodoKey = 'efectivo';

      final String refStr = _selectedMethod == 'Efectivo USD'
          ? 'EFECTIVO_${DateTime.now().millisecondsSinceEpoch}'
          : _refController.text.trim();

      // 2. Inserción en la tabla 'pagos'
      await _supabase.from('pagos').insert({
        'colegio_id': colegioId,
        'representante_id': repId,
        'monto': montoIngresado,
        'moneda': isBs ? 'VES' : 'USD',
        'tasa_aplicada': isBs ? _currentTasaBcv : null,
        'monto_usd_equivalente': montoUsdEquivalente,
        'metodo': metodoKey,
        'referencia': refStr,
        'banco_origen': _selectedOriginBank,
        'fecha_pago': '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
        'comprobante_path': comprobanteUrl,
        'estado': 'pendiente',
        'creado_at': DateTime.now().toIso8601String(),
      });

      final String reportCode = 'EP-${DateTime.now().year}-${refStr.length >= 4 ? refStr.substring(refStr.length - 4) : '0319'}';

      if (mounted) {
        setState(() {
          _generatedReportCode = reportCode;
          _isSubmitting = false;
          _isSubmitted = true;
        });
      }
    } catch (e) {
      debugPrint('Error al subir comprobante o registrar pago: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar el reporte: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 580,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
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
                              fontSize: 11,
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
              const SizedBox(height: 20),

              _buildStepperHeader(),
              const SizedBox(height: 24),

              if (_isSubmitted)
                _buildSuccessWidget()
              else ...[
                if (_currentStep == 1) _buildStep1Widget(),
                if (_currentStep == 2) _buildStep2Widget(),
                if (_currentStep == 3) _buildStep3Widget(),
                const SizedBox(height: 24),
                _buildBottomActionButtons(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                      color: isActive ? Colors.white : AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.w500,
            color: isActive || isCompleted ? AppColors.darkNavy : AppColors.textMuted,
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

  Widget _buildSuccessWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
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
            'Tu pago fue enviado para conciliación. Te notificaremos cuando sea\nverificado.',
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
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // PASO 1: SELECCIONAR MÉTODO
  Widget _buildStep1Widget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿Cómo realizaste el pago?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkNavy),
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
            _buildMethodCard('Pago Móvil', 'VES', 'Conversión BCV automática', Icons.smartphone),
            _buildMethodCard('Zelle', 'USD', 'Monto directo en dólares', Icons.mail_outline),
            _buildMethodCard('Transferencia Bancaria', 'VES', 'Conversión BCV automática', Icons.account_balance_outlined),
            _buildMethodCard('Efectivo USD', 'USD', 'Entrega directa en caja', Icons.payments_outlined),
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
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

  Widget _buildMethodCard(String title, String badge, String subtitle, IconData icon) {
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
                color: isSelected ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: isSelected ? AppColors.primaryBlue : AppColors.textMuted, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.darkNavy)),
                      const SizedBox(width: 6),
                      Text(badge, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primaryBlue : Colors.white,
                border: Border.all(color: isSelected ? AppColors.primaryBlue : AppColors.cardBorder),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PASO 2: DATOS Y MONTO EDITABLE
  Widget _buildStep2Widget() {
    final bool isBs = _selectedMethod == 'Pago Móvil' || _selectedMethod == 'Transferencia Bancaria';
    final double rawMonto = double.tryParse(_montoController.text.replaceAll(',', '.')) ?? 0.0;
    final double equivalenteUsd = isBs ? (rawMonto / _currentTasaBcv) : rawMonto;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Datos de la transacción', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
        const SizedBox(height: 4),
        const Text('Ingresa los datos tal como aparecen en tu comprobante.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Banco de origen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedOriginBank,
                    hint: const Text('Seleccionar banco', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    decoration: inputDecoration(''),
                    items: banks.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (val) => setState(() => _selectedOriginBank = val),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cuenta destino', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedDestinationBank,
                    decoration: inputDecoration(''),
                    items: destinationAccounts.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (val) => setState(() => _selectedDestinationBank = val!),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Referencia bancaria', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _refController,
          onChanged: _onRefChanged,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Mínimo 6 dígitos',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            prefixIcon: const Icon(Icons.description_outlined, color: AppColors.textMuted, size: 18),
            suffixIcon: _isCheckingRef
                ? const SizedBox(width: 16, height: 16, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)))
                : (_isRefValid ? const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20) : null),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _isRefValid ? const Color(0xFF16A34A) : AppColors.cardBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _isRefValid ? const Color(0xFF16A34A) : AppColors.cardBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _isRefValid ? const Color(0xFF16A34A) : AppColors.primaryBlue, width: 1.5)),
          ),
        ),
        if (_refErrorMessage != null) ...[
          const SizedBox(height: 4),
          Text(_refErrorMessage!, style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ] else if (_isRefValid) ...[
          const SizedBox(height: 4),
          const Text('Referencia válida y disponible para conciliación.', style: TextStyle(fontSize: 11, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fecha de transacción', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                              const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textMuted),
                              const SizedBox(width: 8),
                              Text(
                                '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                                style: const TextStyle(fontSize: 13, color: AppColors.darkNavy),
                              ),
                            ],
                          ),
                          const Icon(Icons.calendar_month_outlined, size: 16, color: AppColors.textMuted),
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
                  Text('Monto pagado (${isBs ? 'VES' : 'USD'})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _montoController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+[\.,]?\d{0,2}'))],
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.darkNavy),
                    decoration: InputDecoration(
                      prefixText: isBs ? 'Bs. ' : '\$ ',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cardBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cardBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5)),
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
              const Text('Equivalente estimado', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              Row(
                children: [
                  Text(
                    '\$${equivalenteUsd.toStringAsFixed(2).replaceAll('.', ',')} USD',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Calculado a tasa BCV ${_currentTasaBcv.toStringAsFixed(2).replaceAll('.', ',')} VES/USD',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // PASO 3: COMPROBANTE
  Widget _buildStep3Widget() {
    final bool isBs = _selectedMethod == 'Pago Móvil' || _selectedMethod == 'Transferencia Bancaria';
    final double rawMonto = double.tryParse(_montoController.text.replaceAll(',', '.')) ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Adjunta el comprobante', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
        const SizedBox(height: 4),
        const Text('Asegúrate de que la referencia, fecha y monto sean legibles.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: _pickComprobanteFile,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _attachedFileBytes != null ? const Color(0xFF16A34A) : const Color(0xFFBFDBFE),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _attachedFileBytes != null ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _attachedFileBytes != null ? Icons.check_circle_outline : Icons.cloud_upload_outlined,
                    color: _attachedFileBytes != null ? const Color(0xFF16A34A) : AppColors.primaryBlue,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _attachedFileName ?? 'Adjuntar captura o comprobante',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _attachedFileBytes != null ? const Color(0xFF16A34A) : AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    children: [
                      TextSpan(text: _attachedFileBytes != null ? 'Haz clic para ' : 'Haz clic aquí para '),
                      TextSpan(
                        text: _attachedFileBytes != null ? 'cambiar archivo' : 'seleccionar archivo',
                        style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text('JPG, PNG o PDF • Máximo 5 MB', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
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
              _buildSummaryRow('Monto reportado', isBs ? 'Bs. ${rawMonto.toStringAsFixed(2).replaceAll('.', ',')}' : '\$${rawMonto.toStringAsFixed(2).replaceAll('.', ',')} USD'),
              const SizedBox(height: 8),
              _buildSummaryRow('Estudiante', widget.studentName),
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
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
      ],
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text('Volver a mi portal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          )
        else
          OutlinedButton(
            onPressed: () => setState(() => _currentStep--),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkNavy,
              side: const BorderSide(color: AppColors.cardBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text('Atrás', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        if (_currentStep < 3)
          ElevatedButton(
            onPressed: (_currentStep == 2 && !_isRefValid)
                ? null
                : () async {
                    if (_currentStep == 2) {
                      final bool isUnique = await _validateReferenceUniqueness();
                      if (!isUnique) return;
                    }
                    setState(() => _currentStep++);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              disabledBackgroundColor: const Color(0xFFBFDBFE),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: Row(
              children: [
                Text(_isCheckingRef ? 'Verificando...' : 'Continuar', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          )
        else
          ElevatedButton(
            onPressed: (_isSubmitting || _attachedFileBytes == null) ? null : _submitReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              disabledBackgroundColor: const Color(0xFFBFDBFE),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(
                    children: [
                      Text('Enviar reporte para conciliación', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
          ),
      ],
    );
  }

  InputDecoration inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cardBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cardBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5)),
    );
  }
}