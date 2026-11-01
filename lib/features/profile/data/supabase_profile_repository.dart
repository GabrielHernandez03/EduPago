import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile_contact_update.dart';
import '../domain/representative_profile.dart';
import 'profile_repository.dart';

/// Consultas del perfil del representante. La RLS debe verificar que
/// auth.uid() sea titular de perfiles.id y representantes.perfil_id.
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<RepresentativeProfile?> loadCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('No hay una sesión activa');
    }
    // No se busca un perfil ajeno por cédula o correo, pues esos datos
    // no constituyen autorización suficiente para acceder a una familia.
    final row = await _client
        .from('representantes')
        .select('*')
        .eq('perfil_id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return RepresentativeProfile.fromRow(
      row,
      authEmail: user.email ?? '',
      authName: (user.userMetadata?['nombre_completo'] ?? '').toString(),
      authIdentification: (user.userMetadata?['cedula'] ?? '').toString(),
    );
  }

  @override
  Future<void> updateContact(ProfileContactUpdate update) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('No hay una sesión activa');
    }
    final changed = await _client
        .from('representantes')
        .update(update.toMap())
        .eq('perfil_id', uid)
        .select('id');
    if (changed.isEmpty) {
      throw StateError(
        'No se encontró un representante vinculado a tu cuenta o no tienes permiso para editarlo.',
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> loadLinkedStudents({
    required String representativeId,
    required String schoolId,
  }) async {
    if (representativeId.isEmpty || schoolId.isEmpty) return [];
    final links = await _client
        .from('representante_estudiante')
        .select('estudiante_id')
        .eq('representante_id', representativeId);
    final ids = links
        .map((r) => (r['estudiante_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return [];
    final results = <Map<String, dynamic>>[];
    // Limita el tamaño de cada consulta y filtra también por colegio.
    for (var i = 0; i < ids.length; i += 100) {
      final end = i + 100 < ids.length ? i + 100 : ids.length;
      final rows = await _client
          .from('estudiantes')
          .select('*')
          .eq('colegio_id', schoolId)
          .inFilter('id', ids.sublist(i, end));
      results.addAll(rows.map((row) => Map<String, dynamic>.from(row)));
    }
    return results;
  }

  @override
  Future<ProfileSchoolInfo?> loadSchool(String schoolId) async {
    if (schoolId.trim().isEmpty) return null;
    final row = await _client
        .from('colegios')
        .select('*')
        .eq('id', schoolId)
        .maybeSingle();
    return row == null ? null : ProfileSchoolInfo.fromRow(row);
  }
}
