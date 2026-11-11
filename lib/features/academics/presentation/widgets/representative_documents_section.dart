import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/academic_repository.dart';
import '../../application/academic_pdf.dart';
import 'academic_widgets.dart';

class RepresentativeDocumentsSection extends StatefulWidget {
  const RepresentativeDocumentsSection({
    super.key,
    required this.students,
    this.initialStudentId,
  });
  final List<Map<String, dynamic>> students;
  final String? initialStudentId;
  @override
  State<RepresentativeDocumentsSection> createState() =>
      _RepresentativeDocumentsSectionState();
}

class _RepresentativeDocumentsSectionState
    extends State<RepresentativeDocumentsSection> {
  final _repo = AcademicRepository();
  List<AcademicRow> _notes = [], _bulletins = [];
  String? _student, _year, _error, _downloading;
  String _term = '1';
  bool _loading = true, _documents = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _student = widget.students.any((s) => s['id'] == widget.initialStudentId)
        ? widget.initialStudentId
        : widget.students.firstOrNull?['id']?.toString();
    _load();
  }

  @override
  void didUpdateWidget(covariant RepresentativeDocumentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.students.any((s) => s['id'] == _student)) {
      _student = widget.students.firstOrNull?['id']?.toString();
      _year = null;
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _notes = [];
      _bulletins = [];
    });
    if (_student == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await _repo.student(_student!);
      if (!mounted || request != _request) return;
      setState(() {
        _notes = academicRows(data['notas']);
        _bulletins = academicRows(data['boletines']);
        if (!_years.containsKey(_year)) _year = _years.keys.firstOrNull;
      });
    } catch (e) {
      if (mounted && request == _request)
        setState(() => _error = academicError(e));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Map<String, String> get _years => {
    for (final r in [..._notes, ..._bulletins])
      r['anio_escolar_id'].toString(): r['anio'].toString(),
  };

  Future<void> _download(AcademicRow bulletin) async {
    setState(() => _downloading = bulletin['id'].toString());
    try {
      // Cada descarga vuelve a verificar identidad, vínculo y solvencia en el servidor.
      final snapshot = await _repo.download(bulletin['id'].toString());
      if (!mounted) return;
      await AcademicPdf.download(snapshot);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(academicError(e))));
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Widget _emptyPanel(IconData icon, String title, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 30, color: AppColors.primaryBlue),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted, height: 1.5),
        ),
      ],
    ),
  );

  Widget _noteCard(AcademicRow note) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder.withValues(alpha: .6)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final subject = SchoolHeading(
            title: note['materia'].toString(),
            icon: Icons.menu_book_outlined,
            subtitle: 'Docente: ${note['docente']}',
          );
          final score = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${note['nota']} / 20',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryBlue,
              ),
            ),
          );
          if (box.maxWidth < 400 ||
              MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [subject, const SizedBox(height: 14), score],
            );
          }
          return Row(
            children: [
              Expanded(child: subject),
              const SizedBox(width: 20),
              score,
            ],
          );
        },
      ),
    ),
  );

  Widget _bulletinCard(AcademicRow bulletin) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: LayoutBuilder(
      builder: (context, box) {
        final heading = SchoolHeading(
          title: 'Boletín del lapso ${bulletin['lapso']}',
          icon: Icons.picture_as_pdf_outlined,
          subtitle: '${bulletin['anio']} · Versión ${bulletin['version']}',
        );
        final action = FilledButton.icon(
          onPressed: _downloading != null ? null : () => _download(bulletin),
          icon: const Icon(Icons.download_outlined),
          label: Text(
            _downloading == bulletin['id'] ? 'Preparando…' : 'Descargar PDF',
          ),
        );
        if (box.maxWidth < 620 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 16), action],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 20),
            action,
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final notes = _notes
        .where(
          (r) =>
              r['anio_escolar_id'] == _year && r['lapso'].toString() == _term,
        )
        .toList();
    final bulletins = _bulletins
        .where(
          (r) =>
              r['anio_escolar_id'] == _year && r['lapso'].toString() == _term,
        )
        .toList();
    return SchoolPageTheme(
      child: LayoutBuilder(
        builder: (context, layout) {
          return RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(layout.maxWidth < 640 ? 18 : 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SchoolHeading(
                        title: 'Documentos y calificaciones',
                        icon: Icons.description_rounded,
                        primary: true,
                        subtitle:
                            'Consulta las notas de tus estudiantes y descarga sus boletines publicados.',
                      ),
                      const SizedBox(height: 22),
                      AcademicCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LayoutBuilder(
                              builder: (context, box) {
                                const heading = SchoolHeading(
                                  title: 'Estudiante y período',
                                  icon: Icons.tune_rounded,
                                );
                                final refresh = TextButton.icon(
                                  onPressed: _loading ? null : _load,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 19,
                                  ),
                                  label: const Text('Actualizar'),
                                );
                                if (box.maxWidth < 480)
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      heading,
                                      const SizedBox(height: 8),
                                      refresh,
                                    ],
                                  );
                                return Row(
                                  children: [
                                    const Expanded(child: heading),
                                    const SizedBox(width: 14),
                                    refresh,
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            SchoolFieldGrid(
                              children: [
                                AcademicSelect(
                                  width: double.infinity,
                                  label: 'Estudiante',
                                  value: _student,
                                  items: {
                                    for (final s in widget.students)
                                      s['id'].toString():
                                          '${s['nombres'] ?? ''} ${s['apellidos'] ?? ''}'
                                              .trim(),
                                  },
                                  enabled: !_loading && _downloading == null,
                                  onChanged: (v) {
                                    setState(() {
                                      _student = v;
                                      _year = null;
                                    });
                                    _load();
                                  },
                                ),
                                AcademicSelect(
                                  width: double.infinity,
                                  label: 'Año escolar',
                                  value: _year,
                                  items: _years,
                                  enabled: !_loading,
                                  onChanged: (v) => setState(() => _year = v),
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
                                  enabled: !_loading,
                                  onChanged: (v) => setState(() => _term = v!),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 510),
                          child: SchoolTabs(
                            grades: _documents,
                            onChanged: (v) => setState(() => _documents = v),
                            firstLabel: 'Calificaciones',
                            secondLabel: 'Boletines PDF',
                            firstIcon: Icons.fact_check_outlined,
                            secondIcon: Icons.picture_as_pdf_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: LinearProgressIndicator(),
                        ),
                      if (_error != null)
                        AcademicCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SchoolHeading(
                                title: 'No pudimos cargar la información',
                                icon: Icons.info_outline,
                              ),
                              AcademicMessage(_error!, error: true),
                              TextButton.icon(
                                onPressed: _loading ? null : _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      if (!_loading && _error == null)
                        AcademicCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_student == null)
                                _emptyPanel(
                                  Icons.groups_outlined,
                                  'Sin estudiantes vinculados',
                                  'Contacta a administración para vincular a tus estudiantes.',
                                ),
                              if (_student != null && !_documents) ...[
                                const SchoolHeading(
                                  title: 'Calificaciones registradas',
                                  icon: Icons.fact_check_outlined,
                                  subtitle:
                                      'Disponibles al guardarlas, aunque el boletín todavía no esté publicado.',
                                ),
                                if (notes.isEmpty)
                                  _emptyPanel(
                                    Icons.edit_note_rounded,
                                    'Aún no hay calificaciones',
                                    'Las notas aparecerán aquí cuando el colegio las registre para este lapso.',
                                  ),
                                for (final note in notes) _noteCard(note),
                              ],
                              if (_student != null && _documents) ...[
                                const SchoolHeading(
                                  title: 'Boletines publicados',
                                  icon: Icons.description_outlined,
                                  subtitle:
                                      'La descarga requiere solvencia. Las calificaciones en pantalla siguen disponibles.',
                                ),
                                if (bulletins.isEmpty)
                                  _emptyPanel(
                                    Icons.description_outlined,
                                    'Boletín pendiente de publicación',
                                    'El colegio todavía no ha publicado el boletín de este lapso.',
                                  ),
                                for (final bulletin in bulletins)
                                  _bulletinCard(bulletin),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
