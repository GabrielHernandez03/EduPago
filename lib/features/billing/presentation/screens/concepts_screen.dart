import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/billing_repository.dart';
import '../../data/concept_repository.dart';
import '../../data/supabase_concept_repository.dart';
import '../../domain/billing_concept.dart';
import '../widgets/concepts_dialog.dart';

/// Listado de conceptos de cobro del colegio, con alta, edición e historial.
///
/// Los permisos los impone RLS en la base de datos; si un usuario sin rol de
/// administrador llega aquí, las operaciones fallan con un mensaje claro.
class ConceptsScreen extends StatefulWidget {
  const ConceptsScreen({super.key, required this.colegioId, this.repository});

  final String colegioId;
  final ConceptRepository? repository;

  @override
  State<ConceptsScreen> createState() => _ConceptsScreenState();
}

class _ConceptsScreenState extends State<ConceptsScreen> {
  late final ConceptRepository _repository =
      widget.repository ?? SupabaseConceptRepository();
  late Future<List<BillingConcept>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.list(colegioId: widget.colegioId);
  }

  void _reload() {
    setState(() {
      _future = _repository.list(colegioId: widget.colegioId);
    });
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
    if (saved == true) _reload();
  }

  void _openHistory(BillingConcept concept) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HistorySheet(concept: concept, repository: _repository),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conceptos de cobro')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo concepto'),
      ),
      body: FutureBuilder<List<BillingConcept>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final e = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e is BillingRepositoryException ? e.message : '$e'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _reload,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }
          final concepts = snapshot.data ?? const [];
          if (concepts.isEmpty) {
            return const Center(
              child: Text('Aún no hay conceptos. Crea el primero.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: concepts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ConceptCard(
              concept: concepts[i],
              onEdit: () => _openForm(concepts[i]),
              onHistory: () => _openHistory(concepts[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ConceptCard extends StatelessWidget {
  const _ConceptCard({
    required this.concept,
    required this.onEdit,
    required this.onHistory,
  });

  final BillingConcept concept;
  final VoidCallback onEdit;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final dia = concept.diaVencimiento;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ListTile(
        title: Row(
          children: [
            Flexible(
              child: Text(
                concept.nombre,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (!concept.activo) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('Inactivo', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        subtitle: Text(
          '\$${concept.montoUsd.toStringAsFixed(2)} USD · '
          '${dia == null ? 'Sin día de vencimiento' : 'Vence el día $dia'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Historial',
              icon: const Icon(Icons.history),
              onPressed: onHistory,
            ),
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.concept, required this.repository});

  final BillingConcept concept;
  final ConceptRepository repository;

  static String _fmt(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Historial de "${concept.nombre}"',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 12),
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
                      );
                    }
                    final versions = snapshot.data ?? const [];
                    if (versions.isEmpty) {
                      return const Text(
                        'Este concepto no tiene versiones anteriores.',
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: versions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final v = versions[i];
                        final monto = v.montoUsd == null
                            ? '—'
                            : '\$${v.montoUsd!.toStringAsFixed(2)}';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '$monto USD · vence el día ${v.diaVencimiento ?? '—'}',
                          ),
                          subtitle: Text(
                            'Vigente del ${_fmt(v.vigenteDesde)} '
                            'al ${_fmt(v.vigenteHasta)}',
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
