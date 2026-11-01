import 'dart:typed_data';
import 'package:excel/excel.dart';

// Columnas obligatorias del Excel
const kRequiredCols = [
  'cedula_estudiante',
  'nombres_estudiante',
  'apellidos_estudiante',
];

// Columnas fijas del estudiante (sin representantes)
const kStudentCols = [
  'cedula_estudiante',
  'nombres_estudiante',
  'apellidos_estudiante',
  'fecha_nacimiento',
  'grado_seccion',
];

// Campos de cada representante (se buscan como repN_campo)
const kRepFields = [
  'cedula',
  'nombres',
  'apellidos',
  'telefono',
  'email',
  'direccion',
  'parentesco',
  'es_financiero',
];

// Resultado del parser
class StudentImportResult {
  final List<Map<String, dynamic>> rows;
  final List<String> errors;
  final int repCount; // total de representantes detectados en todas las filas

  const StudentImportResult(
    this.rows,
    this.errors, {
    this.repCount = 0,
  });
}

// Parser de Excel lógica pura, sin Flutter
class StudentExcelParser {
  static StudentImportResult parse(List<int> bytes) {
    // Decodificar
    final Excel excel;
    try {
      final uint8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      excel = Excel.decodeBytes(uint8);
    } catch (e) {
      return StudentImportResult(
        [],
        ['No se pudo leer el archivo. Asegúrate de que sea un .xlsx válido. ($e)'],
      );
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

    // Mapa encabezado -> índice
    final idx = <String, int>{};
    final headerRow = sheet.rows.first;
    for (var i = 0; i < headerRow.length; i++) {
      final name = _norm(_text(headerRow[i]?.value));
      if (name.isNotEmpty) idx.putIfAbsent(name, () => i);
    }

    // Verificar columnas obligatorias
    final missing = kRequiredCols.where((c) => !idx.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      return StudentImportResult([], [
        'Faltan columnas obligatorias: ${missing.join(', ')}.\n'
            'Comprueba que el encabezado use exactamente estos nombres (minúsculas, sin tildes, con guión bajo).',
      ]);
    }

    // Detectar cuántos bloques de representantes hay en el encabezado (rep1...repN)
    int maxRepCols = 0;
    for (var n = 1; n <= 20; n++) {
      if (idx.containsKey('rep${n}_cedula') ||
          idx.containsKey('rep${n}_nombres')) {
        maxRepCols = n;
      }
    }

    // Helpers de lectura
    String cell(List<Data?> row, String col) {
      final i = idx[col];
      if (i == null || i >= row.length) return '';
      return _text(row[i]?.value).trim();
    }

    // Procesar filas
    final rows = <Map<String, dynamic>>[];
    final errors = <String>[];
    final seenCed = <String>{};
    int totalRepresentatives = 0;

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final fila = r + 1; // número visible en Excel

      // Valores fijos del estudiante
      final vals = {for (final c in kStudentCols) c: cell(row, c)};

      // Saltar filas completamente vacías
      if (vals.values.every((v) => v.isEmpty)) continue;

      final cedEst = vals['cedula_estudiante']!;
      final nombres = vals['nombres_estudiante']!;
      final apellidos = vals['apellidos_estudiante']!;

      if (cedEst.isEmpty || nombres.isEmpty || apellidos.isEmpty) {
        errors.add(
          'Fila $fila: cedula_estudiante, nombres_estudiante y apellidos_estudiante son obligatorios.',
        );
        continue;
      }

      if (!seenCed.add(cedEst.toLowerCase())) {
        errors.add(
          'Fila $fila: La cédula "$cedEst" está repetida en el archivo.',
        );
        continue;
      }

      // Fecha de nacimiento (opcional)
      String? fechaNac;
      final fechaRaw = vals['fecha_nacimiento']!;
      if (fechaRaw.isNotEmpty) {
        final d = parseDate(fechaRaw);
        if (d == null) {
          errors.add(
            'Fila $fila: fecha_nacimiento "$fechaRaw" no es válida. Usa dd/mm/aaaa o aaaa-mm-dd.',
          );
          continue;
        }
        fechaNac = iso(d);
      }

      // Representantes: leer rep1_*, rep2_*, ... repN_*
      final representantes = <Map<String, dynamic>>[];
      for (var n = 1; n <= maxRepCols; n++) {
        final repVals = {
          for (final f in kRepFields) f: cell(row, 'rep${n}_$f'),
        };

        final hasSomeData = repVals.values.any((v) => v.isNotEmpty);
        if (!hasSomeData) continue;

        final cedRep = repVals['cedula']!;
        final nomRep = repVals['nombres']!;
        final apRep = repVals['apellidos']!;

        // Ignorar marcadores explícitos de celda vacía como "(vacio)"
        if (cedRep.toLowerCase() == '(vacio)' ||
            nomRep.toLowerCase() == '(vacio)' ||
            apRep.toLowerCase() == '(vacio)') {
          continue;
        }

        if (cedRep.isEmpty || nomRep.isEmpty || apRep.isEmpty) {
          errors.add(
            'Fila $fila (rep$n): si incluyes un representante, cedula, nombres y apellidos son obligatorios.',
          );
          continue;
        }

        representantes.add({
          'cedula': cedRep,
          'nombres': nomRep,
          'apellidos': apRep,
          'telefono': repVals['telefono']!.isNotEmpty ? repVals['telefono'] : null,
          'email': repVals['email']!.isNotEmpty ? repVals['email'] : null,
          'direccion': repVals['direccion']!.isNotEmpty ? repVals['direccion'] : null,
          'parentesco': repVals['parentesco']!.isNotEmpty ? repVals['parentesco'] : null,
          'es_financiero': repVals['es_financiero'],
        });
      }

      totalRepresentatives += representantes.length;

      rows.add({
        'cedula_estudiante': cedEst,
        'nombres_estudiante': nombres,
        'apellidos_estudiante': apellidos,
        'fecha_nacimiento': fechaNac,
        'grado_seccion': vals['grado_seccion']!.isNotEmpty ? vals['grado_seccion'] : null,
        'representantes': representantes,
      });
    }

    if (rows.isEmpty && errors.isEmpty) {
      errors.add('No se encontraron estudiantes en el archivo.');
    }

    return StudentImportResult(rows, errors, repCount: totalRepresentatives);
  }

  // Utilidades
  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _text(CellValue? v) {
    if (v == null) return '';
    switch (v) {
      case IntCellValue():
        return v.value.toString();
      case DoubleCellValue():
        final d = v.value;
        return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
      case DateCellValue():
        return iso(DateTime(v.year, v.month, v.day));
      case DateTimeCellValue():
        return iso(DateTime(v.year, v.month, v.day));
      default:
        return v.toString();
    }
  }

  static DateTime? parseDate(String s) {
    final serial = double.tryParse(s);
    if (serial != null) {
      if (serial < 1000 || serial > 80000) return null;
      return DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
    }

    final isoMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (isoMatch != null) {
      return _safeDate(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }

    final latinMatch = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(s);
    if (latinMatch != null) {
      return _safeDate(
        int.parse(latinMatch.group(3)!),
        int.parse(latinMatch.group(2)!),
        int.parse(latinMatch.group(1)!),
      );
    }

    return null;
  }

  static DateTime? _safeDate(int y, int m, int d) {
    final dt = DateTime(y, m, d);
    if (dt.year != y || dt.month != m || dt.day != d) return null;
    if (y < 1980 || dt.isAfter(DateTime.now())) return null;
    return dt;
  }
}

