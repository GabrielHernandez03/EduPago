import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../students/presentation/widgets/admin_students_section.dart';
import '../../data/academic_repository.dart';
import 'academic_widgets.dart';

class AdminAcademicSection extends StatefulWidget {
  const AdminAcademicSection({super.key, required this.colegioId});
  final String colegioId;
  @override
  State<AdminAcademicSection> createState() => _AdminAcademicSectionState();
}

class _AdminAcademicSectionState extends State<AdminAcademicSection> {
  bool _grades = false;
  final _gradeKey = GlobalKey<_AdminGradesState>();
  Future<void> _tab(bool grades) async {
    if (_grades == grades) return;
    if (_grades &&
        !await (_gradeKey.currentState?.allowDiscard() ?? Future.value(true)))
      return;
    if (mounted) setState(() => _grades = grades);
  }

  @override
  Widget build(BuildContext context) => SchoolPageTheme(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 510),
              child: SchoolTabs(grades: _grades, onChanged: _tab),
            ),
          ),
        ),
        Expanded(
          child: _grades
              ? _AdminGrades(key: _gradeKey, school: widget.colegioId)
              : AdminStudentsSection(colegioId: widget.colegioId),
        ),
      ],
    ),
  );
}

class _AdminGrades extends StatefulWidget {
  const _AdminGrades({super.key, required this.school});
  final String school;
  @override
  State<_AdminGrades> createState() => _AdminGradesState();
}

class _AdminGradesState extends State<_AdminGrades> {
  final _repo = AcademicRepository();
  final _form = GlobalKey<FormState>();
  final _teacher = TextEditingController();
  final Map<String, TextEditingController> _notes = {};
  List<AcademicRow> _years = [], _students = [], _enrolled = [], _subjects = [];
  String? _year, _grade, _section, _subject;
  String _term = '1';
  String? _error;
  bool _busy = true, _dirty = false;
  int _generation = 0;

  bool get _editable =>
      _years.any((a) => a['id'] == _year && a['activo'] == true);
  List<AcademicRow> get _roster =>
      _enrolled
          .where((s) => s['grado'] == _grade && s['seccion'] == _section)
          .toList()
        ..sort((a, b) {
          final order = compareSchoolText(
            a['nombre'].toString(),
            b['nombre'].toString(),
          );
          return order != 0
              ? order
              : a['id'].toString().compareTo(b['id'].toString());
        });
  List<AcademicRow> get _gradeSubjects =>
      _subjects.where((s) => s['grado'] == _grade).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _teacher.dispose();
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> allowDiscard() async {
    if (_busy) return false;
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const SchoolHeading(
              title: 'Cambios sin guardar',
              icon: Icons.edit_note_rounded,
            ),
            content: const Text(
              'Guarda las calificaciones antes de cambiar de vista, o descarta los cambios.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Seguir editando'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Descartar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var data = await _repo.context(_year);
      final years = academicRows(data['anios']);
      final selectedYear =
          _year ?? (years.isEmpty ? null : years.first['id'].toString());
      if (selectedYear != _year && selectedYear != null)
        data = await _repo.context(selectedYear);
      if (!mounted || generation != _generation) return;
      _years = years;
      _year = selectedYear;
      _students = academicRows(data['estudiantes']);
      _enrolled = academicRows(data['inscripciones']);
      final enrolledIds = <String>{};
      if (_enrolled.any((s) => !enrolledIds.add(s['id'].toString()))) {
        throw const FormatException(
          'Hay inscripciones duplicadas en este año. Revisa los registros antes de cargar notas.',
        );
      }
      _subjects = academicRows(data['materias']);
      final grades =
          _enrolled.map((s) => s['grado'].toString()).toSet().toList()
            ..sort(compareSchoolGrade);
      if (!grades.contains(_grade)) _grade = grades.firstOrNull;
      _normalizeSelection();
      await _loadNotes(generation);
    } catch (e) {
      if (mounted && generation == _generation)
        setState(() => _error = academicError(e));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _normalizeSelection() {
    final sections =
        _enrolled
            .where((s) => s['grado'] == _grade)
            .map((s) => s['seccion'].toString())
            .toSet()
            .toList()
          ..sort(compareSchoolText);
    if (!sections.contains(_section)) _section = sections.firstOrNull;
    if (!_gradeSubjects.any((s) => s['id'] == _subject)) {
      _subject = _gradeSubjects.firstOrNull?['id']?.toString();
    }
  }

  Future<void> _loadNotes(int generation) async {
    final subject = _gradeSubjects
        .where((s) => s['id'] == _subject)
        .firstOrNull;
    final rows = _year == null || subject == null
        ? <AcademicRow>[]
        : await _repo.grades(
            widget.school,
            _year!,
            subject['nombre'].toString(),
            _term,
          );
    if (!mounted || generation != _generation) return;
    final ids = <String>{};
    if (rows.any((r) => !ids.add(r['estudiante_id'].toString()))) {
      throw const FormatException('Notas duplicadas');
    }
    for (final c in _notes.values) {
      c.dispose();
    }
    _notes.clear();
    for (final s in _roster) {
      final row = rows.where((r) => r['estudiante_id'] == s['id']).firstOrNull;
      _notes[s['id'].toString()] = TextEditingController(
        text: row?['nota']?.toString() ?? '',
      );
    }
    final rosterIds = _roster.map((s) => s['id']).toSet();
    final teachers = rows
        .where((r) => rosterIds.contains(r['estudiante_id']))
        .map((r) => r['docente']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    _teacher.text = teachers.length == 1 ? teachers.first : '';
    _dirty = false;
  }

  Future<void> _change(VoidCallback update, {bool reload = false}) async {
    if (!await allowDiscard() || !mounted) return;
    setState(() {
      update();
      _normalizeSelection();
      _dirty = false;
    });
    if (reload) {
      await _load();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _loadNotes(generation);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? 'Hay notas duplicadas. Revisa los datos antes de editar.'
              : academicError(e),
        );
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final rows = <AcademicRow>[];
    for (final s in _roster) {
      final raw = _notes[s['id']]!.text.trim().replaceAll(',', '.');
      if (raw.isNotEmpty)
        rows.add({'estudiante_id': s['id'], 'nota': double.parse(raw)});
    }
    if (rows.isEmpty) {
      _message('Ingresa al menos una nota.');
      return;
    }
    setState(() => _busy = true);
    try {
      final count = await _repo.save(
        _year!,
        _subject!,
        _term,
        _teacher.text.trim(),
        rows,
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      _message(
        '$count calificaciones guardadas. Ya están disponibles para los representantes.',
      );
      await _load();
    } catch (e) {
      _message(academicError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish(AcademicRow student) async {
    if (_dirty) {
      _message('Guarda las calificaciones antes de publicar.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const SchoolHeading(
          title: 'Publicar boletín',
          icon: Icons.publish_outlined,
        ),
        content: Text(
          'Se publicarán todas las materias del lapso $_term de ${student['nombre']}. '
          'Si ya hay un boletín, se reemplazará por una nueva versión. Las notas posteriores no cambiarán este PDF hasta volver a publicar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publicar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.publish(student['id'].toString(), _year!, _term);
      _message('Boletín publicado.');
    } catch (e) {
      _message(academicError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setup(bool enrollment) async {
    if (!await allowDiscard() || !mounted) return;
    final grade = TextEditingController(text: _grade ?? '');
    final value = TextEditingController();
    final key = GlobalKey<FormState>();
    String? student;
    String? dialogError;
    bool saving = false;
    final registered = _enrolled.map((e) => e['id']).toSet();
    final candidates = _students
        .where((s) => !registered.contains(s['id']))
        .toList();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: SchoolHeading(
              title: enrollment
                  ? 'Vincular estudiante al año'
                  : 'Agregar materia al grado',
              icon: enrollment
                  ? Icons.person_add_alt
                  : Icons.menu_book_outlined,
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: key,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (enrollment)
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Estudiante',
                          ),
                          items: candidates
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s['id'].toString(),
                                  child: Text(
                                    s['nombre'].toString(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: saving ? null : (v) => student = v,
                          validator: (v) => v == null
                              ? 'Selecciona un estudiante sin inscripción en este año.'
                              : null,
                        ),
                      TextFormField(
                        controller: grade,
                        enabled: !saving,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Grado',
                          hintText: 'Ej. 3er grado',
                        ),
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Indica el grado.' : null,
                      ),
                      TextFormField(
                        controller: value,
                        enabled: !saving,
                        maxLength: enrollment ? 30 : 100,
                        decoration: InputDecoration(
                          labelText: enrollment
                              ? 'Sección (opcional)'
                              : 'Nombre de la materia',
                        ),
                        validator: (v) => !enrollment && v!.trim().isEmpty
                            ? 'Indica la materia.'
                            : null,
                      ),
                      if (enrollment)
                        const AcademicMessage(
                          'Esta inscripción conserva el grado y la sección para el año seleccionado.',
                        ),
                      if (dialogError != null)
                        AcademicMessage(dialogError!, error: true),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!key.currentState!.validate()) return;
                        update(() {
                          saving = true;
                          dialogError = null;
                        });
                        try {
                          if (enrollment) {
                            await _repo.enroll(
                              _year!,
                              student!,
                              grade.text.trim(),
                              value.text.trim(),
                            );
                          } else {
                            await _repo.addSubject(
                              _year!,
                              grade.text.trim(),
                              value.text.trim(),
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          if (ctx.mounted)
                            update(() {
                              saving = false;
                              dialogError = academicError(e);
                            });
                        }
                      },
                child: Text(saving ? 'Guardando…' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
    // El diálogo ya no utiliza los controladores después de su animación.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    grade.dispose();
    value.dispose();
    if (saved == true && mounted) {
      setState(() => _dirty = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final grades = _enrolled.map((s) => s['grado'].toString()).toSet().toList()
      ..sort(compareSchoolGrade);
    final sections =
        _enrolled
            .where((s) => s['grado'] == _grade)
            .map((s) => s['seccion'].toString())
            .toSet()
            .toList()
          ..sort(compareSchoolText);
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SchoolHeading(
                title: 'Calificaciones',
                icon: Icons.fact_check_outlined,
                primary: true,
                subtitle:
                    'Registra las notas por materia. Los representantes podrán consultarlas al guardarlas.',
              ),
              const SizedBox(height: 22),
              AcademicCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SchoolHeading(
                      title: 'Grupo y período',
                      icon: Icons.tune_rounded,
                      subtitle:
                          'Selecciona el año, el grado y la materia que deseas evaluar.',
                    ),
                    const SizedBox(height: 22),
                    SchoolFieldGrid(
                      children: [
                        AcademicSelect(
                          width: double.infinity,
                          label: 'Año escolar',
                          value: _year,
                          items: {
                            for (final a in _years)
                              a['id'].toString():
                                  '${a['nombre']}${a['activo'] == true ? '' : ' (cerrado)'}',
                          },
                          enabled: !_busy,
                          onChanged: (v) => _change(() {
                            _year = v;
                            _grade = null;
                            _section = null;
                            _subject = null;
                          }, reload: true),
                        ),
                        AcademicSelect(
                          width: double.infinity,
                          label: 'Grado',
                          value: _grade,
                          items: {for (final g in grades) g: g},
                          enabled: !_busy,
                          onChanged: (v) => _change(() {
                            _grade = v;
                            _subject = null;
                            _section = null;
                          }),
                        ),
                        AcademicSelect(
                          width: double.infinity,
                          label: 'Sección',
                          value: _section,
                          items: {
                            for (final s in sections)
                              s: s.isEmpty ? 'Sin sección' : s,
                          },
                          enabled: !_busy,
                          onChanged: (v) => _change(() => _section = v),
                        ),
                        AcademicSelect(
                          width: double.infinity,
                          label: 'Lapso',
                          value: _term,
                          items: const {
                            '1': 'Primer lapso',
                            '2': 'Segundo lapso',
                            '3': 'Tercer lapso',
                          },
                          enabled: !_busy,
                          onChanged: (v) => _change(() => _term = v!),
                        ),
                        AcademicSelect(
                          width: double.infinity,
                          label: 'Materia',
                          value: _subject,
                          items: {
                            for (final s in _gradeSubjects)
                              s['id'].toString(): s['nombre'].toString(),
                          },
                          enabled: !_busy,
                          onChanged: (v) => _change(() => _subject = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy || !_editable
                              ? null
                              : () => _setup(false),
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar materia'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || !_editable
                              ? null
                              : () => _setup(true),
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('Vincular al año escolar'),
                        ),
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _change(() {}, reload: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Actualizar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null) AcademicMessage(_error!, error: true),
              if (!_busy && _years.isEmpty)
                const SchoolEmptyState(
                  title: 'Año escolar pendiente',
                  message: 'Configura un año escolar activo para comenzar.',
                  icon: Icons.calendar_month_outlined,
                ),
              if (!_busy && _year != null && _enrolled.isEmpty)
                const SchoolEmptyState(
                  title: 'Prepara tu primer grupo',
                  message:
                      'Vincula los estudiantes al año escolar para empezar a registrar sus notas.',
                  icon: Icons.group_add_outlined,
                ),
              if (!_busy && _grade != null && _gradeSubjects.isEmpty)
                const SchoolEmptyState(
                  title: 'Agrega las materias del grado',
                  message:
                      'Configura las asignaturas del colegio con el botón “Agregar materia”.',
                  icon: Icons.menu_book_outlined,
                ),
              if (_subject != null && _error == null) ...[
                const SizedBox(height: 20),
                AcademicCard(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SchoolHeading(
                          title: 'Registro de notas',
                          icon: Icons.edit_note_rounded,
                          subtitle:
                              '${_roster.length} estudiantes · Lapso $_term · ${_grade ?? ''} ${_section ?? ''}',
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _teacher,
                          enabled: !_busy && _editable,
                          maxLength: 120,
                          decoration: schoolInputDecoration(
                            'Docente de la materia',
                            icon: Icons.person_outline,
                          ),
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Indica el docente.' : null,
                          onChanged: (_) => setState(() => _dirty = true),
                        ),
                        const AcademicMessage(
                          'Notas de 1 a 20 (hasta dos decimales). Los campos vacíos no se guardan ni eliminan notas anteriores.',
                        ),
                        for (final s in _roster)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SchoolCard(
                              padding: const EdgeInsets.all(14),
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final name = Row(
                                    children: [
                                      const Icon(
                                        Icons.person_outline,
                                        size: 20,
                                        color: AppColors.textMuted,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          s['nombre'].toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.darkNavy,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                  final input = SizedBox(
                                    width: 120,
                                    child: TextFormField(
                                      key: ValueKey(
                                        '${s['id']}:$_subject:$_term:$_section',
                                      ),
                                      controller: _notes[s['id']],
                                      enabled: !_busy && _editable,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: schoolInputDecoration(
                                        'Nota / 20',
                                      ),
                                      onChanged: (_) =>
                                          setState(() => _dirty = true),
                                      validator: (v) {
                                        final raw = (v ?? '').trim().replaceAll(
                                          ',',
                                          '.',
                                        );
                                        if (raw.isEmpty) return null;
                                        final n = double.tryParse(raw);
                                        if (n == null ||
                                            !n.isFinite ||
                                            n < 1 ||
                                            n > 20)
                                          return 'Entre 1 y 20';
                                        if (!RegExp(
                                          r'^\d{1,2}(\.\d{1,2})?$',
                                        ).hasMatch(raw))
                                          return 'Máx. 2 decimales';
                                        return null;
                                      },
                                    ),
                                  );
                                  final publish = IconButton(
                                    tooltip:
                                        'Publicar boletín de ${s['nombre']}',
                                    onPressed: _busy || !_editable
                                        ? null
                                        : () => _publish(s),
                                    icon: const Icon(
                                      Icons.publish_outlined,
                                      color: AppColors.primaryBlue,
                                    ),
                                  );
                                  if (box.maxWidth < 480 ||
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) >
                                          20) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        name,
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            Expanded(child: input),
                                            const SizedBox(width: 12),
                                            publish,
                                          ],
                                        ),
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: name),
                                      const SizedBox(width: 20),
                                      input,
                                      const SizedBox(width: 10),
                                      publish,
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy || !_editable || !_dirty
                                  ? null
                                  : _save,
                              icon: const Icon(Icons.save_outlined),
                              label: Text(
                                _busy
                                    ? 'Procesando…'
                                    : 'Guardar calificaciones',
                              ),
                            ),
                            Text(
                              _dirty
                                  ? 'Cambios sin guardar'
                                  : 'Sin cambios pendientes',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const AcademicMessage(
                          'El icono de publicar genera el boletín del estudiante con todas sus materias. Guarda antes de salir de esta sección.',
                        ),
                        if (!_editable)
                          const AcademicMessage('Año cerrado: solo consulta.'),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
