/*
 * Designed and Developed by Manikarnika Technologies
 * Website: https://www.manikarnikatechnologies.in
 */

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'db.dart';

class TerminalDevice {
  final String id;
  final String name;
  final String ip;
  final DateTime lastSeen;

  TerminalDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.lastSeen,
  });

  bool get isOnline => DateTime.now().difference(lastSeen).inSeconds < 15;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'is_online': isOnline,
      'last_seen': lastSeen.toIso8601String(),
    };
  }
}

/// Embedded Lightweight HTTP Server running on Windows Desktop
/// Listens on Port 8080 for Local WiFi HTTP requests from Android HandPOS
class DesktopHttpServer {
  static HttpServer? _server;
  static String _serverIp = '127.0.0.1';
  static final Map<String, TerminalDevice> _connectedTerminals = {};

  static String get serverIp => _serverIp;
  static int get serverPort => 8080;
  static bool get isRunning => _server != null;

  static List<TerminalDevice> getConnectedTerminals() {
    return _connectedTerminals.values.toList();
  }

  static int get activeOnlineTerminalsCount {
    return _connectedTerminals.values.where((t) => t.isOnline).length;
  }

  /// Fetch local network IPv4 address (e.g. 192.168.x.x)
  static Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && (addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.'))) {
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
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
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

    // 2. POST /ping or GET /ping (POS Terminal Connectivity Sync & Heartbeat)
    if (path == '/ping') {
      try {
        String body = '';
        if (request.method == 'POST') {
          body = await utf8.decoder.bind(request).join();
        }

        Map<String, dynamic> data = {};
        if (body.isNotEmpty) {
          try {
            data = jsonDecode(body) as Map<String, dynamic>;
          } catch (_) {}
        }

        final clientIp = request.connectionInfo?.remoteAddress.address ?? '192.168.1.x';
        final terminalId = (data['id'] as String?) ?? request.uri.queryParameters['id'] ?? 'POS-${clientIp.split('.').last}';
        final terminalName = (data['name'] as String?) ?? request.uri.queryParameters['name'] ?? 'Android HandPOS ($clientIp)';

        _connectedTerminals[terminalId] = TerminalDevice(
          id: terminalId,
          name: terminalName,
          ip: clientIp,
          lastSeen: DateTime.now(),
        );

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'connected',
          'desktop_ip': _serverIp,
          'desktop_port': 8080,
          'terminal_id': terminalId,
        }));
      } catch (e) {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({'status': 'connected'}));
      }
      await request.response.close();
      return;
    }

    // 3. GET /terminals (List active POS terminals)
    if (request.method == 'GET' && path == '/terminals') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_connectedTerminals.values.map((t) => t.toJson()).toList()));
      await request.response.close();
      return;
    }

    // 4. GET /item/{barcode}
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

    // 5. POST /print-log (Save receipt print event from POS terminals into central DB)
    if (request.method == 'POST' && path == '/print-log') {
      try {
        final body = await utf8.decoder.bind(request).join();
        if (body.isNotEmpty) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          final log = PrintLog.fromMap(data);
          await InventoryDB.insertPrintLog(log);
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'status': 'logged'}));
          await request.response.close();
          return;
        }
      } catch (e) {
        debugPrint('Error logging print event: $e');
      }
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': 'Invalid Payload'}));
      await request.response.close();
      return;
    }

    // 6. GET /print-logs (Fetch day-wise print logs)
    if (request.method == 'GET' && path == '/print-logs') {
      try {
        final now = DateTime.now();
        final defaultDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
        final date = request.uri.queryParameters['date'] ?? defaultDate;
        final logs = await InventoryDB.getPrintLogsByDate(date);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(logs.map((l) => l.toMap()).toList()));
        await request.response.close();
        return;
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'message': e.toString()}));
        await request.response.close();
        return;
      }
    }

    // Default 404
    request.response.statusCode = HttpStatus.notFound;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'message': 'Endpoint Not Found'}));
    await request.response.close();
  }
}
