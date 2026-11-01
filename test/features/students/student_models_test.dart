// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

// Evita acoplar las pruebas al nombre configurado en pubspec.yaml.
import '../../../lib/features/students/domain/student_account.dart';
import '../../../lib/features/students/domain/student_excel_parser.dart';

void main() {
  test('No se declara solvente sin cuotas o sin saldo verificado', () {
    final account = StudentAccount({'id': 's1', 'nombres': 'Ana', 'apellidos': 'Luz'});
    expect(account.status(false), 'sin_datos');
    expect(account.status(true), 'sin_cuotas');
  });

  test('Con una cuota sin fila de saldo no se inventa solvencia', () {
    final account = StudentAccount({'id': 's1'});
    account.quotas.add(StudentQuota({'id': 'c1', 'periodo': 'Octubre 2026'}, 'Mensualidad'));
    expect(account.status(true), 'sin_datos');
  });

  test('Cuotas verificadas determinan pendiente o solvente', () {
    final account = StudentAccount({'id': 's1'});
    final cuota = StudentQuota({'id': 'c1', 'fecha_vencimiento': '2099-10-01'}, 'Mensualidad');
    account.quotas.add(cuota);
    cuota.balanceRow = {'monto_usd': 50, 'saldo_usd': 10};
    expect(account.status(true), 'pendiente');
    cuota.balanceRow = {'monto_usd': 50, 'saldo_usd': 0};
    expect(account.status(true), 'solvente');
  });

  test('Un archivo XLSX inválido se rechaza sin generar registros', () {
    final parsed = StudentExcelParser.parse([1, 2, 3, 4, 5]);
    expect(parsed.rows, isEmpty);
    expect(parsed.errors, isNotEmpty);
  });
}
