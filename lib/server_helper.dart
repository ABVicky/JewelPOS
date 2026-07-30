import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'db.dart';

/// Embedded Lightweight HTTP Server running on Windows Desktop
/// Listens on Port 8080 for Local WiFi HTTP requests from Android HandPOS
class DesktopHttpServer {
  static HttpServer? _server;
  static String _serverIp = '127.0.0.1';

  static String get serverIp => _serverIp;
  static int get serverPort => 8080;
  static bool get isRunning => _server != null;

  /// Fetch local network IPv4 address (e.g. 192.168.x.x)
  static Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Automatically starts HTTP Server when Windows app opens
  static Future<void> startServer() async {
    if (kIsWeb) {
      _serverIp = 'localhost';
      return;
    }
    if (_server != null) return;

    try {
      _serverIp = await getLocalIpAddress();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _server!.listen(_handleRequest);
      debugPrint('HTTP Server Running at http://$_serverIp:8080');
    } catch (e) {
      debugPrint('HttpServer start error: $e');
    }
  }

  /// Stop server when Windows application closes
  static Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
  }

  static void _handleRequest(HttpRequest request) async {
    // Add CORS headers for local requests
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    // 1. GET /health
    if (request.method == 'GET' && path == '/health') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.text;
      request.response.write('OK');
      await request.response.close();
      return;
    }

    // 2. GET /item/{barcode}
    if (request.method == 'GET' && path.startsWith('/item/')) {
      final barcode = Uri.decodeComponent(path.replaceFirst('/item/', '').trim());
      request.response.headers.contentType = ContentType.json;

      if (barcode.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(jsonEncode({'message': 'Invalid Barcode'}));
        await request.response.close();
        return;
      }

      try {
        final items = await InventoryDB.getAllItems();
        final match = items.where((i) => i.barcode.toLowerCase() == barcode.toLowerCase()).toList();

        if (match.isNotEmpty) {
          final item = match.first;
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'barcode': item.barcode,
            'item_name': item.itemName,
            'category': item.category,
            'purity': item.purity,
            'weight': item.weight,
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'message': 'Item Not Found'}));
        }
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'message': 'Server Error: ${e.toString()}'}));
      }
      await request.response.close();
      return;
    }

    // Default 404
    request.response.statusCode = HttpStatus.notFound;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'message': 'Endpoint Not Found'}));
    await request.response.close();
  }
}
