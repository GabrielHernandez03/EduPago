import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/dashboard_shell.dart' show HoverBuilder;
import '../../domain/account_status.dart';
import '../../domain/student_account_selection.dart';

/// Estado de cuenta del representante. Solo presenta estudiantes vinculados y
/// cuotas que ya devolvió el backend; no calcula ni inventa pagos.
///
/// Diseño: encabezado, ficha del estudiante idéntica a Inicio, tres
/// indicadores y tabla de cuotas. Los estudiantes inactivos siguen visibles
/// en el selector, pero no se pueden elegir.
class RepresentativeAccountStatementSection extends StatefulWidget {
  const RepresentativeAccountStatementSection({
    super.key,
    required this.students,
    required this.account,
    required this.selectedStudentIndex,
    required this.onSelectStudent,
    required this.onRefresh,
    required this.onOpenPayments,
    required this.rate,
    required this.rateLabel,
  });

  final List<Map<String, dynamic>> students;
  final EstadoCuenta? account;
  final int selectedStudentIndex; // -1 = vista familiar.
  final ValueChanged<int> onSelectStudent;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenPayments;
  final double rate;
  final String rateLabel;

  @override
  State<RepresentativeAccountStatementSection> createState() =>
      _RepresentativeAccountStatementSectionState();
}

class _RepresentativeAccountStatementSectionState
    extends State<RepresentativeAccountStatementSection> {
  static const _gap = 20.0;
  final _number = NumberFormat('#,##0.00', 'es_VE');
  String _filter = 'todas';

  String _usd(double n) => '\$${_number.format(n)} USD';
  String _ves(double n) => 'Bs. ${_number.format(n)}';
  String _date(DateTime? d) =>
      d == null ? 'Sin fecha' : DateFormat('dd/MM/yyyy').format(d);

  String _field(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) {
      return '';
    }
    for (final key in keys) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return '';
  }

  String _name(Map<String, dynamic>? st) {
    if (st == null) {
      return 'Toda mi familia';
    }
    final parts = [
      st['nombres'],
      st['apellidos'],
    ].map((p) => (p ?? '').toString().trim()).where((p) => p.isNotEmpty);
    final full = parts.join(' ');
    return full.isEmpty ? 'Estudiante sin nombre' : full;
  }

  String _grade(Map<String, dynamic>? st) =>
      _field(st, const ['grado_seccion', 'grado', 'nivel_grado']);

  String _cedula(Map<String, dynamic>? st) => _field(st, const [
    'cedula',
    'cedula_estudiante',
    'documento_identidad',
    'numero_documento',
    'numero_cedula',
    'nro_cedula',
    'ci',
  ]);

  String _initials(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return 'E';
    }
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  }

  int get _selectedIndex {
    final i = widget.selectedStudentIndex;
    if (i < 0 || i >= widget.students.length) {
      return -1;
    }
    return StudentAccountSelection.canSelect(widget.students[i]) ? i : -1;
  }

  Map<String, dynamic>? get _selectedStudent =>
      _selectedIndex == -1 ? null : widget.students[_selectedIndex];

  String? get _selectedId => _selectedStudent?['id']?.toString();

  List<CuotaEstadoCuenta> _cuotas() {
    final id = _selectedId;
    final rows =
        widget.account?.cuotas
            .where((cuota) => id == null || cuota.estudianteId == id)
            .toList() ??
        <CuotaEstadoCuenta>[];
    rows.sort(
      (a, b) => (b.fechaVencimiento?.millisecondsSinceEpoch ?? -1).compareTo(
        a.fechaVencimiento?.millisecondsSinceEpoch ?? -1,
      ),
    );
    return rows;
  }

  /// No permite que Excel convierta texto controlado por el servidor en fórmula.
  String _csvCell(Object? cell) {
    var value = (cell ?? '').toString();
    if (RegExp(r'^\s*[=+@\-\t\r]').hasMatch(value)) {
      value = "'$value";
    }
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  void _downloadCsv() {
    final account = widget.account;
    if (account == null) {
      return;
    }
    final student = _selectedStudent;
    final studentId = _selectedId;
    final rows = <List<Object?>>[
      ['EDUPAGO - ESTADO DE CUENTA'],
      ['Consulta', student == null ? 'Toda mi familia' : _name(student)],
      ['Fecha de generación', _date(DateTime.now())],
      [
        'Saldo pendiente USD',
        account.pendienteDe(estudianteId: studentId).toStringAsFixed(2),
      ],
      if (studentId == null)
        ['Saldo a favor familiar USD', account.creditoUsd.toStringAsFixed(2)],
      if (studentId == null)
        [
          'Pagos en revisión familiares USD',
          account.enRevisionUsd.toStringAsFixed(2),
        ],
      if (widget.rate > 0)
        ['Tasa BCV referencial', widget.rate.toStringAsFixed(4)],
      [],
      [
        'Estudiante',
        'Concepto',
        'Período',
        'Vencimiento',
        'Monto USD',
        'Aplicado USD',
        'Saldo USD',
        'Estado',
      ],
    ];
    for (final cuota in _cuotas()) {
      Map<String, dynamic>? owner;
      for (final st in widget.students) {
        if (st['id']?.toString() == cuota.estudianteId) {
          owner = st;
          break;
        }
      }
      rows.add([
        owner == null ? 'Estudiante vinculado' : _name(owner),
        cuota.concepto,
        cuota.periodo,
        _date(cuota.fechaVencimiento),
        cuota.montoUsd.toStringAsFixed(2),
        cuota.aplicadoUsd.toStringAsFixed(2),
        cuota.saldoUsd.toStringAsFixed(2),
        _status(cuota).$1,
      ]);
    }
    final csv =
        '\uFEFF${rows.map((r) => r.map(_csvCell).join(';')).join('\r\n')}';
    final blob = html.Blob([utf8.encode(csv)], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'edupago_estado_cuenta_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
      );
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    // La descarga debe tomar el objeto antes de revocar la URL temporal.
    Future<void>.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 640 ? 16.0 : (width < 1000 ? 28.0 : 44.0);
    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(horizontal, 30, horizontal, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 24),
                _studentBanner(),
                const SizedBox(height: 24),
                if (widget.account == null) ...[
                  _loadError(),
                ] else ...[
                  _summaryCards(),
                  const SizedBox(height: 24),
                  _duesPanel(),
                  _familyMovements(),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: widget.onOpenPayments,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Ir a Mis pagos'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Mismo esquema del encabezado de Mis pagos: icono + titulo en una fila,
  // y descripcion alineada con el borde izquierdo del bloque, no con el titulo.
  Widget _header() => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    alignment: WrapAlignment.spaceBetween,
    spacing: 16,
    runSpacing: 14,
    children: [
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 26,
                color: AppColors.primaryBlue,
              ),
              SizedBox(width: 10),
              Text(
                'Mi estado de cuenta',
                style: TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                ),
              ),
            ],
          ),
          SizedBox(height: 7),
          Text(
            'Consulta el saldo, las cuotas y los pagos de tus estudiantes.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
      Tooltip(
        message: 'Descargar archivo CSV con datos reales del estado de cuenta',
        child: OutlinedButton.icon(
          onPressed: widget.account == null ? null : _downloadCsv,
          icon: const Icon(Icons.download_rounded, size: 20),
          label: const Text('Descargar estado de cuenta'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkNavy,
            side: BorderSide(
              color: AppColors.primaryBlue.withValues(alpha: 0.35),
            ),
            backgroundColor: AppColors.surfaceWhite,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ),
    ],
  );

  String _studentDetails(Map<String, dynamic> student) {
    final grado = _grade(student);
    final cedula = _cedula(student);
    return '${grado.isEmpty ? 'Grado no especificado' : grado}  •  C.I. ${cedula.isEmpty ? 'No registrada' : cedula}';
  }

  Widget _featureCornerCurves(Widget child, {required Color color}) {
    return HoverBuilder(
      builder: (context, hovered) {
        final reduceMotion = MediaQuery.of(context).disableAnimations;
        return ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: hovered ? 1.25 : 1.0),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 330),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, _) => CustomPaint(
                      painter: _FeatureCornerCurvesPainter(color, scale: scale),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }

  Widget _dashboardHover(
    Widget child, {
    double radius = 16,
    Color? hoverColor,
    bool outline = true,
  }) {
    return HoverBuilder(
      builder: (context, hovered) {
        final reducedMotion = MediaQuery.of(context).disableAnimations;
        return AnimatedContainer(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 155),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: hovered
                ? [
                    BoxShadow(
                      color: (hoverColor ?? AppColors.primaryBlue).withValues(
                        alpha: 0.065,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: hovered && outline
                  ? (hoverColor ?? AppColors.primaryBlue).withValues(
                      alpha: 0.30,
                    )
                  : Colors.transparent,
            ),
          ),
          child: child,
        );
      },
    );
  }

  Widget _selectorAvatar({
    required bool family,
    required String initials,
    double size = 66,
  }) {
    const bg1 = Color(0xFFEAF2FF);
    const bg2 = Color(0xFFD3E3FF);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg1, bg2],
        ),
        border: Border.all(color: Colors.white, width: size >= 56 ? 2.5 : 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.18),
            blurRadius: size >= 56 ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: family
          ? _FamilyMark(size: size * 0.62, background: const Color(0xFFDDE9FF))
          : Text(
              initials,
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontSize: size >= 56 ? 20 : 13,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  PopupMenuItem<int> _studentMenuItem({
    required int value,
    required Widget leading,
    required String title,
    required String subtitle,
    bool isLast = false,
    bool enabled = true,
  }) {
    final selected = enabled && value == _selectedIndex;
    return PopupMenuItem<int>(
      value: value,
      enabled: enabled,
      padding: EdgeInsets.zero,
      height: 56, // alto mínimo; la fila define su propio alto real
      child: HoverBuilder(
        builder: (context, hovered) => AnimatedContainer(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 125),
          width: double.infinity,
          decoration: BoxDecoration(
            color: (hovered && enabled)
                ? AppColors.primaryLight
                : (selected
                      ? AppColors.primaryLight.withValues(alpha: 0.65)
                      : Colors.transparent),
            border: isLast
                ? null
                : const Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!enabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF1F7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'INACTIVO',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                else if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: AppColors.primaryBlue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _studentBanner() {
    final hasStudents = widget.students.isNotEmpty;
    final linkedCount = widget.students.length;
    final consolidated = _selectedIndex == -1 && hasStudents;
    final selected =
        hasStudents &&
            _selectedIndex >= 0 &&
            _selectedIndex < widget.students.length
        ? widget.students[_selectedIndex]
        : null;
    final name = consolidated
        ? 'Toda mi familia'
        : (selected == null ? 'Sin estudiantes vinculados' : _name(selected));
    final details = consolidated
        ? '$linkedCount estudiantes vinculados'
        : selected != null
        ? _studentDetails(selected)
        : 'Sin grado ni cédula registrados';
    final canChoose =
        linkedCount > 1 ||
        (linkedCount == 1 &&
            !StudentAccountSelection.canSelect(widget.students.first));
    // Incluso con un solo estudiante inactivo, se puede abrir el menú
    // para verlo deshabilitado y consultar la vista familiar.
    final initials = _initials(name);
    final countLabel = consolidated
        ? '$linkedCount'
        : (selected == null ? '0' : '1');

    final inner = Container(
      constraints: const BoxConstraints(minHeight: 122),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          _selectorAvatar(family: consolidated, initials: initials),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'ESTUDIANTE',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.primaryBlue,
                      letterSpacing: 0.45,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.darkNavy,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: details,
                        child: Text(
                          details,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    if (consolidated) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.14,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Vista familiar',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.88),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  countLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
              if (canChoose) ...[
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    ),
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    final cardDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF214576).withValues(alpha: 0.025),
          blurRadius: 14,
          offset: const Offset(0, 3),
        ),
      ],
    );
    final decoratedInner = _featureCornerCurves(
      inner,
      color: AppColors.primaryBlue,
    );
    if (!canChoose) {
      return _dashboardHover(
        DecoratedBox(decoration: cardDecoration, child: decoratedInner),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: AppColors.backgroundLight,
        highlightColor: AppColors.primaryLight,
        splashColor: AppColors.primaryBlue.withValues(alpha: 0.08),
      ),
      child: Builder(
        builder: (ctx) => Semantics(
          button: true,
          label: 'Seleccionar estudiante',
          child: Tooltip(
            message: 'Seleccionar estudiante',
            child: _dashboardHover(
              DecoratedBox(
                decoration: cardDecoration,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('student-switcher'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showStudentChooser(ctx),
                    child: decoratedInner,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showStudentChooser(BuildContext ctx) async {
    final box = ctx.findRenderObject();
    final overlayBox = Overlay.of(ctx).context.findRenderObject();
    if (box is! RenderBox || overlayBox is! RenderBox || !box.hasSize) return;

    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy + box.size.height + 8,
      box.size.width,
      0,
    );

    final orderedStudents = <int>[
      for (var i = 0; i < widget.students.length; i++)
        if (StudentAccountSelection.canSelect(widget.students[i])) i,
      for (var i = 0; i < widget.students.length; i++)
        if (!StudentAccountSelection.canSelect(widget.students[i])) i,
    ];

    final choice = await showMenu<int>(
      context: ctx,
      position: RelativeRect.fromRect(rect, Offset.zero & overlayBox.size),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0xFF1B4785).withValues(alpha: 0.22),
      clipBehavior: Clip.antiAlias,
      menuPadding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: box.size.width),
      // Mismo radio y borde neutro que el resto de las tarjetas.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      items: [
        // Etiqueta discreta, igual que el "ESTUDIANTE" de la tarjeta.
        PopupMenuItem<int>(
          enabled: false,
          padding: EdgeInsets.zero,
          height: 40,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE8EEF8))),
            ),
            child: const Text(
              'SELECCIONAR ESTUDIANTE',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        _studentMenuItem(
          value: -1,
          leading: _selectorAvatar(family: true, initials: '', size: 42),
          title: 'Toda mi familia',
          subtitle: '${widget.students.length} estudiantes vinculados',
        ),
        // Activos primero; los inactivos quedan al final y deshabilitados.
        for (final entry in orderedStudents.indexed)
          _studentMenuItem(
            value: entry.$2,
            isLast: entry.$1 == orderedStudents.length - 1,
            enabled: StudentAccountSelection.canSelect(
              widget.students[entry.$2],
            ),
            leading: _selectorAvatar(
              family: false,
              initials: _initials(_name(widget.students[entry.$2])),
              size: 42,
            ),
            title: _name(widget.students[entry.$2]),
            subtitle:
                StudentAccountSelection.canSelect(widget.students[entry.$2])
                ? _studentDetails(widget.students[entry.$2])
                : 'Estudiante inactivo o retirado',
          ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice < -1 || choice >= widget.students.length) return;
    if (choice >= 0 &&
        !StudentAccountSelection.canSelect(widget.students[choice]))
      return;
    widget.onSelectStudent(choice);
    setState(() => _filter = 'todas');
  }

  Widget _summaryCards() {
    final account = widget.account!;
    final cuotas = _cuotas();
    final pending = cuotas.where((c) => c.tienePendiente).toList();
    final paid = cuotas.where((c) => !c.tienePendiente).toList();
    final balance = account.pendienteDe(estudianteId: _selectedId);
    final today = DateUtils.dateOnly(DateTime.now());
    final future =
        pending
            .where(
              (c) =>
                  c.fechaVencimiento != null &&
                  !DateUtils.dateOnly(c.fechaVencimiento!).isBefore(today),
            )
            .map((c) => c.fechaVencimiento!)
            .toList()
          ..sort();
    final due = future.isEmpty ? null : future.first;
    final overdueCount = pending
        .where(
          (c) =>
              c.fechaVencimiento != null &&
              DateUtils.dateOnly(c.fechaVencimiento!).isBefore(today),
        )
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 650 ? 1 : (width < 900 ? 2 : 3);
        final cardWidth = (width - (columns - 1) * _gap) / columns;
        final cards = <Widget>[
          _metricCard(
            key: const Key('metric-balance'),
            width: cardWidth,
            accent: AppColors.primaryBlue,
            icon: Icons.account_balance_wallet_outlined,
            title: 'Saldo pendiente',
            value: _usd(balance),
            subtitle: widget.rate > 0
                ? 'Equivalente: ${_ves(balance * widget.rate)}'
                : 'Tasa BCV no disponible',
          ),
          _metricCard(
            key: const Key('metric-paid'),
            width: cardWidth,
            accent: AppColors.successGreen,
            icon: Icons.check_circle_outline_rounded,
            title: 'Cuotas pagadas',
            value: '${paid.length}',
            subtitle:
                '${pending.length} ${pending.length == 1 ? 'cuota pendiente' : 'cuotas pendientes'}',
          ),
          _metricCard(
            key: const Key('metric-next-due'),
            width: cardWidth,
            accent: AppColors.warningAmber,
            icon: Icons.calendar_month_outlined,
            title: 'Próximo vencimiento',
            value: due == null ? 'Sin fecha próxima' : _date(due),
            subtitle: overdueCount > 0
                ? '$overdueCount ${overdueCount == 1 ? 'cuota vencida' : 'cuotas vencidas'}'
                : 'Sin cuotas vencidas',
          ),
        ];
        // En escritorio, las tres tarjetas permanecen en una sola fila,
        // ocupan exactamente el mismo ancho y comparten altura.
        if (columns == 3) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: _gap),
                Expanded(child: cards[1]),
                const SizedBox(width: _gap),
                Expanded(child: cards[2]),
              ],
            ),
          );
        }
        return Wrap(spacing: _gap, runSpacing: _gap, children: cards);
      },
    );
  }

  /// Replica la tarjeta de «Solvencia familiar» del Dashboard:
  /// fondo blanco, curvas orgánicas, icono circular con degradado,
  /// contenido centrado y hover sutil. Solo varían el color y los datos.
  Widget _metricCard({
    required Key key,
    required double width,
    required Color accent,
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return _dashboardHover(
      Container(
        key: key,
        width: width,
        constraints: const BoxConstraints(minHeight: 114),
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.36)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.025),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: _featureCornerCurves(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            // Centra vertical y horizontalmente EL GRUPO COMPLETO (ícono +
            // textos), independientemente del largo del saldo o de la fecha.
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [accent.withValues(alpha: 0.88), accent],
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 30,
                        color: AppColors.surfaceWhite,
                      ),
                    ),
                    const SizedBox(width: 17),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          value,
                          maxLines: 1,
                          style: TextStyle(
                            color: accent,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          color: accent,
        ),
      ),
      hoverColor: accent,
    );
  }

  Widget _statusBadge(String value, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
        ] else ...[
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
        ],
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  /// Etiqueta y acento derivados de los saldos reales; sin suposiciones.
  (String, Color, IconData) _status(CuotaEstadoCuenta c) {
    if (!c.tienePendiente) {
      return ('Pagada', AppColors.successGreen, Icons.check_circle_outline);
    }
    final isOverdue =
        c.fechaVencimiento != null &&
        DateUtils.dateOnly(
          c.fechaVencimiento!,
        ).isBefore(DateUtils.dateOnly(DateTime.now()));
    if (isOverdue) {
      return ('Vencida', AppColors.errorRed, Icons.error_outline_rounded);
    }
    if (c.aplicadoUsd > kToleranciaSaldoUsd) {
      return ('Parcial', AppColors.primaryBlue, Icons.timelapse_rounded);
    }
    return ('Pendiente', AppColors.warningAmber, Icons.schedule_rounded);
  }

  Widget _duesPanel() {
    final cuotas = _cuotas();
    final pending = cuotas.where((c) => c.tienePendiente).toList();
    final paid = cuotas.where((c) => !c.tienePendiente).toList();
    final visible = switch (_filter) {
      'pendientes' => pending,
      'pagadas' => paid,
      _ => cuotas,
    };
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.19),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              const Text(
                'Detalle de cuotas',
                style: TextStyle(
                  color: AppColors.darkNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 23,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip('todas', 'Todas'),
                  _filterChip('pagadas', 'Pagadas'),
                  _filterChip('pendientes', 'Pendientes'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 38),
              child: Column(
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    color: AppColors.textMuted,
                    size: 29,
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _filter == 'todas'
                        ? 'No hay cuotas registradas'
                        : 'No hay cuotas en esta categoría',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // En móvil la tabla se desplaza horizontalmente, sin desbordarse.
                final tableWidth = math.max(790.0, constraints.maxWidth);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        _tableHeader(),
                        const SizedBox(height: 9),
                        for (var i = 0; i < visible.length; i++)
                          _dueRow(
                            visible[i],
                            i + 1,
                            showStudent: _selectedId == null,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Mismos colores, íconos y estados que los filtros de
  // representative_payments_section.dart (Mis pagos).
  Widget _filterChip(String id, String label) {
    final color = switch (id) {
      'pendientes' => const Color(0xFFAF6600),
      'pagadas' => const Color(0xFF16845A),
      _ => AppColors.primaryBlue,
    };
    final icon = switch (id) {
      'pendientes' => Icons.schedule_rounded,
      'pagadas' => Icons.check_circle_outline_rounded,
      _ => Icons.grid_view_rounded,
    };
    return _AccountStatementStatusFilter(
      label: label,
      icon: icon,
      color: color,
      selected: _filter == id,
      onTap: () {
        if (_filter == id) return;
        setState(() => _filter = id);
      },
    );
  }

  Widget _tableHeader() => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        _tableCell('CUOTA', 1),
        _tableCell('CONCEPTO', 4),
        _tableCell('VENCIMIENTO', 2),
        _tableCell('MONTO', 2),
        _tableCell('ESTADO', 2),
      ],
    ),
  );

  Widget _tableCell(String text, int flex) => Expanded(
    flex: flex,
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _dueRow(CuotaEstadoCuenta c, int index, {required bool showStudent}) {
    final (label, accent, icon) = _status(c);
    Map<String, dynamic>? owner;
    if (showStudent) {
      for (final s in widget.students) {
        if (s['id']?.toString() == c.estudianteId) {
          owner = s;
          break;
        }
      }
    }
    final outstanding = c.tienePendiente;
    return Container(
      key: ValueKey('cuota-${c.cuotaId}'),
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: outstanding
            ? accent.withValues(alpha: 0.07)
            : AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              'N.º $index',
              style: const TextStyle(
                color: AppColors.darkNavy,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.concepto.isEmpty ? 'Cuota escolar' : c.concepto,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkNavy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (c.periodo.isNotEmpty || owner != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (c.periodo.isNotEmpty) c.periodo,
                      if (owner != null) _name(owner),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _date(c.fechaVencimiento),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.darkNavy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Tooltip(
              message:
                  'Aplicado: ${_usd(c.aplicadoUsd)} · Saldo: ${_usd(c.saldoUsd)}',
              child: Text(
                _usd(c.montoUsd),
                style: const TextStyle(
                  color: AppColors.darkNavy,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusBadge(label, accent, icon: icon),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadError() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.errorRed.withValues(alpha: 0.04),
      border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.32)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.errorRed),
        const Text(
          'No se pudo consultar el estado de cuenta. No es posible confirmar el saldo.',
          style: TextStyle(color: AppColors.errorRed),
        ),
        TextButton.icon(
          onPressed: widget.onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      ],
    ),
  );

  Widget _familyMovements() {
    final account = widget.account;
    if (account == null || _selectedId != null) {
      return const SizedBox.shrink();
    }
    if (account.creditoUsd <= kToleranciaSaldoUsd &&
        account.enRevisionUsd <= kToleranciaSaldoUsd) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.21),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Movimientos familiares',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.darkNavy,
              ),
            ),
            const SizedBox(height: 11),
            if (account.creditoUsd > kToleranciaSaldoUsd)
              _familyAmount(
                'Saldo a favor',
                account.creditoUsd,
                AppColors.successGreen,
                Icons.savings_outlined,
              ),
            if (account.enRevisionUsd > kToleranciaSaldoUsd) ...[
              const SizedBox(height: 10),
              _familyAmount(
                'Pagos en revisión',
                account.enRevisionUsd,
                AppColors.warningAmber,
                Icons.hourglass_empty_rounded,
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Importes familiares sin asignar a un estudiante individual.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _familyAmount(
    String title,
    double amount,
    Color accent,
    IconData icon,
  ) => Row(
    children: [
      Icon(icon, size: 20, color: accent),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
      Text(
        _usd(amount),
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    ],
  );
}

class _FamilyMark extends StatelessWidget {
  final double size;

  /// Color del fondo sobre el que se dibuja (separa al niño de los adultos).
  final Color background;

  const _FamilyMark({required this.size, required this.background});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Un adulto con dos hijos',
      child: CustomPaint(
        size: Size.square(size),
        painter: _FamilyMarkPainter(background: background),
      ),
    );
  }
}

class _FamilyMarkPainter extends CustomPainter {
  final Color background;
  const _FamilyMarkPainter({required this.background});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final adult = Paint()..color = AppColors.primaryBlue;
    final child = Paint()
      ..color = Color.lerp(AppColors.primaryBlue, Colors.white, 0.38)!;
    final gap = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05;

    void person({
      required double cx,
      required double headY,
      required double headR,
      required double bodyTop,
      required double bodyBottom,
      required double bodyHalfW,
      required Paint paint,
      bool outline = false,
    }) {
      final body = RRect.fromRectAndCorners(
        Rect.fromLTRB(
          (cx - bodyHalfW) * s,
          bodyTop * s,
          (cx + bodyHalfW) * s,
          bodyBottom * s,
        ),
        topLeft: Radius.circular(bodyHalfW * s * 0.95),
        topRight: Radius.circular(bodyHalfW * s * 0.95),
        bottomLeft: Radius.circular(bodyHalfW * s * 0.35),
        bottomRight: Radius.circular(bodyHalfW * s * 0.35),
      );
      final head = Offset(cx * s, headY * s);
      if (outline) {
        canvas.drawRRect(body, gap);
        canvas.drawCircle(head, headR * s, gap);
      }
      canvas.drawRRect(body, paint);
      canvas.drawCircle(head, headR * s, paint);
    }

    // Adulto en el centro, detrás de los hijos.
    person(
      cx: 0.50,
      headY: 0.20,
      headR: 0.125,
      bodyTop: 0.38,
      bodyBottom: 0.95,
      bodyHalfW: 0.18,
      paint: adult,
    );
    // Dos niños más pequeños en primer plano, separados del adulto.
    person(
      cx: 0.23,
      headY: 0.50,
      headR: 0.091,
      bodyTop: 0.64,
      bodyBottom: 0.96,
      bodyHalfW: 0.115,
      paint: child,
      outline: true,
    );
    person(
      cx: 0.77,
      headY: 0.50,
      headR: 0.091,
      bodyTop: 0.64,
      bodyBottom: 0.96,
      bodyHalfW: 0.115,
      paint: child,
      outline: true,
    );
  }

  @override
  bool shouldRepaint(_FamilyMarkPainter old) => old.background != background;
}

// Círculo decorativo en la esquina superior derecha. El color se parametriza
// para respetar el estado de solvencia. Con `scale` > 1 (hover) crece anclado
// a la esquina, sin mover el contenido de la tarjeta.
class _FeatureCornerCurvesPainter extends CustomPainter {
  final Color color;
  final double scale;
  const _FeatureCornerCurvesPainter(this.color, {this.scale = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Radio proporcional a la altura para que encaje en tarjetas bajas.
    final radius = (h * 0.5).clamp(34.0, 75.0).toDouble();

    canvas.save();
    // Escala anclada en la esquina superior derecha.
    canvas.translate(w, 0);
    canvas.scale(scale, scale);
    canvas.translate(-w, 0);
    canvas.drawCircle(
      Offset(w - radius * 0.45, radius * 0.2),
      radius,
      Paint()..color = color.withValues(alpha: 0.10),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FeatureCornerCurvesPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scale != scale;
}

class _AccountStatementStatusFilter extends StatefulWidget {
  const _AccountStatementStatusFilter({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AccountStatementStatusFilter> createState() =>
      _AccountStatementStatusFilterState();
}

class _AccountStatementStatusFilterState
    extends State<_AccountStatementStatusFilter> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final selected = widget.selected;
    final highlighted = selected || _hovered;
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Filtrar cuotas: ${widget.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 155),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 38),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.105)
                : _hovered
                ? color.withValues(alpha: 0.045)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted
                  ? color.withValues(alpha: selected ? 0.74 : 0.55)
                  : AppColors.cardBorder,
              width: 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.075),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              hoverColor: Colors.transparent,
              splashColor: color.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 15, color: color),
                    const SizedBox(width: 7),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: highlighted ? color : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
