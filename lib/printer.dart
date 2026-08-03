/*
 * Designed and Developed by Manikarnika Technologies
 * Website: https://www.manikarnikatechnologies.in
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  maxLines: 1,
                ),
                // Row 2: Purity & Weight (Bold & Clear)
                pw.Text(
                  'Pur: ${item.purity}  Wt: ${item.weight.toStringAsFixed(3)} g',
                  style: pw.TextStyle(
                    fontSize: 8,
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

  /// Generate standard receipt PDF with jewel_logo.png header at the top
  static Future<Uint8List> generateReceiptPdfBytes(List<Map<String, dynamic>> items) async {
    final pdf = pw.Document();
    pw.MemoryImage? logoImage;

    try {
      final logoData = await rootBundle.load('assets/images/jewel_logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error loading jewel_logo.png for PDF receipt: $e');
    }

    final pageFormat = PdfPageFormat(
      58 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );

    double totalWeight = 0.0;
    for (var item in items) {
      totalWeight += (item['weight'] as num?)?.toDouble() ?? 0.0;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.Center(
                  child: pw.Image(logoImage, width: 100),
                ),
                pw.SizedBox(height: 4),
              ],
              pw.Text('JEWEL POS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Item Name', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Weight', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Divider(thickness: 0.5),
              ...items.map((item) {
                final name = (item['itemName'] ?? '').toString();
                final wt = (item['weight'] as num?)?.toDouble() ?? 0.0;
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        name.length > 18 ? name.substring(0, 18) : name,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                    pw.Text('${wt.toStringAsFixed(3)} g', style: const pw.TextStyle(fontSize: 8)),
                  ],
                );
              }),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Items:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${items.length}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Weight:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${totalWeight.toStringAsFixed(3)} g', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),
              pw.Text('Thank You', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Generate Day-Wise End of Day Report PDF Document with jewel_logo.png header
  static Future<Uint8List> generateDailyReportPdfBytes(String date, List<PrintLog> logs) async {
    final pdf = pw.Document();
    pw.MemoryImage? logoImage;

    try {
      final logoData = await rootBundle.load('assets/images/jewel_logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error loading jewel_logo.png for Daily Report PDF: $e');
    }

    final pageFormat = PdfPageFormat(
      58 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );

    int grandTotalItems = 0;
    double grandTotalWeight = 0.0;
    final Map<String, Map<String, dynamic>> terminalStats = {};

    for (var log in logs) {
      grandTotalItems += log.totalItems;
      grandTotalWeight += log.totalWeight;
      final termName = log.terminalName;
      if (!terminalStats.containsKey(termName)) {
        terminalStats[termName] = {'count': 0, 'items': 0, 'weight': 0.0};
      }
      terminalStats[termName]!['count'] = (terminalStats[termName]!['count'] as int) + 1;
      terminalStats[termName]!['items'] = (terminalStats[termName]!['items'] as int) + log.totalItems;
      terminalStats[termName]!['weight'] = (terminalStats[termName]!['weight'] as double) + log.totalWeight;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.Center(
                  child: pw.Image(logoImage, width: 100),
                ),
                pw.SizedBox(height: 4),
              ],
              pw.Text('JEWEL POS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('END OF DAY REPORT', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Date:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text(date, style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Receipts:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${logs.length}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Items Billed:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('$grandTotalItems', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Net Weight:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${grandTotalWeight.toStringAsFixed(3)} g', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),
              if (terminalStats.isNotEmpty) ...[
                pw.Text('TERMINAL BREAKDOWN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Divider(thickness: 0.5),
                ...terminalStats.entries.map((e) {
                  final tName = e.key;
                  final tCount = e.value['count'];
                  final tWt = (e.value['weight'] as double).toStringAsFixed(3);
                  return pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text('$tName ($tCount receipts)', style: const pw.TextStyle(fontSize: 7.5)),
                      ),
                      pw.Text('$tWt g', style: const pw.TextStyle(fontSize: 7.5)),
                    ],
                  );
                }),
                pw.Text('================================', style: const pw.TextStyle(fontSize: 8)),
              ],
              pw.SizedBox(height: 4),
              pw.Text('Thank You', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
