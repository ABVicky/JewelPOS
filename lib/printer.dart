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
              // Row 1: Item Name & Category (Bold & Clear)
              pw.Text(
                '${item.itemName} (${item.category})',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
                maxLines: 1,
              ),
              // Row 2: Purity & Weight (Bold & Clear)
              pw.Text(
                'Pur: ${item.purity}  Wt: ${item.weight.toStringAsFixed(4)} g',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
                maxLines: 1,
              ),
              pw.SizedBox(height: 1),
              // Row 3-4: Code128 Barcode & Barcode ID Text (Bold & Clear)
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: item.barcode,
                  width: 100,
                  height: 26,
                  drawText: true,
                  textStyle: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Directly opens Windows Native Printing Window with 38mm x 25mm setup
  static Future<bool> sendTSPLToPrinter(InventoryItem item) async {
    if (kIsWeb) {
      debugPrint('Label printed (Web Simulation)');
      return true;
    }

    try {
      final pdfBytes = await generateLabelPdfBytes(item);
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
    } catch (e) {
      debugPrint('Printing layout exception: $e');
      return false;
    }
  }
}
