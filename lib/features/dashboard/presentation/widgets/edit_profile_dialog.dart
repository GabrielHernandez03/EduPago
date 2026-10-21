import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../main.dart';

class EditProfileDialog extends StatefulWidget {
  final String fullName;
  final String cedula;
  final String phone;
  final String address;
  final String email;
  final VoidCallback? onSaveSuccess;

  const EditProfileDialog({
    super.key,
    required this.fullName,
    required this.cedula,
    required this.phone,
    required this.address,
    required this.email,
    this.onSaveSuccess,
  });

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  final _phoneFocus = FocusNode();
  final _addressFocus = FocusNode();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(
      text: _formatPhone(_extractLocalDigits(widget.phone)),
    );
    _addressController = TextEditingController(text: widget.address);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    _phoneFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  /// Intenta actualizar la fila de `representantes` usando [column] = [value].
  /// Devuelve true solo si realmente se modificó al menos una fila
  /// (evita el falso "éxito" cuando el filtro no coincide o RLS bloquea).
  Future<bool> _tryUpdate(
    Map<String, dynamic> data,
    String column,
    String value,
  ) async {
    final result = await supabase
        .from('representantes')
        .update(data)
        .eq(column, value)
        .select();
    return result.isNotEmpty;
  }

  Future<void> _handleSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No hay una sesión activa');
      }

      final data = {
        'telefono_whatsapp':
            '+58${_phoneController.text.replaceAll(RegExp(r'\D'), '')}',
        'direccion': _addressController.text.trim(),
      };

      // 1) Por perfil_id (el más confiable), 2) por cédula, 3) por email.
      bool updated = await _tryUpdate(data, 'perfil_id', user.id);

      if (!updated &&
          widget.cedula.isNotEmpty &&
          widget.cedula != 'Sin cédula') {
        updated = await _tryUpdate(data, 'cedula', widget.cedula);
      }

      if (!updated && widget.email.isNotEmpty) {
        updated = await _tryUpdate(data, 'email', widget.email);
      }

      if (!updated) {
        throw Exception(
          'No se encontró tu registro de representante o no tienes permiso para editarlo',
        );
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      navigator.pop();
      widget.onSaveSuccess?.call();

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado exitosamente'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al actualizar datos: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 480;
    final horizontalInset = isCompact ? 12.0 : 24.0;
    final availableWidth = size.width - (horizontalInset * 2);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 16,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        // Máximo 440 px, pero se encoge en pantallas angostas
        width: availableWidth < 440 ? availableWidth : 440,
        constraints: BoxConstraints(maxHeight: size.height * 0.95),
        padding: EdgeInsets.all(isCompact ? 16 : 20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Encabezado compacto: ícono + título + cerrar en una sola fila
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: AppColors.primaryBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Editar perfil',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkNavy,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Solo puedes editar tus datos de contacto.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // --- Datos bloqueados ---
                _buildLabel('Nombre completo'),
                const SizedBox(height: 4),
                _buildDisabledField(widget.fullName),
                const SizedBox(height: 10),

                _buildLabel('Cédula de identidad'),
                const SizedBox(height: 4),
                _buildDisabledField(widget.cedula),
                const SizedBox(height: 10),

                _buildLabel('Correo electrónico'),
                const SizedBox(height: 4),
                _buildDisabledField(
                  widget.email.isNotEmpty ? widget.email : 'Sin correo',
                ),
                const SizedBox(height: 10),

                // --- Datos editables ---
                _buildLabel('Número de teléfono'),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _addressFocus.requestFocus(),
                  inputFormatters: [_PhoneNumberFormatter()],
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.darkNavy,
                  ),
                  decoration: _inputDecoration('412 555 0174').copyWith(
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 14, right: 12),
                      child: Text(
                        '+58',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkNavy,
                        ),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                  ),
                  validator: (value) {
                    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.isEmpty) return 'El teléfono es obligatorio';
                    if (digits.length != 10 || !digits.startsWith('4')) {
                      return 'Formato válido: 412 555 0174';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                _buildLabel('Dirección'),
                const SizedBox(height: 4),
                // Enter en la dirección guarda (sin insertar salto de línea)
                Focus(
                  onKeyEvent: (node, event) {
                    final isEnter =
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter;
                    if (isEnter) {
                      if (event is KeyDownEvent && !_isLoading) _handleSave();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextFormField(
                    controller: _addressController,
                    focusNode: _addressFocus,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.streetAddress,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
                    ],
                    onFieldSubmitted: (_) {
                      if (!_isLoading) _handleSave();
                    },
                    minLines: 1,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.darkNavy,
                    ),
                    decoration: _inputDecoration(
                      'Ingresa tu dirección',
                      icon: Icons.location_on_outlined,
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'La dirección es obligatoria';
                      if (text.length < 5) return 'La dirección es muy corta';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Guardar cambios',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppColors.darkNavy,
      ),
    );
  }

  Widget _buildDisabledField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: AppColors.textMuted)
          : null,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      errorStyle: const TextStyle(fontSize: 11),
    );
  }
}

/// Deja solo los 10 dígitos locales: quita "+58", "58" o el "0" inicial.
/// "+584125550174" / "04125550174" / "412 555 0174" -> "4125550174"
String _extractLocalDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('58') && digits.length > 10) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

/// "4125550174" -> "412 555 0174"
String _formatPhone(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i == 3 || i == 6) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formatea mientras se escribe: solo números, máximo 10, en grupos 3-3-4.
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _extractLocalDigits(newValue.text);
    final formatted = _formatPhone(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
