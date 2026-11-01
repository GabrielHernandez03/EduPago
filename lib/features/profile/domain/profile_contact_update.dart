/// Petición de actualización de los ÚNICOS campos editables del representante.
/// La validación de formato también se realiza en el formulario; el backend
/// debe seguir aplicando autorización y validaciones propias.
class ProfileContactUpdate {
  ProfileContactUpdate({required String phone, required String address})
    : localPhone = extractLocalPhone(phone),
      address = address.trim() {
    if (localPhone.length != 10 || !localPhone.startsWith('4')) {
      throw const FormatException('Formato válido: 412 555 0174');
    }
    if (this.address.length < 5) {
      throw const FormatException('La dirección debe tener al menos 5 caracteres');
    }
  }

  final String localPhone;
  final String address;

  String get internationalPhone => '+58$localPhone';

  Map<String, dynamic> toMap() => {
    'telefono_whatsapp': internationalPhone,
    'direccion': address,
  };
}

/// Convierte +584125550174 / 04125550174 / 412 555 0174 en 4125550174.
String extractLocalPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('58') && digits.length > 10) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}
