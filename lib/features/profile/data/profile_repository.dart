import '../domain/profile_contact_update.dart';
import '../domain/representative_profile.dart';

/// Contrato de acceso a los datos del perfil.
abstract class ProfileRepository {
  Future<RepresentativeProfile?> loadCurrentProfile();

  /// Modifica solo telefono_whatsapp y direccion del usuario autenticado.
  Future<void> updateContact(ProfileContactUpdate update);

  Future<List<Map<String, dynamic>>> loadLinkedStudents({
    required String representativeId,
    required String schoolId,
  });

  Future<ProfileSchoolInfo?> loadSchool(String schoolId);
}
