import 'package:supabase_flutter/supabase_flutter.dart';

typedef AcademicRow = Map<String, dynamic>;
List<AcademicRow> academicRows(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

class AcademicRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<AcademicRow> context([String? year]) async =>
      Map<String, dynamic>.from(
        await _db.rpc('academico_contexto', params: {'p_anio': year}) as Map,
      );

  Future<void> addSubject(String year, String grade, String name) async {
    await _db.rpc(
      'academico_materia',
      params: {'p_anio': year, 'p_grado': grade, 'p_nombre': name},
    );
  }

  Future<void> enroll(
    String year,
    String student,
    String grade,
    String section,
  ) async {
    await _db.rpc(
      'academico_inscribir',
      params: {
        'p_anio': year,
        'p_estudiante': student,
        'p_grado': grade,
        'p_seccion': section,
      },
    );
  }

  Future<List<AcademicRow>> grades(
    String school,
    String year,
    String subject,
    String term,
  ) async {
    // La lectura respeta las RLS existentes. Pagina para no truncar salones grandes.
    final result = <AcademicRow>[];
    for (var offset = 0; ; offset += 500) {
      final page = academicRows(
        await _db
            .from('calificaciones')
            .select('id,estudiante_id,nota,docente')
            .eq('colegio_id', school)
            .eq('anio_escolar_id', year)
            .eq('materia', subject)
            .eq('lapso', term)
            .order('id')
            .range(offset, offset + 499),
      );
      result.addAll(page);
      if (page.length < 500) return result;
    }
  }

  Future<int> save(
    String year,
    String subjectId,
    String term,
    String teacher,
    List<AcademicRow> grades,
  ) async => (await _db.rpc(
    'academico_guardar',
    params: {
      'p_anio': year,
      'p_materia': subjectId,
      'p_lapso': term,
      'p_docente': teacher,
      'p_notas': grades,
    },
  ) as num).toInt();

  Future<void> publish(String student, String year, String term) async {
    await _db.rpc(
      'academico_publicar',
      params: {'p_estudiante': student, 'p_anio': year, 'p_lapso': term},
    );
  }

  Future<AcademicRow> student(String student) async =>
      Map<String, dynamic>.from(
        await _db.rpc('academico_consultar', params: {'p_estudiante': student})
            as Map,
      );

  Future<AcademicRow> download(String bulletin) async =>
      Map<String, dynamic>.from(
        await _db.rpc('academico_descargar', params: {'p_boletin': bulletin})
            as Map,
      );
}

String academicError(Object error) {
  if (error is FormatException) return error.message;
  if (error is PostgrestException) {
    if (error.code == '23505')
      return 'Ese registro ya existe. Revisa el nombre y el año seleccionado.';
    if (error.code == 'P0001') return error.message;
    if (error.code == 'PGRST202' || error.code == '42P01') {
      return 'Falta instalar o actualizar el módulo académico en Supabase.';
    }
    if (error.code == '42501')
      return 'Tu usuario no tiene permiso para esta operación.';
  }
  return 'No se pudo completar la operación. Revisa tu conexión e inténtalo de nuevo.';
}
