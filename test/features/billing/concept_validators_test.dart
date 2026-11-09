import 'package:flutter_test/flutter_test.dart';

// Si prefieres import de paquete, cambia por:
// import 'package:<nombre_en_pubspec>/features/billing/domain/billing_concept.dart';
import '../../../lib/features/billing/domain/billing_concept.dart';

void main() {
  group('ConceptValidators.nombre', () {
    test('rechaza vacío o solo espacios', () {
      expect(ConceptValidators.nombre(null), isNotNull);
      expect(ConceptValidators.nombre('   '), isNotNull);
    });

    test('acepta un nombre válido', () {
      expect(ConceptValidators.nombre('Mensualidad escolar'), isNull);
    });

    test('rechaza más de 80 caracteres', () {
      expect(ConceptValidators.nombre('a' * 81), isNotNull);
    });
  });

  group('ConceptValidators.monto', () {
    test('rechaza vacío, cero y texto', () {
      expect(ConceptValidators.monto(''), isNotNull);
      expect(ConceptValidators.monto('0'), isNotNull);
      expect(ConceptValidators.monto('abc'), isNotNull);
    });

    test('acepta punto o coma decimal', () {
      expect(ConceptValidators.monto('45.00'), isNull);
      expect(ConceptValidators.monto('45,50'), isNull);
      expect(ConceptValidators.parseMonto('45,50'), 45.5);
    });
  });

  group('ConceptValidators.diaVencimiento', () {
    test('rechaza nulo y fuera de rango', () {
      expect(ConceptValidators.diaVencimiento(null), isNotNull);
      expect(ConceptValidators.diaVencimiento(0), isNotNull);
      expect(ConceptValidators.diaVencimiento(29), isNotNull);
    });

    test('acepta 1 a 28', () {
      expect(ConceptValidators.diaVencimiento(1), isNull);
      expect(ConceptValidators.diaVencimiento(28), isNull);
    });
  });
}
