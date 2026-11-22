import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/audit_filter.dart';
import '../../domain/audit_operation.dart';
import 'audit_format.dart';

/// CA2: filtros por usuario, fecha y tipo de operación.
class AuditFiltersBar extends StatefulWidget {
  final AuditFilter filter;
  final ValueChanged<AuditFilter> onChanged;
  const AuditFiltersBar({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  @override
  State<AuditFiltersBar> createState() => _AuditFiltersBarState();
}

class _AuditFiltersBarState extends State<AuditFiltersBar> {
  static const _selectable = [
    AuditOperation.registro,
    AuditOperation.modificacion,
    AuditOperation.aprobacion,
    AuditOperation.rechazo,
    AuditOperation.eliminacion,
  ];

  late final TextEditingController _userCtrl = TextEditingController(
    text: widget.filter.user,
  );
  Timer? _debounce;

  @override
  void didUpdateWidget(covariant AuditFiltersBar old) {
    super.didUpdateWidget(old);
    if (widget.filter.user.isEmpty && _userCtrl.text.isNotEmpty) {
      _userCtrl.clear();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _userCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final f = widget.filter;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: (f.from != null && f.to != null)
          ? DateTimeRange(start: f.from!, end: f.to!)
          : null,
    );
    if (picked != null) {
      widget.onChanged(f.copyWith(from: picked.start, to: picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    final hasRange = f.from != null && f.to != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: auditCardDecoration(),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 250,
            height: kAuditControlHeight,
            child: TextField(
              controller: _userCtrl,
              style: auditText(),
              decoration: auditInputDecoration(
                hint: 'Filtrar por usuario',
                icon: Icons.person_search_outlined,
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  widget.onChanged(f.copyWith(user: v));
                });
              },
            ),
          ),
          SizedBox(
            width: 230,
            height: kAuditControlHeight,
            child: InputDecorator(
              decoration: auditInputDecoration(),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AuditOperation?>(
                  value: f.operation,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(kAuditControlRadius),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted,
                  ),
                  style: auditText(),
                  items: [
                    const DropdownMenuItem<AuditOperation?>(
                      value: null,
                      child: Text('Todas las operaciones'),
                    ),
                    for (final op in _selectable)
                      DropdownMenuItem<AuditOperation?>(
                        value: op,
                        child: Text(op.label),
                      ),
                  ],
                  onChanged: (v) => widget.onChanged(
                    v == null
                        ? f.copyWith(clearOperation: true)
                        : f.copyWith(operation: v),
                  ),
                ),
              ),
            ),
          ),
          OutlinedButton.icon(
            style: auditOutlinedButtonStyle(),
            onPressed: _pickRange,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              hasRange
                  ? '${fmtDate(f.from!)} – ${fmtDate(f.to!)}'
                  : 'Rango de fechas',
            ),
          ),
          if (!f.isEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, kAuditControlHeight),
                foregroundColor: AppColors.primaryBlue,
                textStyle: auditText(weight: FontWeight.w600),
              ),
              onPressed: () => widget.onChanged(const AuditFilter()),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Limpiar filtros'),
            ),
        ],
      ),
    );
  }
}
