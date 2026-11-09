import '../domain/billing_concept.dart';

/// Contrato de datos de conceptos de cobro, independiente de Supabase.
///
/// Los errores se lanzan como `BillingRepositoryException`
/// (definida en billing_repository.dart).
abstract class ConceptRepository {
  Future<List<BillingConcept>> list({required String colegioId});

  Future<BillingConcept> create({
    required String colegioId,
    required String nombre,
    required double montoUsd,
    required int diaVencimiento,
  });

  Future<BillingConcept> update({
    required String id,
    required String nombre,
    required double montoUsd,
    required int diaVencimiento,
    required bool activo,
  });

  /// Activa o desactiva un concepto sin modificar el resto de sus datos.
  Future<void> setActive({required String id, required bool activo});

  /// Versiones anteriores del concepto, la más reciente primero.
  Future<List<BillingConceptVersion>> history({required String conceptoId});
}
