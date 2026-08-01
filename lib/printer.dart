import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'db.dart';

class TSPLPrinter {
  /// Build 38mm x 25mm Label Document Bytes in exact layout format for a single item
  static Future<Uint8List> generateLabelPdfBytes(InventoryItem item) async {
    return generateMultipleLabelsPdfBytes([item]);
  }

  /// Build multi-page 38mm x 25mm Label Document Bytes for multiple selected items
  static Future<Uint8List> generateMultipleLabelsPdfBytes(List<InventoryItem> items) async {
    final pdf = pw.Document();

    final pageFormat = PdfPageFormat(
      38 * PdfPageFormat.mm,
      25 * PdfPageFormat.mm,
      marginAll: 1.5 * PdfPageFormat.mm,
    );

    for (var item in items) {
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
                    width: 95,
                    height: 28,
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
    }

    return pdf.save();
  }

  /// Directly opens Windows Native Printing Window for a single item
  static Future<bool> sendTSPLToPrinter(InventoryItem item) async {
    return sendMultipleTSPLToPrinter([item]);
  }

  /// Directly opens Windows Native Printing Window for multiple selected items in a single print job
  static Future<bool> sendMultipleTSPLToPrinter(List<InventoryItem> items) async {
    if (items.isEmpty) return false;

    if (kIsWeb) {
      debugPrint('Batch labels printed (${items.length} items)');
      return true;
    }

    try {
      final pdfBytes = await generateMultipleLabelsPdfBytes(items);
      final jobName = items.length == 1
          ? 'JewelPOS_Label_${items.first.barcode}'
          : 'JewelPOS_Batch_Labels_${items.length}_items';

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: jobName,
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
