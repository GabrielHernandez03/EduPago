/// Modelo independiente de Flutter y Supabase para los movimientos del calendario.
enum CalendarEventKind { generated, due, paid, reported, approved, rejected }

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.date,
    required this.kind,
    required this.title,
    required this.details,
    this.amount,
    this.studentId,
    this.paymentId,
    this.pending = false,
  });

  final String id;
  final DateTime date;
  final CalendarEventKind kind;
  final String title;
  final String details;
  final String? amount;
  final String? studentId;
  final String? paymentId;
  final bool pending;
}

class CalendarStudent {
  const CalendarStudent({required this.id, required this.name});

  final String id;
  final String name;

  factory CalendarStudent.fromMap(Map<String, dynamic> row) {
    final first = (row['nombres'] ?? '').toString().trim();
    final last = (row['apellidos'] ?? '').toString().trim();
    return CalendarStudent(
      id: (row['id'] ?? '').toString().trim(),
      name: '$first $last'.trim(),
    );
  }
}

class CalendarLoadResult {
  const CalendarLoadResult({
    required this.events,
    required this.warnings,
    required this.hasSuccessfulSource,
  });

  final List<CalendarEvent> events;
  final List<String> warnings;
  final bool hasSuccessfulSource;
}
