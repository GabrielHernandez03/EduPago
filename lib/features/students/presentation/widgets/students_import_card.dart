import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;

import '../../../../core/theme/app_colors.dart';
import '../../data/student_repository.dart';
import '../../data/supabase_student_repository.dart';
import '../../domain/student_excel_parser.dart';
import 'manual_student_dialog.dart';

// Widget
enum _Step { idle, reading, ready, importing }

class StudentsImportCard extends StatefulWidget {
  final String colegioId;
  final VoidCallback onImported;

  const StudentsImportCard({
    super.key,
    required this.colegioId,
    required this.onImported,
  });

  @override
  State<StudentsImportCard> createState() => StudentsImportCardState();
}

class StudentsImportCardState extends State<StudentsImportCard> {
  final StudentRepository _repository = SupabaseStudentRepository();
  _Step _step = _Step.idle;
  String? _fileName;
  StudentImportResult? result;
  String? fatal;
  List<Map<String, dynamic>> serverErrors = [];

  // Descargar plantilla (Compatible con Web y Escritorio/Móvil con FilePicker 13+)
  Future<void> downloadTemplate() async {
    try {
      final byteData = await rootBundle.load(
        'assets/Plantilla de Insercion.xlsx',
      );
      final fileBytes = byteData.buffer.asUint8List();

      if (kIsWeb) {
        final blob = html.Blob([fileBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'Plantilla de Insercion.xlsx')
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        await FilePicker.saveFile(
          dialogTitle: 'Guardar plantilla de ejemplo',
          fileName: 'Plantilla de Insercion.xlsx',
          bytes: fileBytes,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plantilla descargada con éxito.'),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar plantilla: $e'),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
      }
    }
  }

  // Agregar manualmente
  Future<void> showManualAddDialog() async {
    final saved = await showManualStudentDialog(
      context,
      colegioId: widget.colegioId,
    );

    if (!mounted || saved == null || saved <= 0) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved == 1
              ? 'Estudiante registrado correctamente.'
              : '$saved estudiantes registrados correctamente.',
        ),
        backgroundColor: const Color(0xFF059669),
      ),
    );

    widget.onImported();
  }

  // Selección de archivo Excel (Compatible con FilePicker 13+)
  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );

    if (files.isEmpty) return;

    final file = files.first;
    final bytes = await file.readAsBytes();

    setState(() {
      fatal = null;
      result = null;
      serverErrors = [];
      _step = _Step.reading;
      _fileName = file.name;
    });

    await Future<void>.delayed(const Duration(milliseconds: 60));
    final parsedResult = StudentExcelParser.parse(bytes);

    if (!mounted) return;

    setState(() {
      result = parsedResult;
      _step = _Step.ready;
    });
  }

  // Importación
  Future<void> import() async {
    final r = result;
    if (r == null || r.rows.isEmpty || r.errors.isNotEmpty) return;

    setState(() {
      _step = _Step.importing;
      fatal = null;
      serverErrors = [];
    });

    try {
      final data = await _repository.importStudents(
        colegioId: widget.colegioId, rows: r.rows,
      );

      if (!mounted) return;
      debugPrint('Respuesta de la función: $data');
      if (data == null) {
        setState(() {
          _step = _Step.ready;
          fatal = 'La función no devolvió respuesta. Revisa los logs de Supabase.';
        });
        return;
      }

      final exitosos = (data['exitosos'] as num?)?.toInt() ?? 0;
      final errores = (data['errores'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];

      if (exitosos == 0 && errores.isNotEmpty) {
        setState(() {
          _step = _Step.ready;
          serverErrors = errores;
          fatal = 'No se importó ningún estudiante. Revisa los errores.';
        });
        return;
      }

      setState(() => serverErrors = errores);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errores.isEmpty
                  ? '$exitosos estudiantes importados correctamente.'
                  : '$exitosos importados, ${errores.length} con errores.',
            ),
            backgroundColor: errores.isEmpty
                ? const Color(0xFF059669)
                : const Color(0xFFD97706),
          ),
        );
      }

      widget.onImported();
    } catch (e) {
      debugPrint('Error detallado al invocar import-students: $e');
      if (!mounted) return;
      setState(() {
        _step = _Step.ready;
        fatal = 'Error detallado al invocar la función: $e';
      });
    }
  }

  void reset() => setState(() {
        _step = _Step.idle;
        result = null;
        _fileName = null;
        fatal = null;
        serverErrors = [];
      });

  // UI
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildTemplateDownloadSection(),
                const SizedBox(height: 28),
                _buildContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.upload_file_rounded,
            color: AppColors.primaryBlue,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Aún no hay estudiantes registrados',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Importa tu matrícula masivamente desde un archivo Excel (.xlsx) o registra estudiantes de forma manual.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textMuted,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateDownloadSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.table_chart_rounded,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plantilla de Inserción Excel',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Descarga el archivo de ejemplo con las columnas y formato requeridos.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: downloadTemplate,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.darkNavy,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(
              Icons.download_rounded,
              size: 16,
              color: AppColors.primaryBlue,
            ),
            label: const Text(
              'Descargar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case _Step.reading:
        return const Loader(label: 'Leyendo archivo...');
      case _Step.importing:
        return const Loader(label: 'Procesando estudiantes...');
      case _Step.ready:
        return _buildPreview();
      case _Step.idle:
        return Column(
          children: [
            if (fatal != null) _errorBox([fatal!]),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _pick,
                  style: _primaryStyle(),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Seleccionar archivo Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: showManualAddDialog,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.darkNavy,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(
                    Icons.person_add_rounded,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                  label: const Text(
                    'Agregar manualmente',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _buildPreview() {
    final r = result!;
    final hasLocalErrors = r.errors.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.description_outlined,
              size: 16,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _fileName ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkNavy,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!hasLocalErrors)
          _infoBox(
            '${r.rows.length} estudiantes listos. ${r.repCount} representante${r.repCount == 1 ? '' : 's'} detectado${r.repCount == 1 ? '' : 's'}.',
            icon: Icons.check_circle_outline,
            color: const Color(0xFF059669),
            bg: const Color(0xFFF0FDF4),
            border: const Color(0xFFBBF7D0),
          ),
        if (hasLocalErrors)
          _errorBox([
            '${r.errors.length} ${r.errors.length == 1 ? 'problema encontrado' : 'problemas encontrados'}, corrige el archivo y vuelve a cargarlo:',
            ...r.errors.take(12),
            if (r.errors.length > 12) '... y ${r.errors.length - 12} más.',
          ]),
        if (serverErrors.isNotEmpty) ...[
          const SizedBox(height: 8),
          _errorBox([
            '${serverErrors.length} fila${serverErrors.length == 1 ? '' : 's'} con errores en el servidor:',
            ...serverErrors.take(10).map(
                  (e) => 'Fila ${e['fila']} (${e['cedula']}): ${e['motivo']}',
                ),
            if (serverErrors.length > 10)
              '... y ${serverErrors.length - 10} más.',
          ]),
        ],
        if (fatal != null) ...[
          const SizedBox(height: 8),
          _errorBox([fatal!]),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _pick,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: Text(
                hasLocalErrors ? 'Elegir otro archivo' : 'Cambiar archivo',
              ),
            ),
            if (!hasLocalErrors && r.rows.isNotEmpty)
              ElevatedButton.icon(
                onPressed: import,
                style: _primaryStyle(),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text('Importar ${r.rows.length} estudiantes'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _infoBox(
    String text, {
    required IconData icon,
    required Color color,
    required Color bg,
    required Color border,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(List<String> lines) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                l,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFB91C1C),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ButtonStyle _primaryStyle() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      );
}

class Loader extends StatelessWidget {
  final String label;
  const Loader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}