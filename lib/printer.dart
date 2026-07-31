import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'db.dart';

class TSPLPrinter {
  /// Build TSPL command string for HPRT HT800 label printer (38mm x 25mm)
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

  /// Automatically fetch list of all installed Windows USB printers
  static Future<List<String>> getInstalledWindowsPrinters() async {
    if (kIsWeb || !Platform.isWindows) return [];
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

  /// Sends raw TSPL commands to Windows Installed Printer Driver by Name, USB COM Port, or TCP Socket
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
    final bytes = utf8.encode(tsplStr);

    if (Platform.isWindows) {
      // 1. Try Named Windows Printer Driver (e.g. "HPRT HT800", "HPRT", "HT800")
      final List<String> targetNames = [];
      if (usbPortName != null && usbPortName.trim().isNotEmpty) {
        targetNames.add(usbPortName.trim());
      }
      
      // Auto-detect installed printers if targetNames is empty or generic
      try {
        final installedPrinters = await getInstalledWindowsPrinters();
        for (var p in installedPrinters) {
          if (!targetNames.contains(p)) {
            // Prioritize HPRT or thermal printer names
            if (p.toLowerCase().contains('hprt') || p.toLowerCase().contains('label') || p.toLowerCase().contains('pos') || p.toLowerCase().contains('tsc')) {
              targetNames.insert(0, p);
            } else {
              targetNames.add(p);
            }
          }
        }
      } catch (_) {}

      // Add common COM / LPT serial ports
      targetNames.addAll([
        'COM3', 'COM1', 'COM2', 'COM4', 'COM5', 'COM6', 'LPT1', 'PRN'
      ]);

      for (var target in targetNames) {
        try {
          final tempFile = File('${Directory.systemTemp.path}\\label_${DateTime.now().millisecondsSinceEpoch}.tspl');
          await tempFile.writeAsBytes(bytes);

          // Attempt PowerShell Out-Printer by Installed Printer Name
          final psResult = await Process.run('powershell', [
            '-Command',
            "Get-Content '${tempFile.path}' | Out-Printer -Name '$target'"
          ]);

          if (psResult.exitCode == 0) {
            try { await tempFile.delete(); } catch (_) {}
            return true;
          }

          // Attempt Windows Raw Copy to Printer Spooler Name or COM port
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

    // 2. Try Network TCP Socket Connection (Ethernet / WiFi / USB Virtual IP)
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {}

    return false;
  }
}
