import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/billing_concept.dart';
import 'billing_repository.dart';
import 'concept_repository.dart';

/// Implementación Supabase.
///
/// La autorización la imponen las políticas RLS (solo administrador de su
/// propio colegio) y la auditoría y el historial los generan triggers en la
/// base de datos. El cliente no inserta en `auditoria`.
class SupabaseConceptRepository implements ConceptRepository {
  SupabaseConceptRepository({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;

  final SupabaseClient client;

  static const _table = 'conceptos_cobro';

  @override
  Future<List<BillingConcept>> list({required String colegioId}) async {
    try {
      final rows = await client
          .from(_table)
          .select()
          .eq('colegio_id', colegioId)
          .order('nombre');
      return rows.map(BillingConcept.fromJson).toList();
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<BillingConcept> create({
    required String colegioId,
    required String nombre,
    required double montoUsd,
    required int diaVencimiento,
  }) async {
    try {
      final row = await client
          .from(_table)
          .insert({
            'colegio_id': colegioId,
            'nombre': nombre.trim(),
            'monto_usd': montoUsd,
            'dia_vencimiento': diaVencimiento,
            'activo': true,
          })
          .select()
          .single();
      return BillingConcept.fromJson(row);
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<BillingConcept> update({
    required String id,
    required String nombre,
    required double montoUsd,
    required int diaVencimiento,
    required bool activo,
  }) async {
    try {
      final row = await client
          .from(_table)
          .update({
            'nombre': nombre.trim(),
            'monto_usd': montoUsd,
            'dia_vencimiento': diaVencimiento,
            'activo': activo,
          })
          .eq('id', id)
          .select()
          .single();
      return BillingConcept.fromJson(row);
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> setActive({required String id, required bool activo}) async {
    try {
      await client
          .from(_table)
          .update({'activo': activo})
          .eq('id', id)
          .select()
          .single();
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<List<BillingConceptVersion>> history({
    required String conceptoId,
  }) async {
    try {
      final rows = await client
          .from('conceptos_cobro_historial')
          .select()
          .eq('concepto_id', conceptoId)
          .order('vigente_hasta', ascending: false);
      return rows.map(BillingConceptVersion.fromJson).toList();
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  BillingRepositoryException _translate(PostgrestException e) {
    debugPrint('Error PostgreSQL (${e.code}): ${e.message}');
    switch (e.code) {
      case '23505':
        return const BillingRepositoryException(
          'Ya existe un concepto con ese nombre.',
        );
      case '23514':
        return const BillingRepositoryException(
          'Los datos no son válidos. Revisa nombre, monto y día de vencimiento.',
        );
      case '42501':
      case 'PGRST116': // RLS bloqueó la fila: 0 filas devueltas
        return const BillingRepositoryException(
          'No tienes permiso para esta operación o el concepto no existe.',
        );
      default:
        return BillingRepositoryException(e.message);
    }
  }
}
