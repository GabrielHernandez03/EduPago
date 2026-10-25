import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';

class GenerateBillingDialog extends StatefulWidget {
  final String colegioId;
  final VoidCallback onBillingGenerated;

  const GenerateBillingDialog({
    super.key,
    required this.colegioId,
    required this.onBillingGenerated,
  });

  @override
  State<GenerateBillingDialog> createState() => _GenerateBillingDialogState();
}

class _GenerateBillingDialogState extends State<GenerateBillingDialog> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _conceptoController =
      TextEditingController(text: 'Mensualidad escolar');
  final TextEditingController _montoUsdController =
      TextEditingController(text: '45.00');

  String _selectedMonth = 'Noviembre';
  String _selectedYear = '2026';
  DateTime _dueDate = DateTime(2026, 11, 5);

  bool _isProcessing = false;
  int _activeStudentsCount = 0;
  bool _isLoadingCount = true;

  final List<String> _months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre'
  ];

  final List<String> _years = ['2025', '2026', '2027'];

  @override
  void initState() {
    super.initState();
    _countActiveStudents();
  }

  @override
  void dispose() {
    _conceptoController.dispose();
    _montoUsdController.dispose();
    super.dispose();
  }

  /// Cuenta únicamente estudiantes con estatus 'activo = true'
  Future<void> _countActiveStudents() async {
    try {
      final response = await _supabase
          .from('estudiantes')
          .select('id')
          .eq('colegio_id', widget.colegioId)
          .eq('activo', true);

      if (mounted) {
        setState(() {
          _activeStudentsCount = (response as List).length;
          _isLoadingCount = false;
        });
      }
    } catch (e) {
      debugPrint('Error contando estudiantes activos: $e');
      if (mounted) setState(() => _isLoadingCount = false);
    }
  }

  /// Obtiene o crea el concepto_id de forma garantizada
  Future<String> _getOrCreateConceptoId(String conceptoNombre, double montoUsd) async {
    final existingConcept = await _supabase
        .from('conceptos_cobro')
        .select('id')
        .eq('colegio_id', widget.colegioId)
        .ilike('nombre', conceptoNombre)
        .maybeSingle();

    if (existingConcept != null && existingConcept['id'] != null) {
      return existingConcept['id'].toString();
    }

    // Se asigna 'monto_usd' para cumplir la restricción NOT NULL de conceptos_cobro
    final newConcept = await _supabase
        .from('conceptos_cobro')
        .insert({
          'colegio_id': widget.colegioId,
          'nombre': conceptoNombre,
          'monto_usd': montoUsd,
          'monto_defecto_usd': montoUsd,
        })
        .select('id')
        .single();

    return newConcept['id'].toString();
  }

  /// Ejecuta el proceso de facturación masiva
  Future<void> _executeMassBilling() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    try {
      final String periodo = '$_selectedMonth $_selectedYear';
      final String conceptoNombre = _conceptoController.text.trim();
      final double montoUsd =
          double.tryParse(_montoUsdController.text.replaceAll(',', '.')) ?? 0.0;
      final String fechaVencimiento =
          '${_dueDate.year}-${_dueDate.month.toString().padLeft(2, '0')}-${_dueDate.day.toString().padLeft(2, '0')}';

      // 1. Obtener obligatoriamente el concepto_id
      final String conceptoId = await _getOrCreateConceptoId(conceptoNombre, montoUsd);

      // 2. Obtener lista de estudiantes ACTIVOS del colegio
      final activeStudents = await _supabase
          .from('estudiantes')
          .select('id')
          .eq('colegio_id', widget.colegioId)
          .eq('activo', true);

      final List<Map<String, dynamic>> students =
          List<Map<String, dynamic>>.from(activeStudents);

      if (students.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay estudiantes activos registrados para facturar.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
          setState(() => _isProcessing = false);
        }
        return;
      }

      int generatedCount = 0;
      int skippedDuplicates = 0;

      // 3. Insertar las cuotas incluyendo concepto_id
      for (final student in students) {
        final studentId = student['id'].toString();

        try {
          await _supabase.from('cuotas').insert({
            'colegio_id': widget.colegioId,
            'estudiante_id': studentId,
            'concepto_id': conceptoId,
            'concepto': conceptoNombre,
            'periodo': periodo,
            'monto_usd': montoUsd,
            'fecha_vencimiento': fechaVencimiento,
            'fecha_corte': fechaVencimiento,
            'estado': 'pendiente',
            'creado_at': DateTime.now().toIso8601String(),
          });
          generatedCount++;
        } on PostgrestException catch (e) {
          if (e.code == '23505') {
            skippedDuplicates++;
          } else {
            rethrow;
          }
        }
      }

      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.pop(context);

        _showSummarySnackBar(
          generatedCount: generatedCount,
          skippedDuplicates: skippedDuplicates,
          periodo: periodo,
        );

        widget.onBillingGenerated();
      }
    } catch (e) {
      debugPrint('Error al generar facturación masiva: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar la facturación: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showSummarySnackBar({
    required int generatedCount,
    required int skippedDuplicates,
    required String periodo,
  }) {
    String msg = '';
    Color bg = const Color(0xFF059669);

    if (generatedCount > 0 && skippedDuplicates == 0) {
      msg = '¡Éxito! Se generaron $generatedCount cuotas para el período $periodo.';
    } else if (generatedCount > 0 && skippedDuplicates > 0) {
      msg = 'Facturación parcial: $generatedCount cuotas creadas. $skippedDuplicates estudiantes ya tenían el cargo previamente.';
      bg = Colors.orange.shade800;
    } else if (generatedCount == 0 && skippedDuplicates > 0) {
      msg = 'El proceso fue omitido: Todas las cuotas para $periodo ya fueron generadas previamente.';
      bg = Colors.amber.shade900;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primaryBlue),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _dueDate) {
      setState(() => _dueDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          Icons.calendar_month_outlined,
                          color: AppColors.primaryBlue,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Generar facturación masiva',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                          Text(
                            'Emisión automática de cuotas mensuales',
                            style: TextStyle(
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
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_alt_outlined,
                        color: Color(0xFF166534), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _isLoadingCount
                          ? const Text('Consultando matrícula activa...',
                              style: TextStyle(fontSize: 12, color: Color(0xFF166534)))
                          : Text(
                              'Se facturará a $_activeStudentsCount estudiantes con estatus "Activo". Se excluirán los retirados.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF166534),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Concepto de cobro',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _conceptoController,
                decoration: _inputDecoration('Ej. Mensualidad escolar'),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Ingresa el concepto' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mes correspondiente',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedMonth,
                          decoration: _inputDecoration(''),
                          items: _months
                              .map((m) =>
                                  DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedMonth = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Año',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedYear,
                          decoration: _inputDecoration(''),
                          items: _years
                              .map((y) =>
                                  DropdownMenuItem(value: y, child: Text(y, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedYear = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Monto por cuota (\$ USD)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _montoUsdController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+[\.,]?\d{0,2}'))
                          ],
                          decoration: _inputDecoration('\$ 0.00'),
                          validator: (val) => (val == null || val.trim().isEmpty)
                              ? 'Ingresa el monto'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Fecha de vencimiento',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _selectDueDate(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_dueDate.day.toString().padLeft(2, '0')}/${_dueDate.month.toString().padLeft(2, '0')}/${_dueDate.year}',
                                  style: const TextStyle(
                                      fontSize: 13, color: AppColors.darkNavy),
                                ),
                                const Icon(Icons.calendar_month_outlined,
                                    size: 16, color: AppColors.textMuted),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.darkNavy,
                      side: const BorderSide(color: AppColors.cardBorder),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _executeMassBilling,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isProcessing
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
                              Icon(Icons.bolt, size: 18),
                              SizedBox(width: 6),
                              Text('Generar cuotas ahora',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
          borderSide: const BorderSide(color: AppColors.cardBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.cardBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.primaryBlue, width: 1.5)),
    );
  }
}