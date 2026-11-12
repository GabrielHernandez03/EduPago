/// Datos bancarios del colegio. TODO: mover a una tabla por colegio.
class ColegioDatosPago {
  static const Map<String, String> pagoMovil = {
    'Banco': 'Mercantil (0105)',
    'RIF': 'J-30062942-0',
    'Teléfono': '0412-3456789',
    'Titular': 'U.E. Nueva Generación',
  };
  static const Map<String, String> zelle = {
    'Correo': 'pagos@nuevageneracion.edu.ve',
    'Titular': 'U.E. Nueva Generación Inc.',
  };
  static const Map<String, String> transferencia = {
    'Banco': 'Mercantil',
    'Cuenta': '0105-0123-45-6789012345',
    'RIF': 'J-30062942-0',
    'Titular': 'U.E. Nueva Generación',
  };
}