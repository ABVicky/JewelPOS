import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'db.dart';

class TSPLPrinter {
  /// Build TSPL command string for TSPL Direct Raw printers (38mm x 25mm)
  static String buildTSPLCommand(InventoryItem item) {
    final buffer = StringBuffer();
    buffer.writeln('SIZE 38 mm, 25 mm');
    buffer.writeln('GAP 2 mm, 0 mm');
    buffer.writeln('DIRECTION 1');
    buffer.writeln('CLS');
    buffer.writeln('TEXT 15,10,"2",0,1,1,"${item.itemName} (${item.category})"');
    buffer.writeln('TEXT 15,38,"2",0,1,1,"Pur: ${item.purity}  Wt: ${item.weight.toStringAsFixed(4)} g"');
    buffer.writeln('BARCODE 15,68,"128",55,1,0,2,2,"${item.barcode}"');
    buffer.writeln('PRINT 1,1');
    return buffer.toString();
  }

  /// Build 38mm x 25mm Label Document Bytes for Windows Driver Printing
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
              pw.Text(
                '${item.itemName} (${item.category})',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                maxLines: 1,
              ),
              pw.Text(
                'Pur: ${item.purity}  Wt: ${item.weight.toStringAsFixed(4)} g',
                style: const pw.TextStyle(fontSize: 7),
                maxLines: 1,
              ),
              pw.SizedBox(height: 1),
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

  /// Opens native Windows Print Dialog (Win + P equivalent) for label printing
  static Future<void> layoutPdf(InventoryItem item) async {
    final bytes = await generateLabelPdfBytes(item);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: 'JewelPOS_Label_${item.barcode}',
      format: PdfPageFormat(
        38 * PdfPageFormat.mm,
        25 * PdfPageFormat.mm,
        marginAll: 1.5 * PdfPageFormat.mm,
      ),
    );
  }

  /// Automatically fetch list of all installed Windows USB printers
  static Future<List<String>> getInstalledWindowsPrinters() async {
    if (kIsWeb || !Platform.isWindows) return [];
    try {
      final printers = await Printing.listPrinters();
      return printers.map((p) => p.name).toList();
    } catch (_) {}
    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-Printer | Select-Object -ExpandProperty Name'
      ]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        return lines;
      }
    } catch (_) {}
    return [];
  }

  /// Sends label print job to Windows Installed Printer Driver (HPRT HT800) or TCP Socket
  static Future<bool> sendTSPLToPrinter(
    InventoryItem item, {
    required String host,
    required int port,
    String? usbPortName,
  }) async {
    if (kIsWeb) {
      debugPrint('TSPL Label generated (Web Simulation):\n${buildTSPLCommand(item)}');
      return true;
    }

    final tsplStr = buildTSPLCommand(item);
    final rawBytes = utf8.encode(tsplStr);

    if (Platform.isWindows) {
      // 1. Primary: Native Windows C++ Printer Driver Integration (Works on HPRT HT800 Driver)
      try {
        final pdfBytes = await generateLabelPdfBytes(item);
        final printers = await Printing.listPrinters();
        Printer? targetPrinter;

        if (usbPortName != null && usbPortName.trim().isNotEmpty) {
          final query = usbPortName.trim().toLowerCase();
          for (var p in printers) {
            if (p.name.toLowerCase().contains(query)) {
              targetPrinter = p;
              break;
            }
          }
        }

        if (targetPrinter == null && printers.isNotEmpty) {
          for (var p in printers) {
            final lower = p.name.toLowerCase();
            if (lower.contains('hprt') || lower.contains('label') || lower.contains('pos') || lower.contains('tsc') || lower.contains('barcode')) {
              targetPrinter = p;
              break;
            }
          }
          targetPrinter ??= printers.firstWhere((p) => p.isDefault, orElse: () => printers.first);
        }

        if (targetPrinter != null) {
          final bool printed = await Printing.directPrintPdf(
            printer: targetPrinter,
            onLayout: (PdfPageFormat format) async => pdfBytes,
            format: PdfPageFormat(
              38 * PdfPageFormat.mm,
              25 * PdfPageFormat.mm,
              marginAll: 1.5 * PdfPageFormat.mm,
            ),
          );
          if (printed) return true;
        }
      } catch (e) {
        debugPrint('Windows Printing.directPrintPdf failed: $e');
      }

      // 2. Secondary: Raw Serial / Spool Targets for direct TSPL printers
      final List<String> targetNames = [];
      if (usbPortName != null && usbPortName.trim().isNotEmpty) {
        targetNames.add(usbPortName.trim());
      }
      targetNames.addAll([
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8',
        '\\\\.\\COM1', '\\\\.\\COM2', '\\\\.\\COM3', '\\\\.\\COM4', '\\\\.\\COM5',
        'LPT1', 'PRN'
      ]);

      for (var target in targetNames) {
        try {
          final tempFile = File('${Directory.systemTemp.path}\\raw_copy.tspl');
          await tempFile.writeAsBytes(rawBytes);

          final rawResult = await Process.run('cmd.exe', [
            '/c',
            'copy',
            '/b',
            tempFile.path,
            target.startsWith('COM') || target.startsWith('LPT') ? target : "\\\\localhost\\$target"
          ]);

          try { await tempFile.delete(); } catch (_) {}

          if (rawResult.exitCode == 0) {
            return true;
          }
        } catch (_) {}
      }
    }

    // 3. Network TCP Socket Connection (Ethernet / WiFi / USB Virtual IP)
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
      socket.add(rawBytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {}

    return false;
  }
}
