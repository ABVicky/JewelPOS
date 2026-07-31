import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'db.dart';

class TSPLPrinter {
  /// Build 38mm x 25mm Label Document Bytes in exact layout format
  static Future<Uint8List> generateLabelPdfBytes(InventoryItem item) async {
    final pdf = pw.Document();

    final pageFormat = PdfPageFormat(
      38 * PdfPageFormat.mm,
      25 * PdfPageFormat.mm,
      marginAll: 1.5 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Row 1: Item Name & Category
              pw.Text(
                '${item.itemName} (${item.category})',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                maxLines: 1,
              ),
              // Row 2: Purity & Weight
              pw.Text(
                'Pur: ${item.purity}  Wt: ${item.weight.toStringAsFixed(4)} g',
                style: const pw.TextStyle(fontSize: 7),
                maxLines: 1,
              ),
              pw.SizedBox(height: 1),
              // Row 3-4: Code128 Barcode & Barcode ID Text
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: item.barcode,
                  width: 95,
                  height: 24,
                  drawText: true,
                  textStyle: const pw.TextStyle(fontSize: 6),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Print label directly to connected Windows printer in given format and layout
  static Future<bool> sendTSPLToPrinter(InventoryItem item) async {
    if (kIsWeb) {
      debugPrint('Label printed (Web Simulation)');
      return true;
    }

    try {
      final pdfBytes = await generateLabelPdfBytes(item);
      final printers = await Printing.listPrinters();

      Printer? targetPrinter;
      if (printers.isNotEmpty) {
        targetPrinter = printers.firstWhere(
          (p) => p.isDefault,
          orElse: () => printers.first,
        );
      }

      if (targetPrinter != null) {
        return await Printing.directPrintPdf(
          printer: targetPrinter,
          onLayout: (PdfPageFormat format) async => pdfBytes,
          format: PdfPageFormat(
            38 * PdfPageFormat.mm,
            25 * PdfPageFormat.mm,
            marginAll: 1.5 * PdfPageFormat.mm,
          ),
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'JewelPOS_Label_${item.barcode}',
          format: PdfPageFormat(
            38 * PdfPageFormat.mm,
            25 * PdfPageFormat.mm,
            marginAll: 1.5 * PdfPageFormat.mm,
          ),
        );
        return true;
      }
    } catch (e) {
      debugPrint('Direct printer exception: $e');
      return false;
    }
  }
}
