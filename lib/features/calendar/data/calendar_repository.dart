import '../domain/calendar_event.dart';

/// Contrato de acceso a eventos. La presentación desconoce el origen de datos.
abstract class CalendarRepository {
  Future<CalendarLoadResult> loadEvents({
    required String representativeId,
    required List<CalendarStudent> students,
  });

  /// Escucha cambios que exigen actualizar el calendario.
  /// El consumidor debe llamar stopListening() al cerrar o cambiar usuario.
  void startListening({
    required String representativeId,
    required void Function() onChanged,
  });

  void stopListening();
}
