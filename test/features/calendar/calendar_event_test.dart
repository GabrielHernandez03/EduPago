// ignore_for_file: avoid_relative_lib_imports
// Para utilizar un import package: necesitamos el valor `name` de pubspec.yaml.

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/features/calendar/domain/calendar_event.dart';

void main() {
  group('CalendarStudent', () {
    test('convierte el mapa del dashboard a un modelo tipado', () {
      final student = CalendarStudent.fromMap({
        'id': 'student-123',
        'nombres': 'Ana',
        'apellidos': 'Pérez',
      });
      expect(student.id, 'student-123');
      expect(student.name, 'Ana Pérez');
    });

    test('acepta datos opcionales sin lanzar excepciones', () {
      final student = CalendarStudent.fromMap({'id': 'student-456'});
      expect(student.id, 'student-456');
      expect(student.name, '');
    });
  });

  test('un evento diferencia un reporte de un pago aprobado', () {
    final event = CalendarEvent(
      id: 'payment-123-reported',
      date: DateTime(2026, 10, 29),
      kind: CalendarEventKind.reported,
      title: 'Pago reportado',
      details: 'Referencia 123456',
      amount: '55,00 USD',
      paymentId: '123',
      pending: true,
    );
    expect(event.kind, CalendarEventKind.reported);
    expect(event.pending, isTrue);
    expect(event.paymentId, '123');
  });
}
