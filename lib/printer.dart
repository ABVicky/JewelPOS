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
    buffer.writeln('TEXT 15,10,"3",0,1,1,"${item.itemName}"');
    buffer.writeln('TEXT 15,40,"2",0,1,1,"Cat: ${item.category}  Pur: ${item.purity}"');
    buffer.writeln('TEXT 15,65,"2",0,1,1,"Wt: ${item.weight.toStringAsFixed(4)} g"');
    buffer.writeln('BARCODE 15,95,"128",45,1,0,2,2,"${item.barcode}"');
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
