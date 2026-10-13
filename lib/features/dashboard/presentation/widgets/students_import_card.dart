import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';

const _kRequired = ['nombres', 'apellidos'];
const _kAllColumns = [
  'codigo_estudiantil',
  'cedula',
  'nombres',
  'apellidos',
  'fecha_nacimiento',
  'activo',
  'grado_seccion',
  'grado', // por compatibilidad con encabezados antiguos
];

class StudentImportResult {
  final List<Map<String, dynamic>> rows;
  final List<String> errors;
  const StudentImportResult(this.rows, this.errors);
}

class StudentExcelParser {
  static StudentImportResult parse(List<int> bytes, String colegioId) {
    final Excel excel;
    try {
      // Convertimos a Uint8List para compatibilidad total con la librería excel
      final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      excel = Excel.decodeBytes(uint8Bytes);
    } catch (e) {
      return StudentImportResult([], [
        'No se pudo leer el archivo. Asegúrate de que sea un .xlsx válido. ($e)',
      ]);
    }

    if (excel.tables.isEmpty) {
      return const StudentImportResult([], ['El archivo no tiene hojas.']);
    }
    final sheet = excel.tables.values.first;
    if (sheet.rows.length < 2) {
      return const StudentImportResult([], [
        'El archivo no contiene filas de datos debajo del encabezado.',
      ]);
    }

    final idx = <String, int>{};
    final header = sheet.rows.first;
    for (var i = 0; i < header.length; i++) {
      final name = _norm(_text(header[i]?.value));
      if (name.isNotEmpty) idx.putIfAbsent(name, () => i);
    }

    final missing = _kRequired.where((c) => !idx.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      return StudentImportResult([], [
        'Faltan columnas obligatorias: ${missing.join(', ')}.',
      ]);
    }

    String cell(List<Data?> row, String col) {
      final i = idx[col];
      if (i == null || i >= row.length) return '';
      return _text(row[i]?.value).trim();
    }

    final rows = <Map<String, dynamic>>[];
    final errors = <String>[];
    final seen = <String>{};

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final line = r + 1;

      final values = {for (final c in _kAllColumns) c: cell(row, c)};
      if (values.values.every((v) => v.isEmpty)) continue;

      // Toma la cédula o el codigo_estudiantil indistintamente como código único
      final cedulaRaw = values['cedula']!.isNotEmpty
          ? values['cedula']!
          : values['codigo_estudiantil']!;

      final codigo = cedulaRaw;
      final nombres = values['nombres']!;
      final apellidos = values['apellidos']!;

      if (codigo.isEmpty) {
        errors.add(
          'Fila $line: Se requiere la cédula o el código estudiantil.',
        );
        continue;
      }

      if (nombres.isEmpty || apellidos.isEmpty) {
        errors.add('Fila $line: nombres y apellidos son obligatorios.');
        continue;
      }

      if (!seen.add(codigo.toLowerCase())) {
        errors.add(
          'Fila $line: La cédula / código "$codigo" está repetido en el archivo.',
        );
        continue;
      }

      String? fecha;
      final fechaRaw = values['fecha_nacimiento']!;
      if (fechaRaw.isNotEmpty) {
        final d = _parseDate(fechaRaw);
        if (d == null) {
          errors.add(
            'Fila $line: fecha_nacimiento "$fechaRaw" no es válida (usa dd/mm/aaaa).',
          );
          continue;
        }
        fecha = _iso(d);
      }

      final activo = _parseBool(values['activo']!);
      if (activo == null) {
        errors.add(
          'Fila $line: activo "${values['activo']}" no es válido (usa SI/NO).',
        );
        continue;
      }

      // Mapea grado o grado_seccion para coincidir exactamente con la tabla en Supabase
      final gradoSeccion = values['grado_seccion']!.isNotEmpty
          ? values['grado_seccion']!
          : (values['grado']!.isNotEmpty ? values['grado']! : null);

      rows.add({
        'colegio_id': colegioId,
        'codigo_estudiantil': codigo, // Cédula usada como código estudiantil
        'cedula': codigo, // Guarda también la cédula
        'nombres': nombres,
        'apellidos': apellidos,
        'fecha_nacimiento': fecha,
        'activo': activo,
        'grado_seccion': gradoSeccion, // Mapeado a la columna real de Supabase
      });
    }

    if (rows.isEmpty && errors.isEmpty) {
      errors.add('No se encontraron estudiantes en el archivo.');
    }
    return StudentImportResult(rows, errors);
  }

  static String _norm(String s) => s.trim().toLowerCase().replaceAll(' ', '_');

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _text(CellValue? v) {
    if (v == null) return '';
    switch (v) {
      case IntCellValue():
        return v.value.toString();
      case DoubleCellValue():
        final d = v.value;
        return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
      case DateCellValue():
        return _iso(DateTime(v.year, v.month, v.day));
      case DateTimeCellValue():
        return _iso(DateTime(v.year, v.month, v.day));
      default:
        return v.toString();
    }
  }

  static DateTime? _parseDate(String s) {
    DateTime? d;
    final serial = double.tryParse(s);
    if (serial != null) {
      if (serial < 1000 || serial > 80000) return null;
      d = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
    } else {
      final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
      final latin = RegExp(
        r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
      ).firstMatch(s);
      if (iso != null) {
        d = _safeDate(
          int.parse(iso.group(1)!),
          int.parse(iso.group(2)!),
          int.parse(iso.group(3)!),
        );
      } else if (latin != null) {
        d = _safeDate(
          int.parse(latin.group(3)!),
          int.parse(latin.group(2)!),
          int.parse(latin.group(1)!),
        );
      }
    }

    if (d == null) return null;
    final now = DateTime.now();
    if (d.year < 1980 || d.isAfter(now)) return null;
    return d;
  }

  static DateTime? _safeDate(int y, int m, int d) {
    final dt = DateTime(y, m, d);
    return (dt.year == y && dt.month == m && dt.day == d) ? dt : null;
  }

  static bool? _parseBool(String s) {
    final v = s.trim().toLowerCase();
    if (v.isEmpty) return true;
    const yes = {'si', 'sí', 's', 'true', '1', 'x', 'activo', 'yes', 'y'};
    const no = {'no', 'n', 'false', '0', 'inactivo'};
    if (yes.contains(v)) return true;
    if (no.contains(v)) return false;
    return null;
  }
}

// ---------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------
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
  State<StudentsImportCard> createState() => _StudentsImportCardState();
}

class _StudentsImportCardState extends State<StudentsImportCard> {
  _Step _step = _Step.idle;
  String? _fileName;
  StudentImportResult? _result;
  String? _fatal;

  static const _chunk = 500;

  Future<void> _pick() async {
    setState(() {
      _fatal = null;
      _result = null;
    });

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _fatal = 'No se pudo leer el archivo seleccionado.');
      return;
    }

    setState(() {
      _step = _Step.reading;
      _fileName = file.name;
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final result = StudentExcelParser.parse(bytes, widget.colegioId);

    if (!mounted) return;
    setState(() {
      _result = result;
      _step = _Step.ready;
    });
  }

  Future<void> _import() async {
    final result = _result;
    if (result == null || result.rows.isEmpty || result.errors.isNotEmpty) {
      return;
    }

    setState(() {
      _step = _Step.importing;
      _fatal = null;
    });

    try {
      for (var i = 0; i < result.rows.length; i += _chunk) {
        final end = (i + _chunk).clamp(0, result.rows.length);
        await supabase
            .from('estudiantes')
            .upsert(
              result.rows.sublist(i, end),
              onConflict: 'colegio_id,codigo_estudiantil',
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.rows.length} estudiantes importados.'),
        ),
      );
      widget.onImported();
    } catch (e) {
      debugPrint('Error al importar estudiantes: $e');
      if (!mounted) return;
      setState(() {
        _step = _Step.ready;
        _fatal = 'No se pudo completar la importación: $e';
      });
    }
  }

  void _reset() => setState(() {
    _step = _Step.idle;
    _result = null;
    _fileName = null;
    _fatal = null;
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.upload_file_outlined,
                    color: AppColors.primaryBlue,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Aún no hay estudiantes registrados',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Importa tu matrícula desde un archivo Excel (.xlsx) para activar el panel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 18),
                _columnsHint(),
                const SizedBox(height: 20),
                _content(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _columnsHint() {
    const displayCols = [
      'cedula',
      'nombres',
      'apellidos',
      'fecha_nacimiento',
      'activo',
      'grado',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final c in displayCols)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kRequired.contains(c) || c == 'cedula'
                  ? const Color(0xFFDBEAFE)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _kRequired.contains(c) || c == 'cedula' ? '$c *' : c,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppColors.darkNavy,
              ),
            ),
          ),
      ],
    );
  }

  Widget _content() {
    switch (_step) {
      case _Step.reading:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        );
      case _Step.importing:
        return Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Importando ${_result?.rows.length ?? 0} estudiantes…',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        );
      case _Step.ready:
        return _preview();
      case _Step.idle:
        return Column(
          children: [
            if (_fatal != null) _errorBox([_fatal!]),
            ElevatedButton.icon(
              onPressed: _pick,
              style: _primaryStyle(),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Seleccionar archivo Excel'),
            ),
            const SizedBox(height: 10),
            const Text(
              '* obligatorias · fecha en formato dd/mm/aaaa · activo: SI/NO (vacío = SI)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        );
    }
  }

  Widget _preview() {
    final r = _result!;
    final hasErrors = r.errors.isNotEmpty;

    return Column(
      children: [
        Text(
          _fileName ?? '',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 10),
        if (!hasErrors)
          Text(
            '${r.rows.length} estudiantes listos para importar.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF059669)),
          ),
        if (hasErrors)
          _errorBox([
            '${r.errors.length} ${r.errors.length == 1 ? 'problema' : 'problemas'} '
                'encontrados. Corrige el archivo y vuelve a cargarlo (no se importó nada):',
            ...r.errors.take(8),
            if (r.errors.length > 8) '… y ${r.errors.length - 8} más.',
          ]),
        if (_fatal != null) _errorBox([_fatal!]),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _reset,
              child: Text(hasErrors ? 'Elegir otro archivo' : 'Cancelar'),
            ),
            if (!hasErrors && r.rows.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _import,
                style: _primaryStyle(),
                icon: const Icon(Icons.check, size: 18),
                label: Text('Importar ${r.rows.length} estudiantes'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _errorBox(List<String> lines) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
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
                style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C)),
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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}
