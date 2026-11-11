import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../academics/presentation/widgets/academic_widgets.dart';
import '../../data/student_repository.dart';
import '../../data/supabase_student_repository.dart';
import '../../domain/student_account.dart';

/// Directorio académico y estado de cuenta por estudiante.
/// Todas las consultas se limitan al colegio del administrador. Las políticas
/// RLS de Supabase deben permitir únicamente la información autorizada.
class AdminStudentsSection extends StatefulWidget {
  const AdminStudentsSection({super.key, required this.colegioId});

  final String colegioId;

  @override
  State<AdminStudentsSection> createState() => _AdminStudentsSectionState();
}

class _AdminStudentsSectionState extends State<AdminStudentsSection> {
  static const _navy = AppColors.darkNavy;
  static const _blue = AppColors.primaryBlue;
  static const _muted = AppColors.textMuted;
  static const _border = AppColors.cardBorder;
  static const _green = Color(0xFF087F5B);
  static const _orange = Color(0xFFAF6500);
  static const _red = Color(0xFFCA3545);

  final StudentRepository _repository = SupabaseStudentRepository();
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _refreshing = false;
  bool _balancesAvailable = false;
  bool _applicationsAvailable = true;
  String? _error;
  String _search = '';
  String _grade = 'todos';
  String _section = 'todos';
  String _status = 'todos';
  int _page = 0;
  int _request = 0;
  static const int _perPage = 12;
  List<StudentAccount> _students = [];
  Map<String, Map<String, dynamic>> _paymentsById = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearch);
    _fetch();
  }

  @override
  void didUpdateWidget(covariant AdminStudentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.colegioId != widget.colegioId) _fetch();
  }

  @override
  void dispose() {
    _request++;
    _searchController.removeListener(_onSearch);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    setState(() {
      _search = _searchController.text.trim().toLowerCase();
      _page = 0;
    });
  }

  Future<void> _fetch() async {
    final request = ++_request;
    setState(() {
      _loading = _students.isEmpty;
      _refreshing = true;
      _error = null;
    });
    try {
      final snapshot = await _repository.fetchDirectory(
        colegioId: widget.colegioId,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _students = snapshot.students;
        _paymentsById = snapshot.paymentsById;
        _balancesAvailable = snapshot.balancesAvailable;
        _applicationsAvailable = snapshot.applicationsAvailable;
        _loading = false;
        _refreshing = false;
        _page = 0;
      });
    } catch (e) {
      debugPrint('Error cargando estudiantes y cuotas: $e');
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error =
            'No se pudo cargar el directorio o los datos de cuotas. Verifica la conexión y los permisos del colegio.';
      });
    }
  }

  List<String> get _grades =>
      _students.map((s) => s.grade).toSet().toList()..sort(compareSchoolGrade);
  List<String> get _sections =>
      _students
          .where((s) => _grade == 'todos' || s.grade == _grade)
          .map((s) => s.section)
          .toSet()
          .toList()
        ..sort(compareSchoolText);

  List<StudentAccount> get _visible {
    final filtered = _students.where((s) {
      if (_grade != 'todos' && s.grade != _grade) return false;
      if (_section != 'todos' && s.section != _section) return false;
      if (_status != 'todos' && s.status(_balancesAvailable) != _status) {
        return false;
      }
      if (_search.isEmpty) return true;
      return [
        s.name,
        s.grade,
        s.section,
        s.identification,
        studentText(s.data, [
          'codigo_escolar',
          'matricula',
          'codigo_estudiante',
        ]),
        ...s.representatives.map(
          (r) =>
              '${studentText(r, ['nombres'])} ${studentText(r, ['apellidos'])}',
        ),
      ].any((v) => v.toLowerCase().contains(_search));
    }).toList();
    // Orden estable por grado (1 a 6), sección y nombre, antes de paginar.
    filtered.sort(
      (a, b) => compareSchoolStudent(
        gradeA: a.grade,
        sectionA: a.section,
        nameA: a.name,
        idA: a.id,
        gradeB: b.grade,
        sectionB: b.section,
        nameB: b.name,
        idB: b.id,
      ),
    );
    return filtered;
  }

  String _cash(double amount) {
    final parts = amount.abs().toStringAsFixed(2).split('.');
    final digits = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => '.',
    );
    return '${amount < 0 ? '-' : ''}\$$digits,${parts[1]}';
  }

  Color _statusColor(String status) {
    if (status == 'solvente' || status == 'Pagada') return _green;
    if (status == 'moroso' || status == 'Vencida') return _red;
    if (status == 'pendiente' || status == 'Pendiente') return _orange;
    return _muted;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'solvente':
        return 'Solvente';
      case 'moroso':
        return 'Moroso';
      case 'pendiente':
        return 'Pendiente';
      case 'sin_cuotas':
        return 'Sin cuotas';
      default:
        return 'Sin información';
    }
  }

  Widget _statusBadge(String code) {
    final color = _statusColor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _statusLabel(code),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  BoxDecoration _card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    border: Border.all(color: _border),
  );

  Widget _statCard(String label, String value, IconData icon, Color accent) =>
      SchoolCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _picker({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChange,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
    items: items,
    onChanged: onChange,
  );

  Widget _filters() => SchoolCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SchoolHeading(
          title: 'Buscar y filtrar',
          icon: Icons.manage_search_rounded,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < 700;
            final search = TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar estudiante, cédula o representante',
                prefixIcon: const Icon(Icons.search_rounded, color: _blue),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _searchController.clear,
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF4F7FD),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: _blue, width: 1.8),
                ),
              ),
            );
            final grade = _picker(
              label: 'Grado',
              value: _grade,
              items: [
                const DropdownMenuItem(
                  value: 'todos',
                  child: Text('Todos los grados'),
                ),
                for (final v in _grades)
                  DropdownMenuItem(
                    value: v,
                    child: Text(v, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChange: (v) => setState(() {
                _grade = v ?? 'todos';
                _section = 'todos';
                _page = 0;
              }),
            );
            final section = _picker(
              label: 'Sección',
              value: _section,
              items: [
                const DropdownMenuItem(
                  value: 'todos',
                  child: Text('Todas las secciones'),
                ),
                for (final v in _sections)
                  DropdownMenuItem(
                    value: v,
                    child: Text(v, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChange: (v) => setState(() {
                _section = v ?? 'todos';
                _page = 0;
              }),
            );
            final status = _picker(
              label: 'Estado',
              value: _status,
              items: const [
                DropdownMenuItem(value: 'todos', child: Text('Todos')),
                DropdownMenuItem(value: 'solvente', child: Text('Solventes')),
                DropdownMenuItem(value: 'pendiente', child: Text('Pendientes')),
                DropdownMenuItem(value: 'moroso', child: Text('Morosos')),
                DropdownMenuItem(
                  value: 'sin_cuotas',
                  child: Text('Sin cuotas'),
                ),
                DropdownMenuItem(
                  value: 'sin_datos',
                  child: Text('Sin información'),
                ),
              ],
              onChange: (v) => setState(() {
                _status = v ?? 'todos';
                _page = 0;
              }),
            );
            if (box.maxWidth < 400 ||
                MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 14),
                  grade,
                  const SizedBox(height: 14),
                  section,
                  const SizedBox(height: 14),
                  status,
                ],
              );
            }
            if (narrow) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: grade),
                      const SizedBox(width: 10),
                      Expanded(child: section),
                    ],
                  ),
                  const SizedBox(height: 12),
                  status,
                ],
              );
            }
            return Column(
              children: [
                search,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: grade),
                    const SizedBox(width: 12),
                    Expanded(child: section),
                    const SizedBox(width: 12),
                    Expanded(child: status),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final stats = {
      for (final k in [
        'solvente',
        'pendiente',
        'moroso',
        'sin_cuotas',
        'sin_datos',
      ])
        k: _students.where((s) => s.status(_balancesAvailable) == k).length,
    };
    final visible = _visible;
    final pages = (visible.length / _perPage).ceil();
    final activePage = pages == 0 ? 0 : _page.clamp(0, pages - 1).toInt();
    final current = visible.skip(activePage * _perPage).take(_perPage).toList();

    return LayoutBuilder(
      builder: (context, layout) {
        final wideTable =
            layout.maxWidth >= 1000 &&
            MediaQuery.textScalerOf(context).scale(14) <= 18;
        return RefreshIndicator(
          color: _blue,
          onRefresh: _fetch,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              layout.maxWidth < 640 ? 18 : 36,
              24,
              layout.maxWidth < 640 ? 18 : 36,
              48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, box) {
                        const heading = SchoolHeading(
                          title: 'Estudiantes',
                          icon: Icons.people,
                          primary: true,
                          subtitle:
                              'Directorio académico y estado de cuenta por estudiante.',
                        );
                        final action = OutlinedButton.icon(
                          onPressed: _refreshing ? null : _fetch,
                          icon: _refreshing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            _refreshing ? 'Actualizando...' : 'Actualizar',
                          ),
                        );
                        if (box.maxWidth < 650 ||
                            MediaQuery.textScalerOf(context).scale(14) > 20) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              heading,
                              const SizedBox(height: 14),
                              action,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            const Expanded(child: heading),
                            const SizedBox(width: 18),
                            action,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_error!, style: const TextStyle(color: _red)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _fetch,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_loading) ...[
                      const SizedBox(height: 100),
                      const Center(
                        child: CircularProgressIndicator(color: _blue),
                      ),
                    ] else ...[
                      LayoutBuilder(
                        builder: (context, box) {
                          final w = box.maxWidth;
                          final columns = w < 540 ? 1 : (w < 850 ? 2 : 4);
                          final width = (w - (columns - 1) * 12) / columns;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: width,
                                child: _statCard(
                                  'Estudiantes',
                                  '${_students.length}',
                                  Icons.people_outline,
                                  _blue,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _statCard(
                                  'Solventes',
                                  '${stats['solvente']}',
                                  Icons.verified_outlined,
                                  _green,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _statCard(
                                  'Pendientes',
                                  '${stats['pendiente']}',
                                  Icons.schedule_rounded,
                                  _orange,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _statCard(
                                  'Morosos',
                                  '${stats['moroso']}',
                                  Icons.warning_amber_rounded,
                                  _red,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      if (!_balancesAvailable || stats['sin_datos']! > 0) ...[
                        const SizedBox(height: 12),
                        _warning(
                          'Algunos saldos no pudieron verificarse. Los estudiantes afectados aparecen como «Sin información», no como solventes.',
                        ),
                      ],
                      const SizedBox(height: 18),
                      _filters(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: SchoolHeading(
                              title:
                                  '${visible.length} de ${_students.length} estudiantes',
                              icon: Icons.format_list_bulleted_rounded,
                            ),
                          ),
                          if (_grade != 'todos' ||
                              _section != 'todos' ||
                              _status != 'todos' ||
                              _search.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _grade = 'todos';
                                  _section = 'todos';
                                  _status = 'todos';
                                  _page = 0;
                                });
                              },
                              child: const Text('Limpiar filtros'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (current.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 50,
                            horizontal: 20,
                          ),
                          decoration: _card(),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.school_outlined,
                                color: _muted,
                                size: 40,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _students.isEmpty
                                    ? 'No hay estudiantes registrados.'
                                    : 'No se encontraron estudiantes con esos filtros.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _muted),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        if (wideTable) _headerTable(),
                        for (final student in current)
                          _studentCard(student, wide: wideTable),
                      ],
                      if (pages > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Página anterior',
                                onPressed: activePage > 0
                                    ? () =>
                                          setState(() => _page = activePage - 1)
                                    : null,
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                              Text(
                                'Página ${activePage + 1} de $pages',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Página siguiente',
                                onPressed: activePage + 1 < pages
                                    ? () =>
                                          setState(() => _page = activePage + 1)
                                    : null,
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _warning(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF9ED),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF1DBAA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 19, color: _orange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, color: _navy)),
        ),
      ],
    ),
  );

  Widget _headerTable() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 17, vertical: 10),
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            'ESTUDIANTE',
            style: TextStyle(
              color: _muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'GRADO / SECCIÓN',
            style: TextStyle(
              color: _muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'SALDO PENDIENTE',
            style: TextStyle(
              color: _muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'ESTADO',
            style: TextStyle(
              color: _muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: 146),
      ],
    ),
  );

  Widget _studentCard(StudentAccount s, {required bool wide}) {
    final status = s.status(_balancesAvailable);
    final student = Row(
      children: [
        CircleAvatar(
          backgroundColor: const Color(0xFFEBF2FF),
          child: Text(
            s.name.isEmpty ? '?' : s.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w700, color: _blue),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _navy,
                ),
              ),
              Text(
                s.identification.isEmpty
                    ? 'Documento no registrado'
                    : 'C.I./Código: ${s.identification}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
    final debt = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          status == 'sin_datos' ? 'No disponible' : _cash(s.outstanding),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _navy,
          ),
        ),
        if (status == 'moroso')
          Text(
            '${s.overdueCount} vencida(s) · ${s.maxOverdueDays} días máx.',
            style: const TextStyle(fontSize: 10, color: _red),
          ),
        if (status == 'pendiente')
          const Text(
            'Cuotas con saldo vigente',
            style: TextStyle(fontSize: 10, color: _orange),
          ),
      ],
    );
    final action = SizedBox(
      width: 146,
      child: OutlinedButton.icon(
        onPressed: () => _openStudent(s),
        icon: const Icon(Icons.visibility_outlined, size: 16),
        label: const Text(
          'Ver detalles',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(146, 40),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          foregroundColor: _blue,
          side: const BorderSide(color: _border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
    return SchoolCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 4, child: student),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${s.grade} · ${s.section}',
                    style: const TextStyle(color: _navy, fontSize: 12),
                  ),
                ),
                Expanded(flex: 2, child: debt),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _statusBadge(status),
                  ),
                ),
                action,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                student,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _statusBadge(status),
                    Text(
                      '${s.grade} · Sección ${s.section}',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, box) {
                    if (box.maxWidth < 380 ||
                        MediaQuery.textScalerOf(context).scale(14) > 18) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [debt, const SizedBox(height: 14), action],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: debt),
                        const SizedBox(width: 12),
                        action,
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }

  void _openStudent(StudentAccount student) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _StudentDetailsDialog(
        student: student,
        balancesAvailable: _balancesAvailable,
        applicationsAvailable: _applicationsAvailable,
        paymentById: _paymentsById,
      ),
    );
  }
}

class _StudentDetailsDialog extends StatelessWidget {
  const _StudentDetailsDialog({
    required this.student,
    required this.balancesAvailable,
    required this.applicationsAvailable,
    required this.paymentById,
  });

  final StudentAccount student;
  final bool balancesAvailable;
  final bool applicationsAvailable;
  final Map<String, Map<String, dynamic>> paymentById;

  static const _navy = AppColors.darkNavy;
  static const _muted = AppColors.textMuted;
  static const _blue = AppColors.primaryBlue;
  static const _border = AppColors.cardBorder;
  static const _green = Color(0xFF087F5B);
  static const _orange = Color(0xFFAF6500);
  static const _red = Color(0xFFCA3545);
  static const _surface = Color(0xFFF5F8FE);

  String _money(double? number) {
    if (number == null) return 'No disponible';
    final parts = number.abs().toStringAsFixed(2).split('.');
    final integer = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => '.',
    );
    return '${number < 0 ? '-' : ''}\$$integer,${parts[1]}';
  }

  String _date(DateTime? value) => value == null
      ? 'No registrada'
      : '${value.day.toString().padLeft(2, '0')}/'
            '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _prettyKey(String key) {
    const labels = <String, String>{
      'creado_at': 'Fecha de registro',
      'created_at': 'Fecha de registro',
      'actualizado_at': 'Última actualización',
      'updated_at': 'Última actualización',
      'fecha_inscripcion': 'Fecha de inscripción',
      'fecha_ingreso': 'Fecha de ingreso',
      'telefono': 'Teléfono',
      'telefono_contacto': 'Teléfono de contacto',
      'tipo_documento': 'Tipo de documento',
      'codigo_escolar': 'Código escolar',
      'codigo_estudiante': 'Código de estudiante',
      'matricula': 'Matrícula',
      'genero': 'Género',
      'sexo': 'Sexo',
      'direccion': 'Dirección',
      'nacionalidad': 'Nacionalidad',
      'observaciones': 'Observaciones',
    };
    if (labels.containsKey(key)) return labels[key]!;
    final readable = key.replaceAll('_', ' ').trim();
    return readable.isEmpty
        ? key
        : '${readable[0].toUpperCase()}${readable.substring(1)}';
  }

  String _readableValue(String key, dynamic value) {
    if (key == 'activo' && value is bool) return value ? 'Activo' : 'Inactivo';
    if (value is bool) return value ? 'Sí' : 'No';
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return 'No registrado';
    if (key == 'activo') {
      if (raw.toLowerCase() == 'true') return 'Activo';
      if (raw.toLowerCase() == 'false') return 'Inactivo';
    }
    if (key.contains('fecha') || key.endsWith('_at')) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return _date(parsed.toLocal());
    }
    return raw;
  }

  Widget _panel({
    required IconData icon,
    required String title,
    required Widget content,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _blue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11)),
          ],
          const SizedBox(height: 13),
          content,
        ],
      ),
    );
  }

  Widget _detailField(String label, String value, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: _muted),
          const SizedBox(width: 7),
        ],
        SizedBox(
          width: icon == null ? 116 : 107,
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.5),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: SelectableText(
            value.isEmpty ? 'No registrado' : value,
            style: const TextStyle(
              color: _navy,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _metric(
    String label,
    String value,
    IconData icon,
    Color accent, {
    String? extra,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .055),
        border: Border.all(color: accent.withValues(alpha: .15)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              color: accent,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
          if (extra != null) ...[
            const SizedBox(height: 4),
            Text(extra, style: const TextStyle(fontSize: 10.5, color: _muted)),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'solvente':
        return _green;
      case 'pendiente':
        return _orange;
      case 'moroso':
        return _red;
      default:
        return _muted;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'solvente':
        return 'Solvente';
      case 'pendiente':
        return 'Pago pendiente';
      case 'moroso':
        return 'Con cuotas vencidas';
      case 'sin_cuotas':
        return 'Sin cuotas emitidas';
      default:
        return 'Saldo no verificado';
    }
  }

  String _statusExplanation(String status) {
    switch (status) {
      case 'solvente':
        return 'Todas las cuotas emitidas están saldadas.';
      case 'pendiente':
        return 'Tiene cuotas pendientes que aún no han vencido.';
      case 'moroso':
        return 'Tiene saldos pendientes con fecha de vencimiento superada.';
      case 'sin_cuotas':
        return 'Aún no se han emitido cuotas para este estudiante. No equivale a solvencia certificada.';
      default:
        return 'No se ha podido verificar el estado financiero completo.';
    }
  }

  Widget _statusPill(String text, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _academicCard() {
    final data = student.data;
    final first = studentText(data, ['nombres', 'nombre']);
    final last = studentText(data, ['apellidos', 'apellido']);
    final birthday = studentText(data, ['fecha_nacimiento', 'nacimiento']);
    final activeValue = data['activo'];
    final active = activeValue == null
        ? 'No registrado'
        : _readableValue('activo', activeValue);
    return _panel(
      icon: Icons.school_outlined,
      title: 'Información académica',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (first.isEmpty && last.isEmpty)
            _detailField('Nombre', student.name)
          else ...[
            _detailField('Nombres', first),
            _detailField('Apellidos', last),
          ],
          _detailField('Documento', student.identification),
          _detailField(
            'Nacimiento',
            birthday.isEmpty
                ? 'No registrado'
                : _readableValue('fecha_nacimiento', birthday),
          ),
          _detailField('Grado', student.grade),
          _detailField('Sección', student.section),
          _detailField(
            'Matrícula',
            studentText(data, [
              'matricula',
              'codigo_escolar',
              'codigo_estudiante',
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                const SizedBox(
                  width: 116,
                  child: Text(
                    'Estado',
                    style: TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ),
                _statusPill(
                  active,
                  active == 'Activo'
                      ? _green
                      : (active == 'Inactivo' ? _red : _muted),
                  icon: active == 'Activo' ? Icons.check_circle_outline : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _representativesCard() => _panel(
    icon: Icons.groups_outlined,
    title: 'Representantes vinculados',
    subtitle: '${student.representatives.length} representante(s) asociado(s)',
    content: student.representatives.isEmpty
        ? _emptyInline(
            Icons.person_off_outlined,
            'Sin representantes visibles',
            'No hay vínculos disponibles o tu cuenta no tiene permiso de consulta.',
          )
        : Column(
            children: [
              for (var i = 0; i < student.representatives.length; i++) ...[
                if (i > 0) const Divider(height: 25, color: _border),
                _representativeItem(student.representatives[i]),
              ],
            ],
          ),
  );

  Widget _representativeItem(Map<String, dynamic> rep) {
    final name =
        '${studentText(rep, ['nombres', 'nombre'])} ${studentText(rep, ['apellidos', 'apellido'])}'
            .trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFFEAF2FF),
              child: const Icon(Icons.person_outline, size: 18, color: _blue),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                name.isEmpty ? 'Representante sin nombre' : name,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _detailField('Cédula', studentText(rep, ['cedula', 'ci'])),
        _detailField(
          'Teléfono',
          studentText(rep, ['telefono_whatsapp', 'telefono']),
        ),
        _detailField('Correo', studentText(rep, ['email', 'correo'])),
      ],
    );
  }

  Widget _emptyInline(IconData icon, String title, String description) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 19),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 23, color: _muted),
            const SizedBox(height: 7),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: _navy,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: _muted, height: 1.4),
            ),
          ],
        ),
      );

  // Conserva los campos adicionales reales, pero no vuelve a mostrar los
  // ya presentes en la ficha ni expone UUID internos como datos personales.
  List<MapEntry<String, String>> _extraFields() {
    const shown = <String>{
      'id',
      'colegio_id',
      'nombres',
      'nombre',
      'apellidos',
      'apellido',
      'nombre_completo',
      'nombre_apellido',
      'cedula',
      'cedula_estudiante',
      'documento_identidad',
      'numero_documento',
      'numero_cedula',
      'nro_cedula',
      'ci',
      'codigo',
      'codigo_estudiante',
      'codigo_escolar',
      'matricula',
      'fecha_nacimiento',
      'nacimiento',
      'activo',
      'grado',
      'nivel_grado',
      'seccion',
      'sección',
      'seccion_actual',
      'letra_seccion',
      'grado_seccion',
    };
    final result = <MapEntry<String, String>>[];
    for (final entry in student.data.entries) {
      if (shown.contains(entry.key) || entry.value == null) continue;
      final raw = entry.value.toString().trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') continue;
      // Las claves foráneas solo se usan en las consultas, no son información
      // comprensible para el usuario del panel.
      if (entry.key.endsWith('_id')) continue;
      result.add(
        MapEntry(_prettyKey(entry.key), _readableValue(entry.key, entry.value)),
      );
    }
    result.sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  Widget _extraCard(List<MapEntry<String, String>> fields) => _panel(
    icon: Icons.badge_outlined,
    title: 'Información adicional',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in fields) _detailField(entry.key, entry.value),
      ],
    ),
  );

  Widget _quotaSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.receipt_long_outlined, color: _blue, size: 19),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Detalle de cuotas',
              style: TextStyle(
                color: _navy,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _statusPill('${student.quotas.length} emitidas', _blue),
        ],
      ),
      const SizedBox(height: 12),
      if (student.quotas.isEmpty)
        _emptyInline(
          Icons.receipt_long_outlined,
          'Aún no hay cuotas emitidas',
          'Cuando se genere facturación para este estudiante, '
              'aparecerá aquí el detalle de cada concepto y su saldo.',
        )
      else
        for (final quota in student.quotas) _quotaCard(quota),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    final screenWidth = window.width;
    final screenHeight = window.height;
    final status = student.status(balancesAvailable);
    final complete = balancesAvailable && !student.hasIncompleteBalance;
    final color = _statusColor(status);
    final extra = _extraFields();

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenWidth < 640 ? 12 : 24,
        vertical: screenHeight < 650 ? 12 : 22,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 950,
          maxHeight: screenHeight - (screenHeight < 650 ? 24 : 44),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                screenWidth < 600 ? 16 : 23,
                17,
                13,
                16,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF3FF),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.school_outlined,
                      color: _blue,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${student.grade} · Sección ${student.section}'
                          '${student.identification.isEmpty ? '' : ' · ${student.identification}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar detalles',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  screenWidth < 600 ? 16 : 23,
                  19,
                  screenWidth < 600 ? 16 : 23,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _statusPill(
                          _statusText(status),
                          color,
                          icon: status == 'solvente'
                              ? Icons.check_circle_outline
                              : status == 'moroso'
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline_rounded,
                        ),
                        if (status == 'moroso')
                          _statusPill(
                            '${student.maxOverdueDays} días de mora máxima',
                            _red,
                            icon: Icons.schedule_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusExplanation(status),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, box) {
                        final columns = box.maxWidth < 430
                            ? 1
                            : (box.maxWidth < 680 ? 2 : 3);
                        final cardW =
                            (box.maxWidth - 10 * (columns - 1)) / columns;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: cardW,
                              child: _metric(
                                'Total facturado',
                                complete ? _money(student.billed) : '—',
                                Icons.receipt_outlined,
                                _navy,
                                extra:
                                    '${student.quotas.length} cuota(s) emitida(s)',
                              ),
                            ),
                            SizedBox(
                              width: cardW,
                              child: _metric(
                                'Saldo pendiente',
                                complete ? _money(student.outstanding) : '—',
                                Icons.account_balance_wallet_outlined,
                                _orange,
                                extra:
                                    '${student.pendingCount} cuota(s) con saldo',
                              ),
                            ),
                            SizedBox(
                              width: cardW,
                              child: _metric(
                                'Saldo vencido',
                                complete ? _money(student.overdueBalance) : '—',
                                Icons.warning_amber_outlined,
                                _red,
                                extra:
                                    '${student.overdueCount} cuota(s) vencida(s)',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (!complete) ...[
                      const SizedBox(height: 11),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: _orange, size: 17),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No se pudieron verificar todos los saldos. '
                                'El estado de solvencia no debe darse por confirmado.',
                                style: TextStyle(fontSize: 11, color: _navy),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 17),
                    LayoutBuilder(
                      builder: (context, box) {
                        if (box.maxWidth < 700) {
                          return Column(
                            children: [
                              _academicCard(),
                              const SizedBox(height: 12),
                              _representativesCard(),
                              if (extra.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _extraCard(extra),
                              ],
                            ],
                          );
                        }
                        final half = (box.maxWidth - 12) / 2;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: half,
                              child: Column(
                                children: [
                                  _academicCard(),
                                  if (extra.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _extraCard(extra),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: half,
                              child: _representativesCard(),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    _quotaSection(),
                    if (student.quotas.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Los días de mora se cuentan desde el día siguiente '
                        'al vencimiento. El saldo se obtiene de la vista contable '
                        'del colegio.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: _muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: _border),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth < 600 ? 15 : 22,
                vertical: 10,
              ),
              child: Row(
                children: [
                  if (screenWidth >= 600)
                    const Expanded(
                      child: Text(
                        'Información del colegio',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ),
                  if (screenWidth < 600) const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Cerrar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _navy,
                      minimumSize: const Size(104, 39),
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      side: const BorderSide(color: _border),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quotaCard(StudentQuota quota) {
    final status = quota.status;
    final color = status == 'Pagada'
        ? _green
        : status == 'Vencida'
        ? _red
        : status == 'Pendiente'
        ? _orange
        : _muted;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_month_outlined,
                  size: 19,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quota.concept,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${quota.period} · Vence ${_date(quota.due)}',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(
                status == 'Vencida'
                    ? '${quota.overdueDays} días de mora'
                    : status,
                color,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth < 320
                  ? 1
                  : (box.maxWidth < 600 ? 2 : 3);
              final cardW = (box.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 11,
                children: [
                  SizedBox(
                    width: cardW,
                    child: _smallAmount(
                      'Monto original',
                      _money(quota.original),
                      _navy,
                    ),
                  ),
                  SizedBox(
                    width: cardW,
                    child: _smallAmount(
                      'Abonado / ajustado',
                      _money(quota.covered),
                      _green,
                    ),
                  ),
                  SizedBox(
                    width: cardW,
                    child: _smallAmount(
                      'Saldo restante',
                      _money(quota.balance),
                      color,
                    ),
                  ),
                ],
              );
            },
          ),
          if (applicationsAvailable && quota.applications.isNotEmpty) ...[
            const Divider(height: 24, color: _border),
            const Text(
              'Pagos aplicados',
              style: TextStyle(
                color: _navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final app in quota.applications) _applicationRow(app),
          ],
          if (!applicationsAvailable)
            const Padding(
              padding: EdgeInsets.only(top: 11),
              child: Text(
                'No se pudo consultar el desglose de pagos aplicados.',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _smallAmount(String label, String value, Color accent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10.5, color: _muted)),
      const SizedBox(height: 5),
      Text(
        value,
        style: TextStyle(
          color: accent,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );

  Widget _applicationRow(Map<String, dynamic> app) {
    final payment = paymentById[studentText(app, ['pago_id'])];
    final reference = payment == null
        ? ''
        : studentText(payment, ['referencia']);
    final date = payment == null ? '' : studentText(payment, ['fecha_pago']);
    final amount =
        studentNumber(app['monto_usd_aplicado']) ??
        studentNumber(app['monto_aplicado_usd']) ??
        studentNumber(app['monto_usd']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 15, color: _green),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${reference.isEmpty ? 'Referencia no disponible' : reference}'
              '${date.isEmpty ? '' : ' · $date'}',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount == null ? 'Sin importe' : _money(amount),
            style: const TextStyle(
              color: _navy,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
