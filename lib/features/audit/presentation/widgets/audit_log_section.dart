import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../data/audit_repository.dart';
import '../../data/supabase_audit_repository.dart';
import '../../domain/audit_entry.dart';
import '../../domain/audit_filter.dart';
import 'audit_entry_tile.dart';
import 'audit_filters_bar.dart';
import 'audit_format.dart';

/// HS20: historial de operaciones financieras (pantalla completa del admin).
class AuditLogSection extends StatefulWidget {
  final String colegioId;
  final VoidCallback onBack;
  final AuditRepository? repository; // inyectable para pruebas
  const AuditLogSection({
    super.key,
    required this.colegioId,
    required this.onBack,
    this.repository,
  });

  @override
  State<AuditLogSection> createState() => _AuditLogSectionState();
}

class _AuditLogSectionState extends State<AuditLogSection> {
  static const _pageSize = 25;
  late final AuditRepository _repo =
      widget.repository ?? SupabaseAuditRepository();

  int _request = 0; // descarta respuestas obsoletas al cambiar filtros
  AuditFilter _filter = const AuditFilter();
  List<AuditEntry> _entries = [];
  bool _firstLoad = true; // true hasta que termina la primera consulta
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _repo.fetch(
        schoolId: widget.colegioId,
        filter: _filter,
        limit: _pageSize,
      );
      if (!mounted || id != _request) return;
      setState(() {
        _entries = rows;
        _hasMore = rows.length == _pageSize;
        _loading = false;
        _firstLoad = false;
      });
    } catch (e) {
      debugPrint('Auditoría: $e');
      if (!mounted || id != _request) return;
      setState(() {
        _error = 'No se pudo cargar la auditoría. Intenta de nuevo.';
        _loading = false;
        _firstLoad = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final id = _request;
    setState(() => _loadingMore = true);
    try {
      final rows = await _repo.fetch(
        schoolId: widget.colegioId,
        filter: _filter,
        offset: _entries.length,
        limit: _pageSize,
      );
      if (!mounted || id != _request) return;
      setState(() {
        _entries = [..._entries, ...rows];
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar más eventos.')),
      );
    }
  }

  void _setFilter(AuditFilter f) {
    setState(() => _filter = f);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    // Carga inicial: skeleton de toda la pantalla (cabecera, filtros y filas).
    if (_firstLoad) return const AuditLogSkeleton();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 20),
        AuditFiltersBar(filter: _filter, onChanged: _setFilter),
        const SizedBox(height: 16),
        _body(),
      ],
    );
  }

  Widget _header() {
    final back = OutlinedButton.icon(
      style: auditOutlinedButtonStyle(),
      onPressed: widget.onBack,
      icon: const Icon(Icons.arrow_back_rounded, size: 16),
      label: const Text('Volver al resumen'),
    );
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.shield_outlined,
          size: 30,
          color: AppColors.primaryBlue,
        ),
        const SizedBox(width: 12),
        const Flexible(
          child: Text(
            'Auditoría de transacciones',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.darkNavy,
            ),
          ),
        ),
      ],
    );
    const subtitle = Text(
      'Historial de operaciones financieras y trazabilidad de acciones administrativas. Solo lectura.',
      style: TextStyle(fontSize: 14, color: AppColors.textMuted),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 6), subtitle],
        );
        if (box.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [text, const SizedBox(height: 12), back],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: text),
            const SizedBox(width: 16),
            back,
          ],
        );
      },
    );
  }

  Widget _body() {
    // Cambio de filtros: cabecera y filtros reales; solo las filas en skeleton.
    if (_loading) return const AuditLogSkeleton(listOnly: true);
    if (_error != null) {
      return _message(
        Icons.error_outline,
        _error!,
        actionLabel: 'Reintentar',
        onAction: _reload,
      );
    }
    if (_entries.isEmpty) {
      return _message(
        Icons.manage_search,
        _filter.isEmpty
            ? 'Aún no hay operaciones registradas.'
            : 'Ninguna operación coincide con los filtros seleccionados.',
        actionLabel: _filter.isEmpty ? null : 'Limpiar filtros',
        onAction: () => _setFilter(const AuditFilter()),
      );
    }
    return Column(
      children: [
        for (final e in _entries) AuditEntryTile(key: ValueKey(e.id), entry: e),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _loadingMore
                ? const AuditLogSkeleton(rows: 2, listOnly: true)
                : OutlinedButton(
                    style: auditOutlinedButtonStyle(),
                    onPressed: _loadMore,
                    child: const Text('Cargar más'),
                  ),
          ),
      ],
    );
  }

  Widget _message(
    IconData icon,
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: AppColors.textMuted)),
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
