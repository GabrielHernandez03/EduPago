// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/features/profile/domain/profile_contact_update.dart';
import '../../../lib/features/profile/domain/representative_profile.dart';

void main() {
  test('Convierte teléfonos venezolanos al formato internacional', () {
    final update = ProfileContactUpdate(
      phone: '0412 555 0174',
      address: '  Caracas, Venezuela  ',
    );
    expect(update.internationalPhone, '+584125550174');
    expect(update.toMap().keys, containsAll(['telefono_whatsapp', 'direccion']));
    expect(update.toMap().keys, isNot(contains('cedula')));
    expect(update.toMap().keys, isNot(contains('nombres')));
    expect(update.address, 'Caracas, Venezuela');
    expect(update.toMap().keys.toSet(), {'telefono_whatsapp', 'direccion'});
  });

  test('No acepta teléfonos o direcciones inválidos', () {
    expect(
      () => ProfileContactUpdate(phone: '12345', address: 'Caracas'),
      throwsFormatException,
    );
    expect(
      () => ProfileContactUpdate(phone: '4125550174', address: 'abc'),
      throwsFormatException,
    );
    expect(
      () => ProfileContactUpdate(phone: '41255501745', address: 'Caracas'),
      throwsFormatException,
    );
  });

  test('Construye identidad desde la fila real de representantes', () {
    final p = RepresentativeProfile.fromRow({
      'id': 'rep-1',
      'colegio_id': 'school-1',
      'nombres': 'Alejandro',
      'apellidos': 'Hernández',
      'cedula': 'V-12345678',
      'telefono_whatsapp': '+584125550174',
      'direccion': 'Caracas',
    }, authEmail: 'test@example.org');
    expect(p.fullName, 'Alejandro Hernández');
    expect(p.schoolId, 'school-1');
    expect(p.email, 'test@example.org');
  });

  test('No inventa un período escolar si el colegio no lo proporciona', () {
    final school = ProfileSchoolInfo.fromRow({'nombre': 'Colegio Central'});
    expect(school.name, 'Colegio Central');
    expect(school.period, isNull);
  });
}
