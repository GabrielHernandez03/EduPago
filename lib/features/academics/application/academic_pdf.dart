import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/academic_repository.dart';

class AcademicPdf {
  static Future<Uint8List> build(AcademicRow bulletin) async {
    final document = pw.Document();
    final navy = PdfColor.fromHex('#10234C');
    final blue = PdfColor.fromHex('#246BFA');
    final notes = academicRows(bulletin['notas']);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 16),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: blue, width: 2)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${bulletin['colegio']}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: navy,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'BOLETÍN DE CALIFICACIONES',
                style: pw.TextStyle(fontSize: 12, color: blue),
              ),
            ],
          ),
        ),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'EduPago · Versión ${bulletin['version']}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                '${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 20),
          pw.Text(
            '${bulletin['estudiante']}',
            style: pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
              color: navy,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('C.I./Código: ${bulletin['cedula'] ?? 'No registrado'}'),
          pw.SizedBox(height: 6),
          pw.Text(
            'Grado: ${bulletin['grado']} · Sección: ${bulletin['seccion'] ?? ''}',
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Año escolar: ${bulletin['anio']} · Lapso: ${bulletin['lapso']}',
          ),
          pw.SizedBox(height: 22),
          pw.TableHelper.fromTextArray(
            headers: ['Materia', 'Docente', 'Nota / 20'],
            data: [
              for (final n in notes)
                [
                  n['materia'].toString(),
                  n['docente'].toString(),
                  n['nota'].toString(),
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 11),
            cellPadding: const pw.EdgeInsets.all(10),
            oddRowDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#EDF4FF'),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Publicado: ${bulletin['publicado_at']}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Identificador: ${bulletin['id']}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Este boletín refleja las calificaciones guardadas al momento de su publicación. '
            'Las correcciones posteriores requieren una nueva publicación.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<void> download(AcademicRow bulletin) async {
    await Printing.sharePdf(
      bytes: await build(bulletin),
      filename: 'boletin_${bulletin['id']}_v${bulletin['version']}.pdf',
    );
  }
}
