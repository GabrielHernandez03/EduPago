/// Datos del representante utilizados por EduPago.
/// Los campos de identidad se presentan en modo solo lectura.
class RepresentativeProfile {
  const RepresentativeProfile({
    required this.id,
    required this.schoolId,
    required this.fullName,
    required this.identification,
    required this.email,
    required this.phone,
    required this.address,
    this.familyName,
  });

  final String id;
  final String schoolId;
  final String fullName;
  final String identification;
  final String email;
  final String phone;
  final String address;
  final String? familyName;

  factory RepresentativeProfile.fromRow(
    Map<String, dynamic> row, {
    String authEmail = '',
    String authName = '',
    String authIdentification = '',
  }) {
    final first = (row['nombres'] ?? '').toString().trim();
    final last = (row['apellidos'] ?? '').toString().trim();
    final assembled = '$first $last'.trim();
    return RepresentativeProfile(
      id: (row['id'] ?? '').toString(),
      schoolId: (row['colegio_id'] ?? '').toString(),
      fullName: assembled.isNotEmpty ? assembled : authName,
      identification: _nonempty(row['cedula'], authIdentification),
      email: _nonempty(row['email'], authEmail),
      phone: (row['telefono_whatsapp'] ?? '').toString(),
      address: (row['direccion'] ?? '').toString(),
      familyName: _nullableString(row['familia']),
    );
  }

  static String _nonempty(dynamic value, String fallback) {
    final str = value?.toString().trim() ?? '';
    return str.isNotEmpty ? str : fallback;
  }

  static String? _nullableString(dynamic value) {
    final str = value?.toString().trim() ?? '';
    return str.isEmpty ? null : str;
  }
}

class ProfileSchoolInfo {
  const ProfileSchoolInfo({required this.name, this.period});

  final String name;
  final String? period;

  factory ProfileSchoolInfo.fromRow(Map<String, dynamic> row) {
    String? period;
    for (final field in [
      'periodo_escolar',
      'periodo_actual',
      'anio_escolar',
      'ano_escolar',
    ]) {
      final candidate = row[field]?.toString().trim() ?? '';
      if (candidate.isNotEmpty) {
        period = candidate;
        break;
      }
    }
    return ProfileSchoolInfo(
      name: (row['nombre'] ?? '').toString(),
      period: period,
    );
  }
}
