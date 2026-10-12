import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ReportPaymentDialog extends StatefulWidget {
  final String studentName;
  final String monthPeriod;
  final double amountUsd;
  final double tasaBcv;

  const ReportPaymentDialog({
    super.key,
    this.studentName = 'Sofía Méndez',
    this.monthPeriod = 'Marzo 2025',
    this.amountUsd = 45.00,
    this.tasaBcv = 64.25,
  });

  @override
  State<ReportPaymentDialog> createState() => _ReportPaymentDialogState();
}

class _ReportPaymentDialogState extends State<ReportPaymentDialog> {
  int _currentStep = 1; // 1: Método, 2: Datos, 3: Comprobante
  bool _isSubmitted = false; // Estado final: ¡Reporte enviado!

  // Paso 1: Método
  String? _selectedMethod = 'Pago Móvil';

  // Paso 2: Datos
  String? _selectedOriginBank;
  String _selectedDestinationBank = 'Mercantil · •• 4872';
  final TextEditingController _refController = TextEditingController();
  DateTime _selectedDate = DateTime(2025, 3, 18);
  bool _isRefValid = false;

  // Paso 3: Comprobante
  String? _attachedFileName;
  bool _isSubmitting = false;

  final List<String> _banks = [
    'Banesco',
    'Mercantil',
    'Provincial',
    'Banco de Venezuela',
    'BNC',
  ];

  final List<String> _destinationAccounts = [
    'Mercantil · •• 4872',
    'Banesco · •• 0194',
  ];

  @override
  void dispose() {
    _refController.dispose();
    super.dispose();
  }

  void _onRefChanged(String val) {
    setState(() {
      _isRefValid = val.trim().length >= 6;
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
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _submitReport() async {
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _isSubmitted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double equivalenteVes = widget.amountUsd * widget.tasaBcv;

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
              // Header superior con título y botón cerrar (X)
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
                            'Mensualidad · ${widget.monthPeriod} · ${widget.studentName}',
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

              // Indicador de Pasos (Stepper Header)
              _buildStepperHeader(),
              const SizedBox(height: 24),

              // Contenido según el estado
              if (_isSubmitted)
                _buildSuccessWidget()
              else ...[
                if (_currentStep == 1) _buildStep1Widget(equivalenteVes),
                if (_currentStep == 2) _buildStep2Widget(equivalenteVes),
                if (_currentStep == 3) _buildStep3Widget(equivalenteVes),
              ],

              const SizedBox(height: 24),

              // Barra inferior de botones
              _buildBottomActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  // --- STEPPER HEADER ---
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

  // --- PANTALLA FINAL: ¡REPORTE ENVIADO! ---
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
              fontSize: 13,
              color: AppColors.textMuted,
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
            child: const Text(
              'Reporte #EP-2025-0319',
              style: TextStyle(
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

  // --- PASO 1: SELECCIONAR MÉTODO DE PAGO ---
  Widget _buildStep1Widget(double equivalenteVes) {
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
                    'Tasa BCV oficial: 1 USD = ${widget.tasaBcv.toStringAsFixed(2).replaceAll('.', ',')} VES',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                  ),
                  const Text(
                    'Sincronizada hoy, 18/03/2025 a las 08:00 AM',
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
      onTap: () => setState(() => _selectedMethod = title),
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

  // --- PASO 2: FORMULARIO DE DATOS ---
  Widget _buildStep2Widget(double equivalenteVes) {
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
                    decoration: _inputDecoration(''),
                    items: _banks.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 13)))).toList(),
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
                    decoration: _inputDecoration(''),
                    items: _destinationAccounts.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
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
          style: const TextStyle(fontSize: 13, color: AppColors.darkNavy),
          decoration: InputDecoration(
            hintText: 'Mínimo 6 dígitos',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            prefixIcon: const Icon(Icons.description_outlined, color: AppColors.textMuted, size: 18),
            suffixIcon: _isRefValid ? const Icon(Icons.check_circle, color: AppColors.successGreen, size: 20) : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _isRefValid ? AppColors.successGreen : AppColors.cardBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _isRefValid ? AppColors.successGreen : AppColors.cardBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _isRefValid ? AppColors.successGreen : AppColors.primaryBlue, width: 1.5)),
          ),
        ),
        if (_isRefValid) ...[
          const SizedBox(height: 4),
          const Text('Referencia disponible para conciliación.', style: TextStyle(fontSize: 11, color: AppColors.successGreen, fontWeight: FontWeight.bold)),
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
                              Text('${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}', style: const TextStyle(fontSize: 13, color: AppColors.darkNavy)),
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
                  const Text('Monto pagado (VES)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Text('Bs. ${equivalenteVes.toStringAsFixed(2).replaceAll('.', ',')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
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
                  Text('\$${widget.amountUsd.toStringAsFixed(2).replaceAll('.', ',')} USD', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.successGreen)),
                  const SizedBox(width: 8),
                  Text('Calculado a tasa BCV ${widget.tasaBcv.toStringAsFixed(2).replaceAll('.', ',')} VES/USD', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- PASO 3: COMPROBANTE ---
  Widget _buildStep3Widget(double equivalenteVes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Adjunta el comprobante', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkNavy)),
        const SizedBox(height: 4),
        const Text('Asegúrate de que la referencia, fecha y monto sean legibles.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 18),

        GestureDetector(
          onTap: () {
            setState(() {
              _attachedFileName = 'Comprobante_Pago_Marzo.png';
            });
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primaryBlue, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  _attachedFileName ?? 'Adjuntar captura o comprobante',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    children: [
                      TextSpan(text: 'Arrastra el archivo aquí o '),
                      TextSpan(text: 'selecciónalo', style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text('JPG, PNG o PDF · Máximo 5 MB', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
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
              _buildSummaryRow('Método', _selectedMethod ?? 'Pago Móvil'),
              const SizedBox(height: 8),
              _buildSummaryRow('Monto reportado', 'Bs. ${equivalenteVes.toStringAsFixed(2).replaceAll('.', ',')}'),
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

  // --- BOTONES DE NAVEGACIÓN INFERIOR ---
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
                : () => setState(() => _currentStep++),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              disabledBackgroundColor: const Color(0xFFBFDBFE),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: const Row(
              children: [
                Text('Continuar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          )
        else
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
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

  InputDecoration _inputDecoration(String hint) {
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