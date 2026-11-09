import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/billing_repository.dart';
import '../../data/concept_repository.dart';
import '../../data/supabase_concept_repository.dart';
import '../../domain/billing_concept.dart';

// ============================================================================
// Estilo compartido por todos los pop-ups de conceptos de cobro
// ============================================================================

const _kIconBg = Color(0xFFEFF6FF);
const _kGreen = Color(0xFF16A34A);
const _kSoftBg = Color(0xFFF8FAFC);

ButtonStyle _primaryStyle([Color? color]) => ElevatedButton.styleFrom(
  backgroundColor: color ?? AppColors.primaryBlue,
  foregroundColor: Colors.white,
  elevation: 0,
  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  textStyle: const TextStyle(fontWeight: FontWeight.bold),
);

ButtonStyle _secondaryStyle() => OutlinedButton.styleFrom(
  foregroundColor: AppColors.darkNavy,
  side: const BorderSide(color: AppColors.cardBorder),
  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

Widget _fieldLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: AppColors.darkNavy,
    ),
  ),
);

InputDecoration _fieldDecoration(String hint) => InputDecoration(
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

/// Contenedor base: blanco, esquinas redondeadas y sin el tinte lila de Material 3.
class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.width,
    required this.child,
    this.maxHeightFactor = 0.85,
    this.padding = 28,
  });

  final double width;
  final double maxHeightFactor;
  final double padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: width,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * maxHeightFactor,
        ),
        padding: EdgeInsets.all(padding),
        child: child,
      ),
    );
  }
}

/// Encabezado común: ícono en caja azul clara, título, subtítulo y cierre.
class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kIconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primaryBlue, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
        ),
      ],
    );
  }
}

/// Confirmación con el mismo estilo que el resto de la aplicación.
Future<bool?> _showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required IconData icon,
  required Color color,
  required String confirmLabel,
  List<String> details = const [],
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _DialogShell(
      width: 420,
      maxHeightFactor: 0.8,
      padding: 24,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withAlpha(28),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.darkNavy,
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kSoftBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: details
                      .map(
                        (d) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: _secondaryStyle(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: _primaryStyle(color),
                    child: Text(confirmLabel),
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

// ============================================================================
// Pop-up principal: listado y acciones
// ============================================================================

/// Pop-up de administración de conceptos de cobro: listado, alta, edición,
/// historial de versiones y activar/desactivar.
///
/// Se cierra devolviendo `true` si hubo algún cambio, para que quien lo abrió
/// pueda recargar sus datos.
class ConceptsDialog extends StatefulWidget {
  const ConceptsDialog({super.key, required this.colegioId, this.repository});

  final String colegioId;
  final ConceptRepository? repository;

  @override
  State<ConceptsDialog> createState() => _ConceptsDialogState();
}

class _ConceptsDialogState extends State<ConceptsDialog> {
  late final ConceptRepository _repository =
      widget.repository ?? SupabaseConceptRepository();

  List<BillingConcept> _concepts = const [];
  bool _loading = true;
  bool _changed = false;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _msg(Object e) => e is BillingRepositoryException ? e.message : '$e';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repository.list(colegioId: widget.colegioId);
      if (!mounted) return;
      setState(() {
        _concepts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _msg(e);
      });
    }
  }

  Future<void> _openForm([BillingConcept? concept]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ConceptFormDialog(
        colegioId: widget.colegioId,
        repository: _repository,
        concept: concept,
      ),
    );
    if (saved == true) {
      _changed = true;
      await _load();
    }
  }

  void _openHistory(BillingConcept concept) {
    showDialog<void>(
      context: context,
      builder: (_) => _HistoryDialog(concept: concept, repository: _repository),
    );
  }

  Future<void> _toggleActive(BillingConcept c) async {
    final target = !c.activo;
    final ok = await _showConfirm(
      context,
      title: target ? 'Activar concepto' : 'Desactivar concepto',
      message: target
          ? '"${c.nombre}" volverá a estar disponible para generar cuotas.'
          : '"${c.nombre}" ya no se podrá usar para generar nuevas cuotas. '
                'Las cuotas existentes no cambian.',
      icon: target ? Icons.check_circle_outline : Icons.pause_circle_outline,
      color: target ? _kGreen : Colors.orange.shade700,
      confirmLabel: target ? 'Activar' : 'Desactivar',
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busyId = c.id;
      _error = null;
    });
    try {
      await _repository.setActive(id: c.id, activo: target);
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
    if (mounted) setState(() => _busyId = null);
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      width: 680,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DialogHeader(
            icon: Icons.tune_outlined,
            title: 'Conceptos de cobro',
            subtitle: 'Montos y vencimientos de las cuotas escolares',
            onClose: () => Navigator.pop(context, _changed),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _toolbar(),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Flexible(child: _body()),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, _changed),
              style: _secondaryStyle(),
              child: const Text('Cerrar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    final n = _concepts.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _loading ? 'Cargando...' : '$n ${n == 1 ? 'concepto' : 'conceptos'}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textMuted,
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nuevo concepto'),
          style: _primaryStyle(),
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_concepts.isEmpty) {
      return const SizedBox(
        height: 140,
        child: Center(
          child: Text(
            'Aún no hay conceptos. Crea el primero con "Nuevo concepto".',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wide) _tableHeader(),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _concepts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _row(_concepts[i], wide),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const _headStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    color: AppColors.textMuted,
  );

  Widget _tableHeader() {
    return Container(
      color: _kSoftBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 5, child: Text('CONCEPTO', style: _headStyle)),
          SizedBox(width: 80, child: Text('MONTO', style: _headStyle)),
          SizedBox(width: 90, child: Text('VENCE', style: _headStyle)),
          SizedBox(width: 90, child: Text('ESTADO', style: _headStyle)),
          SizedBox(width: 144),
        ],
      ),
    );
  }

  Widget _statusChip(bool activo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: activo ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: activo ? const Color(0xFF166534) : AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _actions(BillingConcept c) {
    final busy = _busyId == c.id;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Historial',
          icon: const Icon(Icons.history, size: 20),
          color: AppColors.textMuted,
          onPressed: () => _openHistory(c),
        ),
        IconButton(
          tooltip: 'Editar',
          icon: const Icon(Icons.edit_outlined, size: 20),
          color: AppColors.textMuted,
          onPressed: () => _openForm(c),
        ),
        if (busy)
          const SizedBox(
            width: 48,
            height: 48,
            child: Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            tooltip: c.activo ? 'Desactivar' : 'Activar',
            icon: Icon(
              c.activo ? Icons.toggle_on : Icons.toggle_off,
              size: 32,
              color: c.activo ? _kGreen : AppColors.textMuted,
            ),
            onPressed: () => _toggleActive(c),
          ),
      ],
    );
  }

  Widget _row(BillingConcept c, bool wide) {
    final dia = c.diaVencimiento;
    final monto = '\$${c.montoUsd.toStringAsFixed(2)}';
    final nameStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: c.activo ? AppColors.darkNavy : AppColors.textMuted,
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(flex: 5, child: Text(c.nombre, style: nameStyle)),
            SizedBox(
              width: 80,
              child: Text(
                monto,
                style: const TextStyle(fontSize: 13, color: AppColors.darkNavy),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                dia == null ? 'Sin definir' : 'Día $dia',
                style: TextStyle(
                  fontSize: 13,
                  color: dia == null ? AppColors.textMuted : AppColors.darkNavy,
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusChip(c.activo),
              ),
            ),
            SizedBox(
              width: 144,
              child: Align(
                alignment: Alignment.centerRight,
                child: _actions(c),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.nombre, style: nameStyle)),
              _statusChip(c.activo),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$monto USD · ${dia == null ? 'Sin día de vencimiento' : 'Vence el día $dia'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          Align(alignment: Alignment.centerRight, child: _actions(c)),
        ],
      ),
    );
  }
}

// ============================================================================
// Historial de versiones
// ============================================================================

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({required this.concept, required this.repository});

  final BillingConcept concept;
  final ConceptRepository repository;

  static String _fmt(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final dia = concept.diaVencimiento;
    return _DialogShell(
      width: 480,
      maxHeightFactor: 0.8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DialogHeader(
            icon: Icons.history,
            title: 'Historial de cambios',
            subtitle: concept.nombre,
            onClose: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Text(
              'Versión actual: \$${concept.montoUsd.toStringAsFixed(2)} USD · '
              '${dia == null ? 'sin día de vencimiento' : 'vence el día $dia'}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF166534),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'VERSIONES ANTERIORES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: FutureBuilder<List<BillingConceptVersion>>(
              future: repository.history(conceptoId: concept.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  final e = snapshot.error;
                  return Text(
                    e is BillingRepositoryException ? e.message : '$e',
                    style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                  );
                }
                final versions = snapshot.data ?? const [];
                if (versions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Este concepto aún no tiene cambios registrados.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: versions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final v = versions[i];
                    final monto = v.montoUsd == null
                        ? '—'
                        : '\$${v.montoUsd!.toStringAsFixed(2)}';
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$monto USD · vence el día ${v.diaVencimiento ?? '—'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Vigente del ${_fmt(v.vigenteDesde)} '
                            'al ${_fmt(v.vigenteHasta)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: _secondaryStyle(),
              child: const Text('Cerrar'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Formulario de alta y edición
// ============================================================================

/// Alta y edición de un concepto de cobro.
///
/// - Valida cada campo e indica cuáles faltan por completar.
/// - Si se edita monto o día de vencimiento, pide confirmación antes de guardar.
/// - Devuelve `true` al cerrarse si se guardó.
class ConceptFormDialog extends StatefulWidget {
  const ConceptFormDialog({
    super.key,
    required this.colegioId,
    required this.repository,
    this.concept,
  });

  final String colegioId;
  final ConceptRepository repository;

  /// Null = crear; con valor = editar.
  final BillingConcept? concept;

  @override
  State<ConceptFormDialog> createState() => _ConceptFormDialogState();
}

class _ConceptFormDialogState extends State<ConceptFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _montoController;
  int? _dia;
  late bool _activo;

  bool _saving = false;
  bool _submitted = false;
  List<String> _missing = const [];
  String? _error;

  bool get _isEditing => widget.concept != null;

  @override
  void initState() {
    super.initState();
    final c = widget.concept;
    _nombreController = TextEditingController(text: c?.nombre ?? '');
    _montoController = TextEditingController(
      text: c == null ? '' : c.montoUsd.toStringAsFixed(2),
    );
    _dia = c?.diaVencimiento;
    _activo = c?.activo ?? true;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final missing = <String>[
      if (ConceptValidators.nombre(_nombreController.text) != null) 'Nombre',
      if (ConceptValidators.monto(_montoController.text) != null) 'Monto',
      if (ConceptValidators.diaVencimiento(_dia) != null) 'Día de vencimiento',
    ];

    setState(() {
      _submitted = true;
      _missing = missing;
      _error = null;
    });

    if (missing.isNotEmpty) {
      _formKey.currentState?.validate();
      return;
    }

    final nombre = _nombreController.text.trim();
    final monto = ConceptValidators.parseMonto(_montoController.text)!;
    final dia = _dia!;
    final previous = widget.concept;

    // Confirmación previa cuando cambia el monto o el vencimiento.
    if (previous != null &&
        (previous.montoUsd != monto || previous.diaVencimiento != dia)) {
      final confirmed = await _showConfirm(
        context,
        title: 'Confirmar cambios',
        details: [
          if (previous.montoUsd != monto)
            'Monto: \$${previous.montoUsd.toStringAsFixed(2)} → \$${monto.toStringAsFixed(2)}',
          if (previous.diaVencimiento != dia)
            'Vencimiento: día ${previous.diaVencimiento ?? '—'} → día $dia',
        ],
        message:
            'El nuevo valor se aplicará solo a las cuotas que se generen a '
            'partir de ahora. Las cuotas ya generadas no cambian y la versión '
            'anterior queda en el historial.',
        icon: Icons.edit_note,
        color: AppColors.primaryBlue,
        confirmLabel: 'Guardar cambios',
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      if (previous == null) {
        await widget.repository.create(
          colegioId: widget.colegioId,
          nombre: nombre,
          montoUsd: monto,
          diaVencimiento: dia,
        );
      } else {
        await widget.repository.update(
          id: previous.id,
          nombre: nombre,
          montoUsd: monto,
          diaVencimiento: dia,
          activo: _activo,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is BillingRepositoryException ? e.message : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DialogHeader(
            icon: _isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
            title: _isEditing ? 'Editar concepto' : 'Nuevo concepto de cobro',
            subtitle: _isEditing
                ? 'Los cambios de monto aplican solo a cuotas futuras'
                : 'Define el monto y el día de vencimiento',
            onClose: _saving ? null : () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                autovalidateMode: _submitted
                    ? AutovalidateMode.always
                    : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_missing.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Faltan por completar: ${_missing.join(', ')}.',
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _fieldLabel('Nombre del concepto'),
                    TextFormField(
                      controller: _nombreController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _fieldDecoration('Ej. Mensualidad escolar'),
                      validator: ConceptValidators.nombre,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Monto (\$ USD)'),
                              TextFormField(
                                controller: _montoController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d+[\.,]?\d{0,2}'),
                                  ),
                                ],
                                decoration: _fieldDecoration('\$ 0.00'),
                                validator: ConceptValidators.monto,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Vence el día'),
                              DropdownButtonFormField<int>(
                                initialValue: _dia,
                                decoration: _fieldDecoration('Día'),
                                dropdownColor: Colors.white,
                                items: List.generate(
                                  28,
                                  (i) => DropdownMenuItem(
                                    value: i + 1,
                                    child: Text('${i + 1}'),
                                  ),
                                ),
                                onChanged: (v) => setState(() => _dia = v),
                                validator: ConceptValidators.diaVencimiento,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kSoftBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeTrackColor: AppColors.primaryBlue,
                          title: const Text(
                            'Concepto activo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                          subtitle: const Text(
                            'Solo los conceptos activos se pueden facturar',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          value: _activo,
                          onChanged: (v) => setState(() => _activo = v),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                style: _secondaryStyle(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: _primaryStyle(),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
