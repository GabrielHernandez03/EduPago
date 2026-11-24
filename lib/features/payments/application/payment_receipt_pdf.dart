import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../domain/reported_payment.dart';

class PaymentReceiptPdf {
  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _formatDateTime(DateTime? date) {
    if (date == null) return 'No disponible';
    final local = date.toLocal();
    return '${_two(local.day)}/${_two(local.month)}/${local.year} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _formatDateOnly(DateTime? date) {
    if (date == null) return 'No disponible';
    final local = date.toLocal();
    return '${_two(local.day)}/${_two(local.month)}/${local.year}';
  }

  static String _formatUsd(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '\$$whole,${parts[1]} USD';
  }

  static Future<Uint8List> build(
    ReportedPayment payment, {
    String? schoolName,
    String? representativeName,
  }) async {
    final document = pw.Document();
    final navy = PdfColor.fromHex('#10234C');
    final blue = PdfColor.fromHex('#246BFA');
    final green = PdfColor.fromHex('#16845A');
    final lightBg = PdfColor.fromHex('#F4F8FF');
    final border = PdfColor.fromHex('#D7E4FC');

    final resolvedSchool = (schoolName ??
            payment.raw['colegio_nombre']?.toString() ??
            payment.raw['nombre_colegio']?.toString() ??
            'EduPago · Gestión Escolar')
        .trim();

    final resolvedRep = (representativeName ??
            payment.raw['representante_nombre']?.toString() ??
            payment.raw['nombre_representante']?.toString() ??
            '')
        .trim();

    final receiptNumber = 'REC-${payment.shortId.toUpperCase()}';
    final approvedDate = payment.confirmedAt ?? payment.createdAt;
    final concepts = payment.quotaDetails.isNotEmpty
        ? payment.quotaDetails
        : [payment.installmentCardValue];

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 14),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: blue, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    resolvedSchool,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'COMPROBANTE DE PAGO APROBADO',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: blue,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#E6F6EF'),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'APROBADO',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: green,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Recibo N.º $receiptNumber',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Comprobante generado digitalmente por EduPago',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 18),

          // Bloque resumen de monto y fechas
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: lightBg,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: border),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (resolvedRep.isNotEmpty) ...[
                      pw.Text(
                        'Representante: $resolvedRep',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: navy,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                    ],
                    pw.Text(
                      'Fecha de aprobación: ${_formatDateTime(approvedDate)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Fecha de reporte: ${_formatDateTime(payment.createdAt)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    if (payment.paymentDate != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Fecha de operación: ${_formatDateOnly(payment.paymentDate)}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'MONTO PAGADO',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: blue,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      payment.displayAmount,
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: navy,
                      ),
                    ),
                    if (payment.amountUsdEquivalent > 0 &&
                        !payment.displayAmount.contains('USD')) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Equivalente: ${_formatUsd(payment.amountUsdEquivalent)}',
                        style: const pw.TextStyle(
                          fontSize: 9.5,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 18),

          // Datos de la operación
          pw.Text(
            'Datos de la operación',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: navy,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Método de pago', 'Banco / Canal', 'Referencia'],
            data: [
              [
                payment.method.isEmpty ? 'No especificado' : payment.method,
                payment.bank.isEmpty ? 'N/A' : payment.bank,
                payment.reference.isEmpty ? payment.shortId : payment.reference,
              ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 10,
            ),
            headerDecoration: pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.all(8),
          ),

          pw.SizedBox(height: 18),

          // Conceptos cancelados
          pw.Text(
            'Conceptos cancelados',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: navy,
            ),
          ),
          pw.SizedBox(height: 6),
          for (final item in concepts)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                '• $item',
                style: const pw.TextStyle(fontSize: 10.5),
              ),
            ),

          // Desglose por estudiante (si existe)
          if (payment.studentAllocations.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Distribución aplicada por estudiante',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: navy,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Estudiante', 'Cuotas', 'Monto aplicado'],
              data: [
                for (final alloc in payment.studentAllocations)
                  [
                    alloc.name,
                    '${alloc.quotaCount}',
                    alloc.amountUsd == null
                        ? 'No disponible'
                        : _formatUsd(alloc.amountUsd!),
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: pw.BoxDecoration(color: navy),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.all(8),
              oddRowDecoration: pw.BoxDecoration(color: lightBg),
            ),
          ],

          pw.SizedBox(height: 22),
          pw.Divider(color: border),
          pw.SizedBox(height: 6),
          pw.Text(
            'Identificador único de transacción (UUID): ${payment.id}',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Emitido el: ${_formatDateTime(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return document.save();
  }

  static Future<void> download(
    ReportedPayment payment, {
    String? schoolName,
    String? representativeName,
  }) async {
    final bytes = await build(
      payment,
      schoolName: schoolName,
      representativeName: representativeName,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'recibo_pago_${payment.shortId}.pdf',
    );
  }
}