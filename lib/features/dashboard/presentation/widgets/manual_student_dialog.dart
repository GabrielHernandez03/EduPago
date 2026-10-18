// lib/features/dashboard/presentation/widgets/manual_student_dialog.dart

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';

// ---------------------------------------------------------------------------
// API pública
// ---------------------------------------------------------------------------

/// Abre el diálogo de registro manual.
/// Devuelve la cantidad de estudiantes registrados con éxito (0 si ninguno).
Future<int?> showManualStudentDialog(
  BuildContext context, {
  required String colegioId,
}) {
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ManualStudentDialog(colegioId: colegioId),
  );
}

// ---------------------------------------------------------------------------
// Constantes de estilo (mismos tonos que students_import_card.dart)
// ---------------------------------------------------------------------------
const _kBorder = Color(0xFFE2E8F0);
const _kBorderSoft = Color(0xFFF1F5F9);
const _kSoft = Color(0xFFF8FAFC);
const _kBlueSoft = Color(0xFFEFF6FF);
const _kRed = Color(0xFFB91C1C);
const _kRedSoft = Color(0xFFFEF2F2);
const _kRedBorder = Color(0xFFFECACA);
const _kGreen = Color(0xFF059669);
const _kGreenSoft = Color(0xFFF0FDF4);
const _kGreenBorder = Color(0xFFBBF7D0);
const _kAmber = Color(0xFFD97706);
const _kAmberSoft = Color(0xFFFFFBEB);
const _kAmberBorder = Color(0xFFFDE68A);

// ⚠ AJUSTA estos nombres a tu esquema de Supabase. Las columnas de
// representantes salen de tu captura; los nombres de las TABLAS son suposición.
const _kTblEstudiantes = 'estudiantes';
const _kColCedulaEstudiante = 'cedula';
const _kTblRepresentantes = 'representantes';
const _kColCedulaRep = 'cedula';
const _kSelectRep = 'id, nombres, apellidos, telefono_whatsapp, email';

/// Prefijos de documento: valor → descripción.
const _kCedPrefixes = {
  'V-': 'Venezolano',
  'E-': 'Extranjero',
  'J-': 'Jurídico',
  'P-': 'Pasaporte',
};

const _kParentescos = [
  'madre',
  'padre',
  'tutor',
  'tutora',
  'abuelo',
  'abuela',
  'tío',
  'tía',
  'familiar',
  'otro',
];

// ---------------------------------------------------------------------------
// Modelos de borrador (solo viven en memoria hasta pulsar "Aceptar")
// ---------------------------------------------------------------------------
class _RepDraft {
  final String cedula;
  final String nombres;
  final String apellidos;
  final String? telefono;
  final String? email;
  final String parentesco;
  final bool esFinanciero;

  /// true si ya existía en la base de datos al momento de ingresarlo.
  final bool existente;

  const _RepDraft({
    required this.cedula,
    required this.nombres,
    required this.apellidos,
    this.telefono,
    this.email,
    required this.parentesco,
    required this.esFinanciero,
    this.existente = false,
  });

  String get fullName => '$nombres $apellidos';

  Map<String, dynamic> toJson() => {
    'cedula': cedula,
    'nombres': nombres,
    'apellidos': apellidos,
    'telefono': telefono,
    'email': email,
    'parentesco': parentesco,
    'es_financiero': esFinanciero,
  };
}

class _StudentDraft {
  final String cedula;
  final String nombres;
  final String apellidos;
  final String? fechaNacimiento; // ISO yyyy-MM-dd
  final String? gradoSeccion;
  final List<_RepDraft> reps;
  final String? serverError;

  const _StudentDraft({
    required this.cedula,
    required this.nombres,
    required this.apellidos,
    this.fechaNacimiento,
    this.gradoSeccion,
    this.reps = const [],
    this.serverError,
  });

  String get fullName => '$nombres $apellidos';

  _StudentDraft withError(String? error) => _StudentDraft(
    cedula: cedula,
    nombres: nombres,
    apellidos: apellidos,
    fechaNacimiento: fechaNacimiento,
    gradoSeccion: gradoSeccion,
    reps: reps,
    serverError: error,
  );

  Map<String, dynamic> toJson() => {
    'cedula_estudiante': cedula,
    'nombres_estudiante': nombres,
    'apellidos_estudiante': apellidos,
    'fecha_nacimiento': fechaNacimiento,
    'grado_seccion': gradoSeccion,
    'representantes': reps.map((r) => r.toJson()).toList(),
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

String _initials(String a, String b) {
  final x = a.trim().isNotEmpty ? a.trim()[0] : '';
  final y = b.trim().isNotEmpty ? b.trim()[0] : '';
  return (x + y).toUpperCase();
}

/// 'E-123456' → ['E-', '123456']. Sin prefijo reconocible usa 'V-'.
List<String> _splitCed(String full) {
  final m = RegExp(r'^([VEJPvejp])-(.*)$').firstMatch(full.trim());
  if (m != null) return ['${m.group(1)!.toUpperCase()}-', m.group(2)!];
  return ['V-', full.trim().replaceAll(RegExp(r'\D'), '')];
}

String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

String? _req(String? v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null;

String _two(int n) => n.toString().padLeft(2, '0');

String _dmy(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)}/${d.year.toString().padLeft(4, '0')}';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String _isoToDmy(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (m == null) return '';
  return '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}

/// Misma regla que el parser de Excel: fecha real, >= 1980 y no futura.
DateTime? _parseDmy(String s) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(s);
  if (m == null) return null;
  final d = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final y = int.parse(m.group(3)!);
  final dt = DateTime(y, mo, d);
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  if (y < 1980 || dt.isAfter(DateTime.now())) return null;
  return dt;
}

OutlineInputBorder _outline(Color c, [double w = 1]) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(10),
  borderSide: BorderSide(color: c, width: w),
);

InputDecoration _dec(
  String label, {
  String? hint,
  IconData? icon,
  Widget? suffix,
  Widget? prefixWidget,
  bool locked = false,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: locked ? const Color(0xFFF1F5F9) : _kSoft,
    prefixIcon:
        prefixWidget ??
        (icon == null
            ? null
            : Icon(icon, size: 18, color: AppColors.textMuted)),
    prefixIconConstraints: prefixWidget == null
        ? null
        : const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    labelStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
    errorStyle: const TextStyle(fontSize: 11, color: _kRed),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: _outline(_kBorder),
    enabledBorder: _outline(_kBorder),
    focusedBorder: _outline(AppColors.primaryBlue, 1.6),
    errorBorder: _outline(const Color(0xFFDC2626)),
    focusedErrorBorder: _outline(const Color(0xFFDC2626), 1.6),
  );
}

ButtonStyle _primaryBtn() => ElevatedButton.styleFrom(
  backgroundColor: AppColors.primaryBlue,
  foregroundColor: Colors.white,
  disabledBackgroundColor: const Color(0xFFCBD5E1),
  disabledForegroundColor: Colors.white,
  elevation: 0,
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

ButtonStyle _outlineBtn({
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
}) => OutlinedButton.styleFrom(
  backgroundColor: Colors.white,
  foregroundColor: AppColors.darkNavy,
  side: const BorderSide(color: Color(0xFFCBD5E1)),
  padding: padding,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

/// Formatea mientras se escribe: 12072015 → 12/07/2015
class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(d[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogo
// ---------------------------------------------------------------------------
enum _NoticeKind { error, warning }

class _ManualStudentDialog extends StatefulWidget {
  final String colegioId;
  const _ManualStudentDialog({required this.colegioId});

  @override
  State<_ManualStudentDialog> createState() => _ManualStudentDialogState();
}

class _ManualStudentDialogState extends State<_ManualStudentDialog> {
  final _studentFormKey = GlobalKey<FormState>();

  // Estudiante
  final _cedEst = TextEditingController();
  final _nomEst = TextEditingController();
  final _apEst = TextEditingController();
  final _fecha = TextEditingController();
  final _grado = TextEditingController();
  final _cedFocus = FocusNode();
  // Cada "época" recrea los campos del formulario (limpia errores residuales)
  // sin depender de FormState.reset(), que con controllers es poco fiable.
  int _studentEpoch = 0;
  bool _autoValStudent =
      false; // revalidar en vivo solo tras un intento fallido
  // cédula → detalle del error cuando la consulta a la BD falló
  final Map<String, String> _studentCheckErrors = {};
  // cédula del estudiante → ¿ya es un representante de este colegio en la BD?
  final Map<String, bool> _studentIsRep = {};
  Timer? _studentCheckTimer;
  String _pEst = 'V-';
  bool _checkingStudent = false;
  // cédula completa (minúsculas) → ¿existe en la BD? Solo guarda consultas exitosas.
  final Map<String, bool> _studentExists = {};

  // Estado general
  List<_RepDraft> _currentReps = [];
  final List<_StudentDraft> _queue = [];
  int? _editingIndex;
  final _queueScroll = ScrollController();

  bool _saving = false;
  int _savedCount = 0;
  List<String> _noticeLines = [];
  _NoticeKind _noticeKind = _NoticeKind.error;

  @override
  void initState() {
    super.initState();
    _cedFocus.addListener(() {
      if (!_cedFocus.hasFocus) _checkStudentCed();
    });
  }

  @override
  void dispose() {
    for (final c in [_cedEst, _nomEst, _apEst, _fecha, _grado]) {
      c.dispose();
    }
    _cedFocus.dispose();
    _studentCheckTimer?.cancel();
    _queueScroll.dispose();
    super.dispose();
  }

  // ── Derivados ─────────────────────────────────────────────────────────────
  bool get _studentFormDirty =>
      [
        _cedEst,
        _nomEst,
        _apEst,
        _fecha,
        _grado,
      ].any((c) => c.text.trim().isNotEmpty) ||
      _currentReps.isNotEmpty;

  int get _existingRepsInQueue =>
      _queue.fold(0, (n, s) => n + s.reps.where((r) => r.existente).length);

  String get _fullEstCed => '$_pEst${_cedEst.text.trim()}';

  int get _totalReps => _queue.fold(0, (sum, s) => sum + s.reps.length);

  // ── Avisos dentro del diálogo ─────────────────────────────────────────────
  void _setNotice(_NoticeKind kind, List<String> lines) {
    _noticeKind = kind;
    _noticeLines = lines;
  }

  void _clearNotice() {
    _noticeLines = [];
  }

  // ── Validadores ───────────────────────────────────────────────────────────
  String? _validateStudentCed(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Obligatorio';
    final full = '$_pEst$t'.toLowerCase();
    final dup = _queue.indexWhere((s) => s.cedula.toLowerCase() == full);
    if (dup != -1 && dup != _editingIndex) return 'Ya está en la lista';
    return null;
  }

  String? _validateDate(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return _parseDmy(t) == null ? 'Usa dd/mm/aaaa con una fecha válida' : null;
  }

  // ── Fecha ─────────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = _parseDmy(_fecha.text.trim());
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 8, 1, 1),
      firstDate: DateTime(1980),
      lastDate: now,
      helpText: 'Fecha de nacimiento',
    );
    if (picked != null && mounted) {
      setState(() => _fecha.text = _dmy(picked));
    }
  }

  // ── Verificación contra la base de datos ──────────────────────────────────
  // Es una ayuda de UX: la validación definitiva debe seguir en el servidor
  // (restricción UNIQUE + Edge Function), porque aquí RLS o una carrera entre
  // dos usuarios pueden dar un "no existe" falso.

  void _setVerifyWarning(String quien, String detalle) {
    final corto = detalle.length > 160
        ? '${detalle.substring(0, 160)}…'
        : detalle;
    _setNotice(_NoticeKind.warning, [
      'No se pudo verificar la cédula del $quien en la base de datos.',
      'Detalle: $corto',
      'Revisa los nombres de tabla y columna (constantes _kTbl… y _kCol… al '
          'inicio de manual_student_dialog.dart) y las políticas RLS.',
    ]);
  }

  Future<void> _checkStudentCed() async {
    if (!mounted || _cedEst.text.trim().isEmpty) return;
    final full = _fullEstCed;
    final key = full.toLowerCase();
    if (_studentExists.containsKey(key) && _studentIsRep.containsKey(key)) {
      return;
    }

    setState(() => _checkingStudent = true);
    String? failure;
    try {
      final results = await Future.wait<bool>([
        _studentCedExistsInDb(full),
        _cedExistsAsRepresentative(full),
      ]);
      _studentExists[key] = results[0];
      _studentIsRep[key] = results[1];
      _studentCheckErrors.remove(key);
      debugPrint(
        'Verificación cédula $full (colegio ${widget.colegioId}): '
        'estudiante=${results[0] ? 'YA EXISTE' : 'no'}, '
        'representante=${results[1] ? 'YA EXISTE' : 'no'}',
      );
    } catch (e) {
      debugPrint('No se pudo verificar la cédula del estudiante: $e');
      failure = e.toString();
      _studentCheckErrors[key] = failure;
    }
    if (!mounted) return;
    setState(() {
      _checkingStudent = false;
      if (failure != null) _setVerifyWarning('estudiante', failure);
    });
  }

  /// ¿Existe ya un estudiante con esta cédula en ESTE colegio?
  /// La misma cédula sí puede existir en otros colegios (un niño puede estar
  /// registrado en varios); la unicidad es por (colegio_id, cedula).
  Future<bool> _studentCedExistsInDb(String full) async {
    final row = await supabase
        .from(_kTblEstudiantes)
        .select('id')
        .eq('colegio_id', widget.colegioId)
        .eq(_kColCedulaEstudiante, full)
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  /// ¿Esta cédula ya pertenece a un representante de este colegio?
  Future<bool> _cedExistsAsRepresentative(String full) async {
    final row = await supabase
        .from(_kTblRepresentantes)
        .select('id')
        .eq('colegio_id', widget.colegioId)
        .eq(_kColCedulaRep, full)
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  /// ¿La cédula coincide con un representante del formulario o de la lista?
  bool _studentCedInLocalReps(String key) {
    if (_currentReps.any((r) => r.cedula.toLowerCase() == key)) return true;
    for (var i = 0; i < _queue.length; i++) {
      if (i == _editingIndex) continue;
      if (_queue[i].reps.any((r) => r.cedula.toLowerCase() == key)) {
        return true;
      }
    }
    return false;
  }

  /// Aviso fijo bajo el campo de cédula del estudiante.
  Widget _buildStudentCedStatus() {
    if (_cedEst.text.trim().isEmpty) return const SizedBox.shrink();
    final key = _fullEstCed.toLowerCase();
    final String text;
    final Color color;
    final IconData icon;
    if (_studentExists[key] == true) {
      text =
          'Ya existe un estudiante con esta cédula en este colegio. '
          'No se puede agregar.';
      color = _kRed;
      icon = Icons.error_outline_rounded;
    } else if (_studentIsRep[key] == true) {
      text =
          'Esta cédula pertenece a un representante registrado en este '
          'colegio. No puede usarse para un estudiante.';
      color = _kRed;
      icon = Icons.error_outline_rounded;
    } else if (_studentCedInLocalReps(key)) {
      text =
          'Esta cédula coincide con la de un representante de la lista. '
          'No puede usarse para un estudiante.';
      color = _kRed;
      icon = Icons.error_outline_rounded;
    } else if (_studentCheckErrors.containsKey(key)) {
      text =
          'No se pudo verificar la cédula en la base de datos. '
          'No se puede agregar hasta verificarla.';
      color = _kAmber;
      icon = Icons.warning_amber_rounded;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _focusCedula() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cedFocus.requestFocus();
    });
  }

  // ── Representantes (formulario en ventana modal) ──────────────────────────
  Future<void> _openRepDialog({int? index}) async {
    final result = await showGeneralDialog<_RepDraft>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Representante',
      barrierColor: Colors.black.withOpacity(0.28),
      transitionDuration: const Duration(milliseconds: 200),
      // Sin FadeTransition: una opacidad por encima rompería el desenfoque.
      transitionBuilder: (ctx, anim, secondary, child) => child,
      pageBuilder: (ctx, anim, secondary) => _RepFormDialog(
        colegioId: widget.colegioId,
        initial: index == null ? null : _currentReps[index],
        defaultFinanciero: !_currentReps.any((r) => r.esFinanciero),
        otherRepCeds: {
          for (var i = 0; i < _currentReps.length; i++)
            if (i != index) _currentReps[i].cedula.toLowerCase(),
        },
        currentStudentCed: _cedEst.text.trim().isEmpty
            ? ''
            : _fullEstCed.toLowerCase(),
        queuedStudentCeds: {
          for (var i = 0; i < _queue.length; i++)
            if (i != _editingIndex) _queue[i].cedula.toLowerCase(),
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index != null) {
        _currentReps[index] = result;
      } else {
        _currentReps.add(result);
      }
      _clearNotice();
    });
  }

  void _addRep() => _openRepDialog();

  void _editRep(int i) => _openRepDialog(index: i);

  void _removeRep(int i) {
    setState(() => _currentReps.removeAt(i));
  }

  // ── Estudiantes ───────────────────────────────────────────────────────────
  void _resetStudentForm() {
    for (final c in [_cedEst, _nomEst, _apEst, _fecha, _grado]) {
      c.clear();
    }
    _studentEpoch++;
    _autoValStudent = false;
    _pEst = 'V-';
    _currentReps = [];
    _editingIndex = null;
  }

  void _clearStudentForm() {
    _resetStudentForm();
    setState(_clearNotice);
    _focusCedula();
  }

  Future<void> _submitStudent() async {
    await _checkStudentCed();
    if (!mounted) return;

    if (_cedEst.text.trim().isNotEmpty) {
      final key = _fullEstCed.toLowerCase();
      if (_studentExists[key] == true) {
        setState(
          () => _setNotice(_NoticeKind.error, [
            'Ya existe un estudiante con la cédula $_fullEstCed en este colegio.',
            'No se puede agregar a la lista.',
          ]),
        );
        return;
      }
      if (_studentIsRep[key] == true) {
        setState(
          () => _setNotice(_NoticeKind.error, [
            'La cédula $_fullEstCed pertenece a un representante de este colegio.',
            'No puede usarse para un estudiante.',
          ]),
        );
        return;
      }
      if (_studentCedInLocalReps(key)) {
        setState(
          () => _setNotice(_NoticeKind.error, [
            'La cédula $_fullEstCed coincide con la de un representante de la lista.',
            'No puede usarse para un estudiante.',
          ]),
        );
        return;
      }
      final failure = _studentCheckErrors[key];
      if (failure != null) {
        setState(() => _setVerifyWarning('estudiante', failure));
        return;
      }
    }

    if (!(_studentFormKey.currentState?.validate() ?? false)) {
      setState(() => _autoValStudent = true);
      return;
    }

    final fechaText = _fecha.text.trim();
    final draft = _StudentDraft(
      cedula: '$_pEst${_cedEst.text.trim()}',
      nombres: _nomEst.text.trim(),
      apellidos: _apEst.text.trim(),
      fechaNacimiento: fechaText.isEmpty ? null : _iso(_parseDmy(fechaText)!),
      gradoSeccion: _nullIfEmpty(_grado.text),
      reps: List.of(_currentReps),
    );

    final editing = _editingIndex;
    _resetStudentForm();
    setState(() {
      if (editing != null) {
        _queue[editing] = draft;
      } else {
        _queue.add(draft);
      }
      _clearNotice();
    });
    _focusCedula();

    if (editing == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_queueScroll.hasClients) {
          _queueScroll.animateTo(
            _queueScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _editStudent(int i) {
    if (_editingIndex == null && _studentFormDirty) {
      setState(
        () => _setNotice(_NoticeKind.error, [
          'Termina o limpia el estudiante actual antes de editar otro.',
        ]),
      );
      return;
    }
    final s = _queue[i];
    _studentEpoch++;
    _autoValStudent = false;
    final ced = _splitCed(s.cedula);
    _pEst = ced[0];
    _cedEst.text = ced[1];
    _nomEst.text = s.nombres;
    _apEst.text = s.apellidos;
    _fecha.text = s.fechaNacimiento == null
        ? ''
        : _isoToDmy(s.fechaNacimiento!);
    _grado.text = s.gradoSeccion ?? '';
    setState(() {
      _currentReps = List.of(s.reps);
      _editingIndex = i;
      _clearNotice();
    });
    _focusCedula();
  }

  void _removeStudent(int i) {
    final wasEditing = _editingIndex == i;
    if (wasEditing) _resetStudentForm();
    setState(() {
      _queue.removeAt(i);
      if (!wasEditing && _editingIndex != null && i < _editingIndex!) {
        _editingIndex = _editingIndex! - 1;
      }
      _clearNotice();
    });
  }

  // ── Registrar todo ────────────────────────────────────────────────────────
  Future<void> _accept() async {
    if (_queue.isEmpty || _saving) return;
    if (_studentFormDirty) {
      setState(
        () => _setNotice(_NoticeKind.error, [
          'Hay datos en el formulario que no están en la lista.',
          'Pulsa "Agregar a la lista" o "Limpiar" antes de aceptar.',
        ]),
      );
      return;
    }

    setState(() {
      _saving = true;
      _clearNotice();
      for (var i = 0; i < _queue.length; i++) {
        _queue[i] = _queue[i].withError(null);
      }
    });

    try {
      final response = await supabase.functions.invoke(
        'import-students',
        body: {
          'colegio_id': widget.colegioId,
          'rows': _queue.map((s) => s.toJson()).toList(),
        },
      );
      if (!mounted) return;

      final raw = response.data;
      final data = raw is Map ? Map<String, dynamic>.from(raw) : null;
      if (data == null) {
        setState(() {
          _saving = false;
          _setNotice(_NoticeKind.error, [
            'La función no devolvió respuesta. Revisa los logs de Supabase.',
          ]);
        });
        return;
      }

      final exitosos = (data['exitosos'] as num?)?.toInt() ?? 0;
      final errores =
          (data['errores'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];

      // Todo bien
      if (errores.isEmpty && exitosos > 0) {
        Navigator.of(context).pop(_savedCount + exitosos);
        return;
      }
      if (errores.isEmpty && exitosos == 0) {
        setState(() {
          _saving = false;
          _setNotice(_NoticeKind.error, [
            'El servidor no confirmó ningún registro. Inténtalo de nuevo.',
          ]);
        });
        return;
      }

      // Hay errores: se asocian a cada estudiante por cédula.
      final errByCed = <String, String>{};
      final unmatched = <String>[];
      for (final e in errores) {
        final ced = (e['cedula'] ?? '').toString().trim().toLowerCase();
        final motivo = (e['motivo'] ?? 'Error desconocido').toString();
        if (ced.isNotEmpty &&
            _queue.any((s) => s.cedula.toLowerCase() == ced)) {
          errByCed[ced] = motivo;
        } else {
          unmatched.add(
            'Fila ${e['fila'] ?? '?'} (${e['cedula'] ?? 's/n'}): $motivo',
          );
        }
      }

      setState(() {
        _saving = false;
        _savedCount += exitosos;

        // Solo se retiran de la lista los registrados cuando el mapeo de
        // errores es inequívoco; si no, se conserva todo para no perder datos.
        final canPrune = exitosos > 0 && unmatched.isEmpty;
        final next = <_StudentDraft>[];
        for (final s in _queue) {
          final err = errByCed[s.cedula.toLowerCase()];
          if (err != null) {
            next.add(s.withError(err));
          } else if (!canPrune) {
            next.add(s);
          }
        }
        _queue
          ..clear()
          ..addAll(next);

        if (exitosos == 0) {
          _setNotice(_NoticeKind.error, [
            'No se registró ningún estudiante. Revisa los errores en la lista.',
            ...unmatched.take(6),
          ]);
        } else if (canPrune) {
          _setNotice(_NoticeKind.warning, [
            '$exitosos registrado${exitosos == 1 ? '' : 's'}. '
                '${errByCed.length} con error: corrígelos (botón editar) '
                'y vuelve a aceptar.',
          ]);
        } else {
          _setNotice(_NoticeKind.warning, [
            'Se registraron $exitosos, pero algunos errores no se pudieron '
                'asociar a un estudiante. Revisa la lista de estudiantes '
                'antes de reintentar para evitar duplicados.',
            ...unmatched.take(6),
          ]);
        }
      });
    } catch (e) {
      debugPrint('Error al invocar import-students: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _setNotice(_NoticeKind.error, ['Error de conexión: $e']);
      });
    }
  }

  // ── Cerrar ────────────────────────────────────────────────────────────────
  Future<void> _tryClose() async {
    if (_saving) return;
    if (_queue.isEmpty && !_studentFormDirty) {
      Navigator.of(context).pop(_savedCount);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Descartar los cambios?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
        content: Text(
          _queue.isEmpty
              ? 'Hay datos en el formulario que aún no se han agregado.'
              : 'Tienes ${_plural(_queue.length, 'estudiante')} sin registrar. '
                    'Si cierras ahora, se perderán.',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir editando'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(_savedCount);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // UI
  // ═════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: _kBorderSoft),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) =>
                    c.maxWidth >= 860 ? _buildWide() : _buildNarrow(),
              ),
            ),
            if (_noticeLines.isNotEmpty) _buildNotice(),
            const Divider(height: 1, color: _kBorderSoft),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Cabecera ──────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kBlueSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.person_add_rounded,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agregar estudiantes manualmente',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Completa los datos, agrégalos a la lista y regístralos todos juntos.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: _saving ? null : _tryClose,
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ── Layouts ───────────────────────────────────────────────────────────────
  Widget _buildWide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildFormContent(),
          ),
        ),
        Container(
          width: 360,
          decoration: const BoxDecoration(
            color: _kSoft,
            border: Border(left: BorderSide(color: _kBorderSoft)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: _buildQueueHeader(),
              ),
              Expanded(child: _buildQueueList(scrollable: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormContent(),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQueueHeader(),
                const SizedBox(height: 12),
                _buildQueueList(scrollable: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Formulario ────────────────────────────────────────────────────────────
  Widget _buildFormContent() {
    final editing = _editingIndex != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (editing) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: _kBlueSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editando a ${_queue[_editingIndex!].fullName}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Estudiante ──────────────────────────────────────────────────────
        const _SectionTitle(
          icon: Icons.school_rounded,
          title: 'Datos del estudiante',
        ),
        const SizedBox(height: 14),
        Form(
          key: _studentFormKey,
          autovalidateMode: _autoValStudent
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            key: ValueKey('student-form-$_studentEpoch'),
            children: [
              _Row2(
                _CedulaField(
                  controller: _cedEst,
                  focusNode: _cedFocus,
                  onChanged: (_) {
                    setState(() {});
                    // Verifica mientras escribe (con pausa de 600 ms).
                    _studentCheckTimer?.cancel();
                    if (_cedEst.text.trim().length >= 5) {
                      _studentCheckTimer = Timer(
                        const Duration(milliseconds: 600),
                        _checkStudentCed,
                      );
                    }
                  },
                  checking: _checkingStudent,
                  prefix: _pEst,
                  validator: _validateStudentCed,
                  onPrefixChanged: (p) {
                    setState(() {
                      _pEst = p;
                      if (p != 'J-') {
                        _cedEst.text = _cedEst.text.replaceAll(
                          RegExp(r'\D'),
                          '',
                        );
                      }
                    });
                    _checkStudentCed();
                  },
                ),
                TextFormField(
                  controller: _fecha,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [_DateInputFormatter()],
                  decoration: _dec(
                    'Fecha de nacimiento',
                    hint: 'dd/mm/aaaa',
                    icon: Icons.cake_outlined,
                    suffix: IconButton(
                      tooltip: 'Elegir en el calendario',
                      onPressed: _pickDate,
                      icon: const Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  validator: _validateDate,
                ),
              ),
              _buildStudentCedStatus(),
              const SizedBox(height: 14),
              _Row2(
                TextFormField(
                  controller: _nomEst,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: _dec('Nombres *'),
                  validator: _req,
                ),
                TextFormField(
                  controller: _apEst,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: _dec('Apellidos *'),
                  validator: _req,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _grado,
                textInputAction: TextInputAction.done,
                decoration: _dec(
                  'Grado y sección',
                  hint: 'Ej. 3er grado A',
                  icon: Icons.class_outlined,
                ),
              ),
            ],
          ),
        ),

        // ── Representantes ──────────────────────────────────────────────────
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          spacing: 12,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SectionTitle(
                  icon: Icons.family_restroom_rounded,
                  title: 'Representantes',
                ),
                const SizedBox(width: 8),
                _CountPill(_currentReps.length),
              ],
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _addRep,
              style: _outlineBtn(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              icon: const Icon(
                Icons.person_add_alt_1_rounded,
                size: 16,
                color: AppColors.primaryBlue,
              ),
              label: const Text(
                'Agregar representante',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),

        for (var i = 0; i < _currentReps.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _RepTile(
              rep: _currentReps[i],
              onEdit: () => _editRep(i),
              onDelete: () => _removeRep(i),
            ),
          ),

        if (_currentReps.isNotEmpty &&
            !_currentReps.any((r) => r.esFinanciero)) ...[
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: _kAmber),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ningún representante está marcado como responsable de pagos.',
                  style: TextStyle(fontSize: 11, color: _kAmber),
                ),
              ),
            ],
          ),
        ],

        if (_currentReps.isEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.family_restroom_rounded,
                  size: 20,
                  color: Color(0xFFCBD5E1),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Opcional. Puedes agregar uno o varios representantes para este estudiante.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Acciones del formulario ─────────────────────────────────────────
        const SizedBox(height: 24),
        Row(
          children: [
            if (editing)
              TextButton(
                onPressed: _clearStudentForm,
                child: const Text('Cancelar edición'),
              )
            else
              TextButton.icon(
                onPressed: _clearStudentForm,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Limpiar'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                ),
              ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _saving ? null : _submitStudent,
              style: _primaryBtn(),
              icon: Icon(
                editing ? Icons.check_rounded : Icons.playlist_add_rounded,
                size: 18,
              ),
              label: Text(
                editing ? 'Guardar cambios' : 'Agregar a la lista',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Lista de estudiantes por registrar ────────────────────────────────────
  Widget _buildQueueHeader() {
    return Row(
      children: [
        const _SectionTitle(
          icon: Icons.checklist_rounded,
          title: 'Lista por registrar',
        ),
        const SizedBox(width: 8),
        _CountPill(_queue.length),
      ],
    );
  }

  Widget _buildQueueList({required bool scrollable}) {
    if (_queue.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: _kBlueSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.playlist_add_rounded,
                  color: AppColors.primaryBlue,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Aún no hay estudiantes en la lista',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Completa el formulario y pulsa "Agregar a la lista". '
                'Cuando termines, pulsa "Aceptar" para registrarlos todos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget tile(int i) => _StudentTile(
      student: _queue[i],
      editing: _editingIndex == i,
      disabled: _saving,
      onEdit: () => _editStudent(i),
      onDelete: () => _removeStudent(i),
    );

    if (scrollable) {
      return ListView.separated(
        controller: _queueScroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        itemCount: _queue.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => tile(i),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _queue.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: tile(i),
          ),
      ],
    );
  }

  // ── Aviso y pie ───────────────────────────────────────────────────────────
  Widget _buildNotice() {
    final isErr = _noticeKind == _NoticeKind.error;
    final color = isErr ? _kRed : _kAmber;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isErr ? _kRedSoft : _kAmberSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isErr ? _kRedBorder : _kAmberBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isErr ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _noticeLines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
                    child: Text(
                      _noticeLines[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final ex = _existingRepsInQueue;
    final exTxt = ex == 0 ? '' : ' ($ex ya registrado${ex == 1 ? '' : 's'})';
    final summary = _queue.isEmpty
        ? 'Agrega al menos un estudiante para continuar.'
        : '${_plural(_queue.length, 'estudiante')} y '
              '${_plural(_totalReps, 'representante')}$exTxt '
              'listos para registrar.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _saving ? null : _tryClose,
            style: _outlineBtn(),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: (_queue.isEmpty || _saving) ? null : _accept,
            style: _primaryBtn(),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: Text(
              _saving
                  ? 'Registrando…'
                  : (_queue.isEmpty
                        ? 'Aceptar'
                        : 'Aceptar y registrar (${_queue.length})'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets pequeños
// ---------------------------------------------------------------------------
/// Campo de cédula con selector de prefijo (V-, E-, J-, P-).
/// El controller guarda solo el número; el prefijo lo maneja el padre.
class _CedulaField extends StatelessWidget {
  final TextEditingController controller;
  final String prefix;
  final ValueChanged<String> onPrefixChanged;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final GlobalKey<FormFieldState<String>>? fieldKey;
  final bool checking;
  final ValueChanged<String>? onChanged;

  const _CedulaField({
    required this.controller,
    required this.prefix,
    required this.onPrefixChanged,
    this.focusNode,
    this.validator,
    this.fieldKey,
    this.checking = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isJ = prefix == 'J-';
    return TextFormField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.next,
      keyboardType: isJ ? TextInputType.text : TextInputType.number,
      inputFormatters: [
        // J- (RIF) puede llevar guion antes del dígito verificador.
        FilteringTextInputFormatter.allow(RegExp(isJ ? r'[0-9-]' : r'[0-9]')),
        LengthLimitingTextInputFormatter(12),
      ],
      decoration: _dec(
        'Cédula *',
        hint: '30123456',
        suffix: checking ? const _MiniSpinner() : null,
        prefixWidget: PopupMenuButton<String>(
          tooltip: 'Tipo de documento',
          initialValue: prefix,
          onSelected: onPrefixChanged,
          position: PopupMenuPosition.under,
          offset: const Offset(0, 8),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          itemBuilder: (_) => [
            for (final e in _kCedPrefixes.entries)
              PopupMenuItem<String>(
                value: e.key,
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy,
                        ),
                      ),
                    ),
                    Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  prefix,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Container(width: 1, height: 22, color: _kBorder),
              ],
            ),
          ),
        ),
      ),
      validator: validator,
    );
  }
}

class _MiniSpinner extends StatelessWidget {
  const _MiniSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(13),
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ExistingBadge extends StatelessWidget {
  const _ExistingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _kBlueSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_rounded, size: 11, color: AppColors.primaryBlue),
          SizedBox(width: 4),
          Text(
            'Ya registrado',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _kBlueSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primaryBlue),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.darkNavy,
          ),
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: _kBlueSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryBlue,
        ),
      ),
    );
  }
}

/// Dos columnas; en pantallas angostas se apilan.
class _Row2 extends StatelessWidget {
  final Widget a;
  final Widget b;
  const _Row2(this.a, this.b);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 420) {
          return Column(children: [a, const SizedBox(height: 14), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 14),
            Expanded(child: b),
          ],
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  final String text;
  final double size;
  const _Avatar(this.text, {this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _kBlueSoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryBlue,
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  const _MiniAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: color ?? AppColors.textMuted),
    );
  }
}

class _FinancialBadge extends StatelessWidget {
  const _FinancialBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _kGreenSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGreenBorder),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.payments_rounded, size: 11, color: _kGreen),
          SizedBox(width: 4),
          Text(
            'Pagos',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _kGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepTile extends StatelessWidget {
  final _RepDraft rep;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  const _RepTile({
    required this.rep,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final extra = [
      if (rep.telefono != null) rep.telefono!,
      if (rep.email != null) rep.email!,
    ].join('   ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: _kSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          _Avatar(_initials(rep.nombres, rep.apellidos), size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        rep.fullName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy,
                        ),
                      ),
                    ),
                    if (rep.esFinanciero) ...[
                      const SizedBox(width: 8),
                      const _FinancialBadge(),
                    ],
                    if (rep.existente) ...[
                      const SizedBox(width: 6),
                      const _ExistingBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_cap(rep.parentesco)}   ${rep.cedula}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                if (extra.isNotEmpty)
                  Text(
                    extra,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          _MiniAction(
            icon: Icons.edit_outlined,
            tooltip: 'Editar representante',
            onPressed: onEdit,
          ),
          _MiniAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Quitar representante',
            onPressed: onDelete,
            color: _kRed,
          ),
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final _StudentDraft student;
  final bool editing;
  final bool disabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StudentTile({
    required this.student,
    required this.editing,
    required this.disabled,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = student.serverError != null;
    final details = [
      student.cedula,
      if (student.gradoSeccion != null) student.gradoSeccion!,
    ].join('   ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: hasError ? _kRedSoft : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasError
              ? _kRedBorder
              : (editing ? AppColors.primaryBlue : _kBorder),
          width: editing ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(_initials(student.nombres, student.apellidos)),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _MiniAction(
                icon: Icons.edit_outlined,
                tooltip: 'Editar',
                onPressed: disabled ? null : onEdit,
              ),
              _MiniAction(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Quitar de la lista',
                onPressed: disabled ? null : onDelete,
                color: _kRed,
              ),
            ],
          ),
          if (student.reps.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in student.reps)
                    Container(
                      constraints: const BoxConstraints(maxWidth: 230),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _kSoft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            r.esFinanciero
                                ? Icons.payments_rounded
                                : Icons.person_outline_rounded,
                            size: 12,
                            color: r.esFinanciero
                                ? _kGreen
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '${_cap(r.parentesco)}: ${r.fullName}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.darkNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (hasError) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: _kRed,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      student.serverError!,
                      style: const TextStyle(fontSize: 11, color: _kRed),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ventana modal (fondo desenfocado) para agregar / editar un representante
// ---------------------------------------------------------------------------
class _RepFormDialog extends StatefulWidget {
  final String colegioId;
  final _RepDraft? initial; // null = representante nuevo
  final bool defaultFinanciero;
  final Set<String> otherRepCeds; // cédulas (minúsculas) de los demás reps
  final String currentStudentCed; // cédula del estudiante en el formulario
  final Set<String> queuedStudentCeds; // cédulas de estudiantes en la lista

  const _RepFormDialog({
    required this.colegioId,
    required this.initial,
    required this.defaultFinanciero,
    required this.otherRepCeds,
    required this.currentStudentCed,
    required this.queuedStudentCeds,
  });

  @override
  State<_RepFormDialog> createState() => _RepFormDialogState();
}

class _RepFormDialogState extends State<_RepFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ced = TextEditingController();
  final _nom = TextEditingController();
  final _ap = TextEditingController();
  final _tel = TextEditingController();
  final _email = TextEditingController();
  final _cedFocus = FocusNode();

  String _prefix = 'V-';
  String _parentesco = 'madre';
  late bool _financiero;
  bool _checking = false;
  bool _locked = false; // datos autocompletados desde la BD
  bool _autoVal = false;
  bool _saving = false;
  String? _checkError;
  Timer? _timer;
  // cédula completa (minúsculas) → fila de la BD, o null si no existe.
  final Map<String, Map<String, dynamic>?> _lookup = {};

  String get _fullCed => '$_prefix${_ced.text.trim()}';

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _financiero = r?.esFinanciero ?? widget.defaultFinanciero;
    if (r != null) {
      final c = _splitCed(r.cedula);
      _prefix = c[0];
      _ced.text = c[1];
      _nom.text = r.nombres;
      _ap.text = r.apellidos;
      _tel.text = r.telefono ?? '';
      _email.text = r.email ?? '';
      _parentesco = r.parentesco;
    }
    _cedFocus.addListener(() {
      if (!_cedFocus.hasFocus) _check();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (r == null) {
        _cedFocus.requestFocus();
      } else {
        _check();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_ced, _nom, _ap, _tel, _email]) {
      c.dispose();
    }
    _cedFocus.dispose();
    super.dispose();
  }

  // ── Validadores ───────────────────────────────────────────────────────────
  String? _validateCed(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Obligatorio';
    final full = '$_prefix$t'.toLowerCase();
    if (widget.otherRepCeds.contains(full)) {
      return 'Ya agregado a este estudiante';
    }
    if (widget.currentStudentCed.isNotEmpty &&
        full == widget.currentStudentCed) {
      return 'Es la cédula del estudiante';
    }
    if (widget.queuedStudentCeds.contains(full)) {
      return 'Es la cédula de un estudiante de la lista';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
        ? null
        : 'Correo no válido';
  }

  // ── Verificación contra la base de datos (este colegio) ──────────────────
  Future<void> _check() async {
    if (!mounted) return;
    if (_ced.text.trim().isEmpty) {
      _unlock();
      return;
    }
    final full = _fullCed;
    final key = full.toLowerCase();

    if (!_lookup.containsKey(key)) {
      setState(() {
        _checking = true;
        _checkError = null;
      });
      String? failure;
      try {
        final row = await supabase
            .from(_kTblRepresentantes)
            .select(_kSelectRep)
            .eq('colegio_id', widget.colegioId)
            .eq(_kColCedulaRep, full)
            .limit(1)
            .maybeSingle();
        _lookup[key] = row;
      } catch (e) {
        debugPrint('No se pudo verificar la cédula del representante: $e');
        failure = e.toString();
      }
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkError = failure;
      });
    }
    // Si cambió la cédula mientras se consultaba, no se aplica.
    if (_fullCed.toLowerCase() != key) return;

    final found = _lookup[key];
    if (found != null) {
      _apply(found);
    } else {
      _unlock();
    }
  }

  void _apply(Map<String, dynamic> row) {
    String v(String k) => (row[k] ?? '').toString();
    _nom.text = v('nombres');
    _ap.text = v('apellidos');
    _tel.text = v('telefono_whatsapp');
    _email.text = v('email');
    setState(() => _locked = true);
  }

  void _unlock() {
    if (!_locked) return;
    for (final c in [_nom, _ap, _tel, _email]) {
      c.clear();
    }
    setState(() => _locked = false);
  }

  // ── Guardar ───────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _check();
    if (!mounted) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() {
        _saving = false;
        _autoVal = true;
      });
      return;
    }
    final full = _fullCed;
    Navigator.of(context).pop(
      _RepDraft(
        existente: _lookup[full.toLowerCase()] != null,
        cedula: full,
        nombres: _nom.text.trim(),
        apellidos: _ap.text.trim(),
        telefono: _nullIfEmpty(_tel.text),
        email: _nullIfEmpty(_email.text),
        parentesco: _parentesco,
        esFinanciero: _financiero,
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Fondo desenfocado (fuera de cualquier Opacity para que funcione).
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              builder: (context, t, _) => BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 7 * t, sigmaY: 7 * t),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Padding(
            padding: MediaQuery.of(context).viewInsets,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.96 + 0.04 * t,
                      child: child,
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Material(
                      color: Colors.white,
                      elevation: 24,
                      shadowColor: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(editing),
                          const Divider(height: 1, color: _kBorderSoft),
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: _buildForm(),
                            ),
                          ),
                          const Divider(height: 1, color: _kBorderSoft),
                          _buildFooter(editing),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool editing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 12, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kBlueSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing ? 'Editar representante' : 'Nuevo representante',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkNavy,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Se agregará al estudiante que estás registrando.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: _autoVal
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row2(
            _CedulaField(
              controller: _ced,
              focusNode: _cedFocus,
              checking: _checking,
              prefix: _prefix,
              validator: _validateCed,
              onChanged: (_) {
                if (_locked) _unlock();
                if (_checkError != null) setState(() => _checkError = null);
                _timer?.cancel();
                if (_ced.text.trim().length >= 5) {
                  _timer = Timer(const Duration(milliseconds: 600), _check);
                }
              },
              onPrefixChanged: (p) {
                setState(() {
                  _prefix = p;
                  if (p != 'J-') {
                    _ced.text = _ced.text.replaceAll(RegExp(r'\D'), '');
                  }
                });
                _check();
              },
            ),
            TextFormField(
              controller: _tel,
              readOnly: _locked,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
              ],
              decoration: _dec(
                'Teléfono',
                hint: '0414-1234567',
                icon: Icons.phone_outlined,
                locked: _locked,
              ),
            ),
          ),
          if (_checkError != null) ...[
            const SizedBox(height: 8),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: _kAmber),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No se pudo comprobar si este representante ya está '
                    'registrado en el colegio.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _kAmber,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (_locked) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kBlueSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 16,
                    color: AppColors.primaryBlue,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Este representante ya está registrado en el colegio. '
                      'Sus datos se cargaron y no se editan aquí; '
                      'solo indica el parentesco.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _Row2(
            TextFormField(
              controller: _nom,
              readOnly: _locked,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _dec('Nombres *', locked: _locked),
              validator: _req,
            ),
            TextFormField(
              controller: _ap,
              readOnly: _locked,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _dec('Apellidos *', locked: _locked),
              validator: _req,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            readOnly: _locked,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: _dec(
              'Correo electrónico',
              icon: Icons.mail_outline_rounded,
              locked: _locked,
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: 18),
          const Text(
            'Parentesco',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _kParentescos)
                ChoiceChip(
                  label: Text(_cap(p)),
                  selected: _parentesco == p,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _parentesco = p),
                  backgroundColor: Colors.white,
                  selectedColor: _kBlueSoft,
                  side: BorderSide(
                    color: _parentesco == p ? AppColors.primaryBlue : _kBorder,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _parentesco == p
                        ? AppColors.primaryBlue
                        : AppColors.darkNavy,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: _kSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeTrackColor: AppColors.primaryBlue,
              title: const Text(
                'Responsable de pagos',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkNavy,
                ),
              ),
              subtitle: const Text(
                'Marca a quien se encarga de los pagos del estudiante.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              value: _financiero,
              onChanged: (v) => setState(() => _financiero = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool editing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: _outlineBtn(),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            style: _primaryBtn(),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(
              editing ? 'Guardar cambios' : 'Añadir representante',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
