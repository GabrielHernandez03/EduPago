import 'package:flutter_test/flutter_test.dart';

import 'package:edupago/core/widgets/dashboard_shell.dart';

void main() {
  group('Navegación responsiva de EduPago', () {
    test('identifica correctamente los anchos compactos y de escritorio', () {
      expect(Breakpoints.isCompact(390), isTrue);
      expect(Breakpoints.isCompact(640), isFalse);
      expect(Breakpoints.isDesktop(900), isFalse);
      expect(Breakpoints.isDesktop(1200), isTrue);
    });

    test('reserva más espacio lateral en pantallas anchas', () {
      expect(Breakpoints.pagePadding(390), 18);
      expect(Breakpoints.pagePadding(700), 28);
      expect(Breakpoints.pagePadding(1100), 36);
      expect(Breakpoints.pagePadding(1300), 48);
    });
  });
}
