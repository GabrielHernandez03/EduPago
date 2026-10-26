import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';

class PaymentReconciliationWidget extends StatefulWidget {
  final String colegioId;
  final VoidCallback? onPaymentProcessed;

  const PaymentReconciliationWidget({
    super.key,
    required this.colegioId,
    this.onPaymentProcessed,
  });

  @override
  State<PaymentReconciliationWidget> createState() =>
      _PaymentReconciliationWidgetState();
}

class _PaymentReconciliationWidgetState
    extends State<PaymentReconciliationWidget> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _pendingPayments = [];
  bool _isLoading = true;
  String? _filterStatus = 'pendiente';

  @override
  void initState() {
    super.initState();
    _fetchPayments();
  }

  Future<void> _fetchPayments() async {
    setState(() => _isLoading = true);
    try {
      var query = _supabase.from('pagos').select('''
        id,
        colegio_id,
        representante_id,
        monto,
        moneda,
        tasa_aplicada,
        monto_usd_equivalente,
        metodo,
        referencia,
        banco_origen,
        fecha_pago,
        comprobante_path,
        estado,
        motivo_rechazo,
        creado_at,
        representantes (
          nombres,
          apellidos,
          cedula
        )
      ''');

      if (_filterStatus != 'todos') {
        query = query.eq('estado', _filterStatus!);
      }

      final response = await query.order('creado_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingPayments = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando pagos para conciliación: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approvePayment(Map<String, dynamic> pago) async {
    final String pagoId = pago['id'].toString();
    final user = _supabase.auth.currentUser;

    try {
      // Solo se cambia el estado del pago. El trigger de base de datos
      // (fn_conciliar_cuota_al_aprobar_pago) aplica el monto por FIFO a las
      // cuotas de todos los hijos del representante y registra cada abono en
      // pago_aplicaciones. Si sobra dinero queda como saldo a favor.
      // .select() devuelve las filas realmente actualizadas: si viene vacío,
      // la base de datos bloqueó el cambio (p. ej. por permisos/RLS).
      final updated = await _supabase
          .from('pagos')
          .update({
            'estado': 'aprobado',
            'revisado_por': user?.id,
            'revisado_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', pagoId)
          .select('id');

      if ((updated as List).isEmpty) {
        throw Exception(
          'La base de datos no actualizó el pago (revisa permisos/RLS de la tabla pagos).',
        );
      }

      if (!mounted) return;

      // Quita el pago de la lista al instante y luego recarga desde la BD.
      setState(() {
        _pendingPayments.removeWhere((p) => p['id'].toString() == pagoId);
      });
      widget.onPaymentProcessed?.call(); // Recarga las métricas del Dashboard
      _fetchPayments();

      await _showApprovedDialog(pago);
    } catch (e) {
      debugPrint('Error al aprobar el pago: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al aprobar el pago: $e'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  /// Diálogo de confirmación que se muestra tras aprobar un pago.
  Future<void> _showApprovedDialog(Map<String, dynamic> pago) {
    final rep = pago['representantes'];
    final String nombre = rep is Map
        ? '${rep['nombres'] ?? ''} ${rep['apellidos'] ?? ''}'.trim()
        : '';
    final num monto = (pago['monto'] as num?) ?? 0;
    final num usd = (pago['monto_usd_equivalente'] as num?) ?? 0;
    final String moneda = (pago['moneda'] ?? '').toString();

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Color(0xFF16A34A),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '¡Pago aprobado!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (nombre.isNotEmpty)
              Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Referencia: ${pago['referencia'] ?? '-'}'),
            Text('Monto: ${monto.toStringAsFixed(2)} $moneda'),
            Text('Equivalente: \$${usd.toStringAsFixed(2)} USD'),
            const SizedBox(height: 12),
            const Text(
              'Se aplicó a las cuotas más antiguas. Cualquier excedente '
              'queda como saldo a favor del representante.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectPaymentDialog(String pagoId) async {
    final TextEditingController motivoController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              'Rechazar Pago',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Indica el motivo por el cual rechazas este comprobante. El representante podrá ver esta observación.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: motivoController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText:
                      'Ej. Referencia no encontrada en la cuenta bancaria...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'El motivo de rechazo es obligatorio';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar Rechazo'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final user = _supabase.auth.currentUser;
      try {
        await _supabase
            .from('pagos')
            .update({
              'estado': 'rechazado',
              'motivo_rechazo': motivoController.text.trim(),
              'revisado_por': user?.id,
              'revisado_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', pagoId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pago marcado como rechazado.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
          _fetchPayments();
          widget.onPaymentProcessed
              ?.call(); // <-- Notifica al Dashboard principal
        }
      } catch (e) {
        _showErrorSnackBar('Error al rechazar el pago: $e');
      }
    }
  }

  /// Devuelve una URL firmada y temporal para ver el comprobante.
  /// Acepta la ruta del archivo (formato nuevo) o la URL pública completa que
  /// guardaban los registros antiguos. El bucket debe ser privado.
  Future<String?> _resolveComprobanteUrl(String stored) async {
    if (stored.isEmpty) return null;
    String path = stored;
    final legacy = RegExp(
      r'/storage/v1/object/(?:public|sign|authenticated)/comprobantes/',
    ).firstMatch(stored);
    if (legacy != null) {
      path = Uri.decodeComponent(stored.substring(legacy.end).split('?').first);
    }
    try {
      return await _supabase.storage
          .from('comprobantes')
          .createSignedUrl(path, 300);
    } catch (e) {
      debugPrint('No se pudo firmar el comprobante: $e');
      // Último recurso para registros antiguos con bucket aún público.
      return stored.startsWith('http') ? stored : null;
    }
  }

  void _showDetailModal(Map<String, dynamic> pago) {
    final String repNombre = pago['representantes'] != null
        ? '${pago['representantes']['nombres']} ${pago['representantes']['apellidos']}'
        : 'Representante no identificado';
    final String repCedula = pago['representantes']?['cedula'] ?? 'N/A';
    final String comprobanteUrl = pago['comprobante_path'] ?? '';
    final bool isPdf = comprobanteUrl.toLowerCase().contains('.pdf');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 540,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Detalle de Comprobante',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkNavy,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              _buildDetailRow('Representante', '$repNombre (C.I. $repCedula)'),
              _buildDetailRow(
                'Método de pago',
                pago['metodo'].toString().toUpperCase(),
              ),
              _buildDetailRow(
                'Banco Origen',
                pago['banco_origen'] ?? 'No especificado',
              ),
              _buildDetailRow(
                'Número de Referencia',
                pago['referencia'] ?? 'N/A',
              ),
              _buildDetailRow(
                'Monto Reportado',
                '${pago['moneda']} ${pago['monto']}',
              ),
              _buildDetailRow(
                'Equivalente USD',
                '\$${(pago['monto_usd_equivalente'] as num?)?.toStringAsFixed(2)} USD',
              ),
              _buildDetailRow('Fecha de Reporte', pago['fecha_pago'] ?? ''),
              const SizedBox(height: 16),
              const Text(
                'Soporte / Comprobante:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: comprobanteUrl.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin imagen de comprobante adjunta',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : FutureBuilder<String?>(
                        future: _resolveComprobanteUrl(comprobanteUrl),
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final String? url = snap.data;
                          if (url == null) {
                            return const Center(
                              child: Text('No se pudo cargar el comprobante'),
                            );
                          }
                          if (isPdf) {
                            return const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.picture_as_pdf,
                                    color: Colors.red,
                                    size: 48,
                                  ),
                                  SizedBox(height: 8),
                                  Text('Documento PDF adjunto'),
                                ],
                              ),
                            );
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              errorBuilder: (c, e, s) => const Center(
                                child: Text('No se pudo cargar la imagen'),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 20),
              if (pago['estado'] == 'pendiente')
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _rejectPaymentDialog(pago['id'].toString());
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Rechazar'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _approvePayment(pago);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Aprobar Pago'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.darkNavy,
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      color: AppColors.primaryBlue,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Conciliación de Pagos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ],
                ),
                DropdownButton<String>(
                  value: _filterStatus,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: 'pendiente',
                      child: Text('Pendientes de revisión'),
                    ),
                    DropdownMenuItem(
                      value: 'aprobado',
                      child: Text('Aprobados'),
                    ),
                    DropdownMenuItem(
                      value: 'rechazado',
                      child: Text('Rechazados'),
                    ),
                    DropdownMenuItem(
                      value: 'todos',
                      child: Text('Todos los registros'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _filterStatus = val);
                      _fetchPayments();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_pendingPayments.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                width: double.infinity,
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: Colors.green.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _filterStatus == 'pendiente'
                          ? '¡Al día! No hay pagos pendientes por conciliar.'
                          : 'No se encontraron registros.',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pendingPayments.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final pago = _pendingPayments[index];
                  final String repNombre = pago['representantes'] != null
                      ? '${pago['representantes']['nombres']} ${pago['representantes']['apellidos']}'
                      : 'Representante';
                  final String status = pago['estado'] ?? 'pendiente';

                  Color badgeColor = Colors.orange;
                  if (status == 'aprobado')
                    badgeColor = const Color(0xFF059669);
                  if (status == 'rechazado') badgeColor = Colors.redAccent;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: badgeColor.withOpacity(0.1),
                      child: Icon(
                        status == 'aprobado'
                            ? Icons.check
                            : (status == 'rechazado'
                                  ? Icons.close
                                  : Icons.access_time),
                        color: badgeColor,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '$repNombre — ${pago['referencia']}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${pago['metodo'].toString().toUpperCase()} • ${pago['fecha_pago']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${pago['moneda']} ${pago['monto']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.darkNavy,
                              ),
                            ),
                            Text(
                              '\$${(pago['monto_usd_equivalente'] as num?)?.toStringAsFixed(2)} USD',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(
                            Icons.visibility_outlined,
                            color: AppColors.primaryBlue,
                          ),
                          onPressed: () => _showDetailModal(pago),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
