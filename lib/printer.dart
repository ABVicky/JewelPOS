import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'db.dart';

class TSPLPrinter {
  /// Build TSPL command string for HPRT HT800 label printer (38mm x 25mm)
  static String buildTSPLCommand(InventoryItem item) {
    final buffer = StringBuffer();
    buffer.writeln('SIZE 38 mm,25 mm');
    buffer.writeln('GAP 2 mm,0 mm');
    buffer.writeln('SPEED 3');
    buffer.writeln('DENSITY 10');
    buffer.writeln('DIRECTION 1');
    buffer.writeln('CLS');

    // Handle max length item name safely (truncate if > 22 chars to fit 304 dots printable area)
    String safeName = item.itemName.trim();
    if (safeName.length > 22) {
      safeName = safeName.substring(0, 22).trim();
    }

    // Format weight strictly to 3 decimal places (e.g. Wt:14.250g)
    final weightStr = 'Wt:${item.weight.toStringAsFixed(3)}g';

    // Format purity (e.g. 22K)
    final purityStr = item.purity.trim();

    buffer.writeln('TEXT 20,15,"3",0,1,1,"$safeName"');
    buffer.writeln('TEXT 20,50,"2",0,1,1,"$weightStr"');
    buffer.writeln('TEXT 170,50,"3",0,1,1,"$purityStr"');
    buffer.writeln('BARCODE 20,85,"128",65,0,0,2,4,"${item.barcode}"');
    buffer.writeln('TEXT 40,165,"2",0,1,1,"${item.barcode}"');
    buffer.writeln('PRINT 1,1');

    return buffer.toString();
  }

  /// Sends raw TSPL commands over TCP Socket to printer IP and Port
  static Future<bool> sendTSPLToPrinter(
    InventoryItem item, {
    required String host,
    required int port,
  }) async {
    if (kIsWeb) {
      debugPrint('TSPL Label generated (Web Simulation):\n${buildTSPLCommand(item)}');
      return true;
    }
    final tsplStr = buildTSPLCommand(item);
    final bytes = utf8.encode(tsplStr);

    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }
}
