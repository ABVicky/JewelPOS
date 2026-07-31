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

    return pdf.save();
  }

  /// Fetch list of all installed Windows printer names
  static Future<List<String>> getInstalledWindowsPrinters() async {
    if (kIsWeb) return [];
    try {
      final printers = await Printing.listPrinters();
      return printers.map((p) => p.name).toList();
    } catch (_) {}
    return [];
  }

  /// Print label directly to saved printer in 1 click or open print window
  static Future<bool> sendTSPLToPrinter(
    InventoryItem item, {
    String? selectedPrinterName,
    bool showPrintDialog = false,
  }) async {
    if (kIsWeb) {
      debugPrint('Label printed (Web Simulation)');
      return true;
    }

    try {
      final pdfBytes = await generateLabelPdfBytes(item);
      final labelFormat = PdfPageFormat(
        38 * PdfPageFormat.mm,
        25 * PdfPageFormat.mm,
        marginAll: 1.5 * PdfPageFormat.mm,
      );

      // If user wants to open print dialog explicitly
      if (showPrintDialog) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'JewelPOS_Label_${item.barcode}',
          format: labelFormat,
        );
        return true;
      }

      // 1-Click Direct Print to Saved / Default Printer
      final printers = await Printing.listPrinters();
      Printer? targetPrinter;

      if (selectedPrinterName != null && selectedPrinterName.trim().isNotEmpty) {
        final query = selectedPrinterName.trim().toLowerCase();
        for (var p in printers) {
          if (p.name.toLowerCase().contains(query)) {
            targetPrinter = p;
            break;
          }
        }
      }

      if (targetPrinter == null && printers.isNotEmpty) {
        targetPrinter = printers.firstWhere(
          (p) => p.isDefault,
          orElse: () => printers.first,
        );
      }

      if (targetPrinter != null) {
        final printed = await Printing.directPrintPdf(
          printer: targetPrinter,
          onLayout: (PdfPageFormat format) async => pdfBytes,
          format: labelFormat,
        );
        if (printed) return true;
      }

      // Fallback if direct print was unhandled
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'JewelPOS_Label_${item.barcode}',
        format: labelFormat,
      );
      return true;
    } catch (e) {
      debugPrint('Printing exception: $e');
      return false;
    }
  }
}
