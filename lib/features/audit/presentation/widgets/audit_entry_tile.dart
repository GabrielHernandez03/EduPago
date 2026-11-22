import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/audit_entry.dart';
import '../../domain/audit_operation.dart';
import 'audit_format.dart';

/// CA1: usuario responsable, fecha, hora y operación realizada.
/// Solo lectura (CA3): sin acciones de editar ni eliminar.
class AuditEntryTile extends StatelessWidget {
  final AuditEntry entry;
  const AuditEntryTile({super.key, required this.entry});

  static Color _color(AuditOperation op) => switch (op) {
    AuditOperation.aprobacion => AppColors.successGreen,
    AuditOperation.rechazo || AuditOperation.eliminacion => AppColors.errorRed,
    AuditOperation.modificacion => AppColors.warningAmber,
    _ => AppColors.primaryBlue,
  };

  static String _initials(String name) {
    final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    if (p.isEmpty) return '?';
    final first = p.first[0];
    final second = p.length > 1 ? p.elementAt(1)[0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(entry.operation);
    final d = entry.createdAt;

    final when = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fmtDate(d),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.darkNavy,
          ),
        ),
        Text(
          fmtTime(d),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tint(c),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.tint(c, 0.4)),
      ),
      child: Text(
        entry.operation.label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
      ),
    );

    final who = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.primaryBlue,
          child: Text(
            _initials(entry.userName),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            entry.userName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.darkNavy,
            ),
          ),
        ),
      ],
    );

    final summary = Text(
      entry.summary,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.darkNavy,
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: auditCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: AppColors.primaryBlue.withValues(alpha: 0.04),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: AppColors.primaryBlue,
          collapsedIconColor: AppColors.textMuted,
          title: LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [badge, when],
                    ),
                    const SizedBox(height: 10),
                    summary,
                    const SizedBox(height: 8),
                    who,
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 100, child: when),
                  SizedBox(
                    width: 120,
                    child: Align(alignment: Alignment.centerLeft, child: badge),
                  ),
                  SizedBox(width: 200, child: who),
                  const SizedBox(width: 12),
                  Expanded(child: summary),
                ],
              );
            },
          ),
          children: [_details()],
        ),
      ),
    );
  }

  Widget _details() {
    final isUpdate = entry.antes != null && entry.despues != null;
    final items = entry.changes
        .where((ch) => !auditHiddenFields.contains(ch.field))
        .toList();

    final ref = entry.registroId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ref.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectableText(
                'Referencia: $ref',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          if (items.isEmpty)
            const Text(
              'Sin detalles adicionales.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 28,
              runSpacing: 12,
              children: [
                for (final ch in items)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 140,
                      maxWidth: 300,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          auditFieldLabel(ch.field),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (isUpdate && ch.before != null)
                              ? '${auditFormatValue(ch.before)}  →  ${auditFormatValue(ch.after)}'
                              : auditFormatValue(ch.after ?? ch.before),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
