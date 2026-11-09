import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/billing_repository.dart';
import '../../data/concept_repository.dart';
import '../../data/supabase_billing_repository.dart';
import '../../data/supabase_concept_repository.dart';
import '../../domain/billing_concept.dart';
import '../../domain/billing_request.dart';
import 'concepts_dialog.dart';

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
  final BillingRepository _repository = SupabaseBillingRepository();

  final ConceptRepository _conceptRepository = SupabaseConceptRepository();

  final _formKey = GlobalKey<FormState>();

  List<BillingConcept> _concepts = const [];
  BillingConcept? _selectedConcept;
  bool _autoSelected = false;

  final TextEditingController _conceptoController = TextEditingController(
    text: 'Mensualidad escolar',
  );

  final TextEditingController _montoUsdController = TextEditingController(
    text: '45.00',
  );

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
    'Diciembre',
  ];

  final List<String> _years = ['2025', '2026', '2027'];

  @override
  void initState() {
    super.initState();
    _countActiveStudents();
    _loadConcepts();
  }

  @override
  void didUpdateWidget(covariant GenerateBillingDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.colegioId != widget.colegioId) {
      setState(() {
        _isLoadingCount = true;
        _activeStudentsCount = 0;
        _concepts = const [];
        _selectedConcept = null;
      });

      _countActiveStudents();
      _loadConcepts();
    }
  }

  @override
  void dispose() {
    _conceptoController.dispose();
    _montoUsdController.dispose();
    super.dispose();
  }

  /// Cuenta únicamente estudiantes activos.
  Future<void> _countActiveStudents() async {
    try {
      final colegioId = widget.colegioId;

      final count = await _repository.countActiveStudents(colegioId: colegioId);

      if (!mounted || colegioId != widget.colegioId) {
        return;
      }

      setState(() {
        _activeStudentsCount = count;
        _isLoadingCount = false;
      });
    } catch (e) {
      debugPrint('Error contando estudiantes activos: $e');

      if (mounted) {
        setState(() => _isLoadingCount = false);
      }
    }
  }

  /// Carga los conceptos activos configurados.
  Future<void> _loadConcepts() async {
    try {
      final colegioId = widget.colegioId;

      final all = await _conceptRepository.list(colegioId: colegioId);

      if (!mounted || colegioId != widget.colegioId) {
        return;
      }

      final active = all.where((c) => c.activo).toList();

      setState(() => _concepts = active);

      if (!_autoSelected && _selectedConcept == null && active.isNotEmpty) {
        _autoSelected = true;
        _applyConcept(active.first);
      }
    } catch (e) {
      debugPrint('Error cargando conceptos de cobro: $e');
    }
  }

  /// Abre la administración de conceptos.
  Future<void> _openConceptsDialog() async {
    if (_isProcessing) return;

    final selectedId = _selectedConcept?.id;

    await showDialog<bool>(
      context: context,
      builder: (_) => ConceptsDialog(colegioId: widget.colegioId),
    );

    if (!mounted) return;

    await _loadConcepts();

    if (!mounted) return;

    if (selectedId != null) {
      final matches = _concepts.where((c) => c.id == selectedId);

      _applyConcept(matches.isEmpty ? null : matches.first);
    }
  }

  /// Aplica los datos del concepto seleccionado.
  void _applyConcept(BillingConcept? concept) {
    if (!mounted || _isProcessing) return;

    setState(() {
      _selectedConcept = concept;

      if (concept != null) {
        _conceptoController.text = concept.nombre;

        _montoUsdController.text = concept.montoUsd.toStringAsFixed(2);
      }
    });

    _recomputeDueDate();
  }

  /// Calcula el vencimiento según el concepto.
  void _recomputeDueDate() {
    final dia = _selectedConcept?.diaVencimiento;

    if (dia == null || !mounted) return;

    final month = _months.indexOf(_selectedMonth) + 1;

    setState(() {
      _dueDate = DateTime(int.parse(_selectedYear), month, dia);
    });
  }

  /// Generación masiva de cuotas.
  ///
  /// CORRECCIÓN:
  /// La operación SQL se maneja independientemente
  /// de las operaciones visuales posteriores.
  ///
  /// Un error al actualizar el dashboard no debe
  /// presentarse como un fallo de facturación.
  Future<void> _executeMassBilling() async {
    if (_isProcessing || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Obtener las referencias mientras el widget
    // todavía se encuentra activo.
    final navigator = Navigator.of(context);

    final messenger = ScaffoldMessenger.maybeOf(context);

    final currentRoute = ModalRoute.of(context);

    final onDone = widget.onBillingGenerated;

    final periodo = '$_selectedMonth $_selectedYear';

    final conceptoNombre = _conceptoController.text.trim();

    final montoUsd =
        double.tryParse(_montoUsdController.text.replaceAll(',', '.')) ?? 0.0;

    final solicitud = BillingRequest(
      colegioId: widget.colegioId,
      concepto: conceptoNombre,
      periodo: periodo,
      montoUsd: montoUsd,
      fechaVencimiento: _dueDate,
    );

    setState(() {
      _isProcessing = true;
    });

    late final int generatedCount;
    late final int skippedDuplicates;
    late final int activos;

    // 1. ÚNICAMENTE LA OPERACIÓN SUPABASE.
    try {
      final resultado = await _repository.generateBilling(solicitud);

      generatedCount = resultado.generadas;
      skippedDuplicates = resultado.omitidas;
      activos = resultado.activos;
    } catch (error, stackTrace) {
      debugPrint('Error real en generar_facturacion: $error');

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      await _showAlertDialog(
        title: 'No se pudo generar la facturación',
        message: error is BillingRepositoryException
            ? error.message
            : error.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        color: Colors.red.shade600,
      );

      return;
    }

    // 2. LA FACTURACIÓN YA TERMINÓ.
    if (!mounted) return;

    setState(() {
      _isProcessing = false;
    });

    if (activos == 0) {
      await _showAlertDialog(
        title: 'Sin estudiantes activos',
        message:
            'No hay estudiantes activos registrados '
            'para facturar.',
        icon: Icons.info_outline,
        color: Colors.orange.shade700,
      );

      return;
    }

    // 3. CERRAR DIÁLOGO DE FORMA SEGURA.
    try {
      if (navigator.mounted && currentRoute?.isCurrent == true) {
        navigator.pop();
      }
    } catch (error, stackTrace) {
      debugPrint('Error cerrando diálogo: $error');

      debugPrintStack(stackTrace: stackTrace);
    }

    // 4. MOSTRAR RESULTADO.
    try {
      if (messenger != null && messenger.mounted) {
        _showSummarySnackBar(
          messenger: messenger,
          generatedCount: generatedCount,
          skippedDuplicates: skippedDuplicates,
          periodo: periodo,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Error mostrando resultado: $error');

      debugPrintStack(stackTrace: stackTrace);
    }

    // 5. ACTUALIZAR DASHBOARD.
    try {
      onDone();
    } catch (error, stackTrace) {
      debugPrint('Error recargando dashboard: $error');

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Muestra un diálogo de error o información.
  Future<void> _showAlertDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(icon, color: color, size: 40),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.darkNavy),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Entendido',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Notificación del resultado real.
  void _showSummarySnackBar({
    required ScaffoldMessengerState messenger,
    required int generatedCount,
    required int skippedDuplicates,
    required String periodo,
  }) {
    String msg = '';
    Color bg = const Color(0xFF059669);

    if (generatedCount > 0 && skippedDuplicates == 0) {
      msg =
          '¡Éxito! Se generaron $generatedCount cuotas '
          'para el período $periodo.';
    } else if (generatedCount > 0 && skippedDuplicates > 0) {
      msg =
          'Facturación parcial: $generatedCount '
          'cuotas creadas. $skippedDuplicates '
          'estudiantes ya tenían el cargo previamente.';

      bg = Colors.orange.shade800;
    } else if (generatedCount == 0 && skippedDuplicates > 0) {
      msg =
          'El proceso fue omitido: Todas las cuotas '
          'para $periodo ya fueron generadas previamente.';

      bg = Colors.amber.shade900;
    } else {
      msg = 'No se generaron cuotas nuevas.';
      bg = Colors.orange.shade800;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Selector de fecha de vencimiento.
  Future<void> _selectDueDate(BuildContext context) async {
    if (_isProcessing) return;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
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

    if (!mounted) return;

    if (picked != null && picked != _dueDate) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ENCABEZADO
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
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
                            const Expanded(
                              child: Column(
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
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isProcessing
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ESTUDIANTES ACTIVOS
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.people_alt_outlined,
                          color: Color(0xFF166534),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _isLoadingCount
                              ? const Text(
                                  'Consultando matrícula activa...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF166534),
                                  ),
                                )
                              : Text(
                                  'Se facturará a '
                                  '$_activeStudentsCount estudiantes '
                                  'con estatus "Activo". '
                                  'Se excluirán los retirados.',
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

                  // CONCEPTOS CONFIGURADOS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Concepto configurado',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _isProcessing ? null : _openConceptsDialog,
                        icon: const Icon(Icons.settings_outlined, size: 16),
                        label: const Text(
                          'Administrar conceptos',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  if (_concepts.isEmpty)
                    const Text(
                      'Aún no hay conceptos configurados. '
                      'Créalos en "Administrar conceptos" '
                      'o escribe los datos a mano.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    )
                  else
                    DropdownButtonFormField<BillingConcept?>(
                      key: ValueKey(_selectedConcept?.id ?? 'manual'),
                      initialValue: _selectedConcept,
                      isExpanded: true,
                      decoration: _inputDecoration(''),
                      items: [
                        const DropdownMenuItem<BillingConcept?>(
                          value: null,
                          child: Text(
                            'Personalizado (escribir a mano)',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        ..._concepts.map(
                          (c) => DropdownMenuItem<BillingConcept?>(
                            value: c,
                            child: Text(
                              '${c.nombre} · '
                              '\$${c.montoUsd.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                      onChanged: _isProcessing ? null : _applyConcept,
                    ),

                  const SizedBox(height: 14),

                  // CONCEPTO DE COBRO
                  const Text(
                    'Concepto de cobro',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),

                  const SizedBox(height: 6),

                  TextFormField(
                    controller: _conceptoController,
                    enabled: !_isProcessing,
                    readOnly: _selectedConcept != null,
                    decoration: _inputDecoration('Ej. Mensualidad escolar'),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Ingresa el concepto';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 14),

                  // MES Y AÑO
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mes correspondiente',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedMonth,
                              decoration: _inputDecoration(''),
                              items: _months
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        m,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _isProcessing
                                  ? null
                                  : (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedMonth = val;
                                        });
                                        _recomputeDueDate();
                                      }
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
                            const Text(
                              'Año',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedYear,
                              decoration: _inputDecoration(''),
                              items: _years
                                  .map(
                                    (y) => DropdownMenuItem(
                                      value: y,
                                      child: Text(
                                        y,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _isProcessing
                                  ? null
                                  : (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedYear = val;
                                        });
                                        _recomputeDueDate();
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // MONTO Y VENCIMIENTO
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Monto por cuota (\$ USD)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _montoUsdController,
                              enabled: !_isProcessing,
                              readOnly: _selectedConcept != null,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d+[\.,]?\d{0,2}'),
                                ),
                              ],
                              decoration: _inputDecoration('\$ 0.00'),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Ingresa el monto';
                                }

                                final monto = double.tryParse(
                                  val.replaceAll(',', '.'),
                                );

                                if (monto == null ||
                                    !monto.isFinite ||
                                    monto <= 0) {
                                  return 'Monto inválido';
                                }

                                return null;
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
                            const Text(
                              'Fecha de vencimiento',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkNavy,
                              ),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: _isProcessing
                                  ? null
                                  : () => _selectDueDate(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.cardBorder,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${_dueDate.day.toString().padLeft(2, '0')}/'
                                        '${_dueDate.month.toString().padLeft(2, '0')}/'
                                        '${_dueDate.year}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.darkNavy,
                                        ),
                                      ),
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
                    ],
                  ),

                  const SizedBox(height: 24),

                  // BOTONES
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isProcessing
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.darkNavy,
                          side: const BorderSide(color: AppColors.cardBorder),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bolt, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Generar cuotas ahora',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
