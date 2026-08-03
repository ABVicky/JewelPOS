/*
 * Designed and Developed by Manikarnika Technologies
 * Website: https://www.manikarnikatechnologies.in
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'db.dart';
import 'printer.dart';

class ScannedPosItem {
  final String barcode;
  final String itemName;
  final String category;
  final String purity;
  final double weight;

  ScannedPosItem({
    required this.barcode,
    required this.itemName,
    required this.category,
    required this.purity,
    required this.weight,
  });

  factory ScannedPosItem.fromJson(Map<String, dynamic> json) {
    return ScannedPosItem(
      barcode: json['barcode'] as String? ?? '',
      itemName: json['item_name'] as String? ?? json['name'] as String? ?? 'Unknown',
      category: json['category'] as String? ?? '',
      purity: json['purity'] as String? ?? '',
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AndroidHandPOSApp extends StatefulWidget {
  const AndroidHandPOSApp({super.key});

  @override
  State<AndroidHandPOSApp> createState() => _AndroidHandPOSAppState();
}

class _AndroidHandPOSAppState extends State<AndroidHandPOSApp> {
  // In-Memory Temporary List
  final List<ScannedPosItem> _scannedItems = [];

  // Settings & Connection State
  String _desktopIp = '192.168.1.25';
  String _printerIp = '127.0.0.1'; // Built-in thermal printer for Smart POS Model 1008
  int _printerPort = 9100;
  String _terminalName = 'Smart POS 1008 HandPOS';
  String _terminalId = 'POS-1008';

  bool _autoPrintOnScan = false;
  bool _isConnectedToDesktop = false;
  bool _isAutoDiscovering = false;
  String _connectionStatusText = 'Connecting...';
  Timer? _pingTimer;

  // Scanner Hardware Focus
  final FocusNode _laserFocusNode = FocusNode();
  final TextEditingController _laserInputController = TextEditingController();

  bool _isProcessingScan = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndAutoConnect();
    // Start periodic background connectivity heartbeat ping every 6 seconds
    _pingTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_isAutoDiscovering) {
        _sendConnectivityPing();
      }
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _laserFocusNode.dispose();
    _laserInputController.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndAutoConnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _desktopIp = prefs.getString('android_desktop_ip') ?? '192.168.1.25';
        _printerIp = prefs.getString('android_printer_ip') ?? '127.0.0.1';
        _printerPort = prefs.getInt('android_printer_port') ?? 9100;
        _terminalName = prefs.getString('android_terminal_name') ?? 'Smart POS 1008 HandPOS';
        _terminalId = prefs.getString('android_terminal_id') ?? 'POS-1008';
        _autoPrintOnScan = prefs.getBool('android_auto_print') ?? false;
      });

      // Attempt immediate auto-connection
      bool ok = await _sendConnectivityPing();
      if (!ok) {
        // If saved IP fails, automatically discover active Desktop on local WiFi
        await _autoDiscoverAndConnectDesktop();
      }
    } catch (_) {}
  }

  Future<void> _saveSettings(String desktopIp, String printerIp, int port, String terminalName, bool autoPrint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('android_desktop_ip', desktopIp);
      await prefs.setString('android_printer_ip', printerIp);
      await prefs.setInt('android_printer_port', port);
      await prefs.setString('android_terminal_name', terminalName);
      await prefs.setBool('android_auto_print', autoPrint);
      setState(() {
        _desktopIp = desktopIp;
        _printerIp = printerIp;
        _printerPort = port;
        _terminalName = terminalName;
        _autoPrintOnScan = autoPrint;
      });
      _sendConnectivityPing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings Saved & Synced')),
        );
      }
    } catch (e) {
      _showSimpleDialog('Error', e.toString());
    }
  }

  // --- AUTOMATIC SUBNET DISCOVERY ---
  Future<bool> _autoDiscoverAndConnectDesktop() async {
    if (_isAutoDiscovering) return false;
    _isAutoDiscovering = true;

    if (mounted) {
      setState(() {
        _connectionStatusText = 'Auto-detecting Desktop Workstation on WiFi...';
      });
    }

    try {
      final List<String> candidateSubnets = [];

      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback && (addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.'))) {
              final parts = addr.address.split('.');
              candidateSubnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
            }
          }
        }
      } catch (_) {}

      if (candidateSubnets.isEmpty) {
        candidateSubnets.add('192.168.1');
        candidateSubnets.add('192.168.0');
      }

      for (var subnet in candidateSubnets) {
        final List<Future<String?>> scanTasks = [];
        for (int i = 1; i <= 254; i++) {
          final targetIp = '$subnet.$i';
          scanTasks.add(_testDesktopAddress(targetIp));
        }

        final results = await Future.wait(scanTasks);
        final foundIp = results.firstWhere((ip) => ip != null, orElse: () => null);

        if (foundIp != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('android_desktop_ip', foundIp);

          if (mounted) {
            setState(() {
              _desktopIp = foundIp;
              _isAutoDiscovering = false;
            });
          }
          bool ok = await _sendConnectivityPing();
          _isAutoDiscovering = false;
          return ok;
        }
      }
    } catch (_) {}

    _isAutoDiscovering = false;
    if (mounted) {
      setState(() {
        _isConnectedToDesktop = false;
        _connectionStatusText = 'Desktop Not Found — Tap to Setup';
      });
    }
    return false;
  }

  Future<String?> _testDesktopAddress(String targetIp) async {
    final url = Uri.parse('http://$targetIp:8080/health');
    try {
      final response = await http.get(url).timeout(const Duration(milliseconds: 900));
      if (response.statusCode == 200 && (response.body.trim() == 'OK' || response.body.contains('ok'))) {
        return targetIp;
      }
    } catch (_) {}
    return null;
  }

  // --- CONNECTIVITY SYNC & PING ---
  Future<bool> _sendConnectivityPing() async {
    final url = Uri.parse('http://$_desktopIp:8080/ping');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': _terminalId,
          'name': _terminalName,
        }),
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _isConnectedToDesktop = true;
            _connectionStatusText = 'Connected to Workstation ($_desktopIp:8080)';
          });
        }
        return true;
      }
    } catch (_) {}

    if (mounted && !_isAutoDiscovering) {
      setState(() {
        _isConnectedToDesktop = false;
        _connectionStatusText = 'Not Connected to Desktop ($_desktopIp)';
      });
    }
    return false;
  }

  // --- SCANNING & LOOKUP FLOW ---
  Future<void> _onBarcodeScanned(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty || _isProcessingScan) return;
    _isProcessingScan = true;

    // Check duplicate scan
    final isDuplicate = _scannedItems.any((item) => item.barcode.toLowerCase() == cleanBarcode.toLowerCase());

    if (isDuplicate) {
      bool? addAgain = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text('Item Already Scanned', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Item already scanned.\nAdd again?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('NO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('YES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      );

      if (addAgain != true) {
        _isProcessingScan = false;
        return;
      }
    }

    // Call Desktop HTTP GET /item/{barcode} with max 3s timeout
    await _fetchItemFromDesktop(cleanBarcode);
    _isProcessingScan = false;
  }

  Future<void> _fetchItemFromDesktop(String barcode) async {
    final url = Uri.parse('http://$_desktopIp:8080/item/$barcode');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final item = ScannedPosItem.fromJson(data);
        setState(() {
          _scannedItems.add(item);
          _isConnectedToDesktop = true;
          _connectionStatusText = 'Connected to Workstation ($_desktopIp:8080)';
        });

        // Auto-print receipt if enabled
        if (_autoPrintOnScan) {
          await _sendToBuiltInPrinter();
        }
      } else if (response.statusCode == 404) {
        _showSimpleDialog('Item Not Found', 'The item barcode $barcode was not found in inventory.');
      } else {
        _showSimpleDialog('Item Not Found', 'Server returned status ${response.statusCode}');
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _isConnectedToDesktop = false);
      _showSimpleDialog('Desktop Not Reachable', 'HTTP connection timed out (Max 3s). Ensure Desktop app is running.');
    } on SocketException {
      if (!mounted) return;
      setState(() => _isConnectedToDesktop = false);
      _showSimpleDialog('Check WiFi Connection', 'Could not reach Desktop at http://$_desktopIp:8080. Verify WiFi network connection.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnectedToDesktop = false);
      _showSimpleDialog('Desktop Application Not Running', 'Could not connect to Desktop server at http://$_desktopIp:8080');
    }
  }

  // Camera Scanner Modal
  void _openCameraScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => SizedBox(
        height: 450,
        child: Column(
          children: [
            Container(
              color: Colors.grey.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text('Camera Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null) {
                      final val = barcode.rawValue!;
                      Navigator.of(ctx).pop();
                      _onBarcodeScanned(val);
                      break;
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Manual Barcode Entry Fallback
  void _openManualEntryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Manual Barcode Entry'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Enter Barcode ID',
            hintText: 'e.g. JMT000000001',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () {
              final text = controller.text.trim();
              Navigator.of(ctx).pop();
              if (text.isNotEmpty) {
                _onBarcodeScanned(text);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // Clear In-Memory List
  void _clearList() {
    setState(() {
      _scannedItems.clear();
    });
  }

  // --- ESC/POS RECEIPT PRINTING (BUILT-IN 58MM THERMAL PRINTER FOR SMART POS 1008) ---
  List<int>? _cachedLogoEscBytes;

  Future<List<int>> _getLogoEscPosBytes() async {
    if (_cachedLogoEscBytes != null) return _cachedLogoEscBytes!;
    try {
      final ByteData data = await rootBundle.load('assets/images/jewel_logo.png');
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      final ByteData? rgbaData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgbaData == null) return [];

      final int width = image.width;
      final int height = image.height;
      final int widthBytes = (width + 7) ~/ 8;

      final List<int> escPos = [];
      // GS v 0 0 (raster bit image, normal mode)
      escPos.addAll([
        0x1D, 0x76, 0x30, 0x00,
        widthBytes & 0xFF,
        (widthBytes >> 8) & 0xFF,
        height & 0xFF,
        (height >> 8) & 0xFF,
      ]);

      final Uint8List rgba = rgbaData.buffer.asUint8List();
      for (int y = 0; y < height; y++) {
        for (int xByte = 0; xByte < widthBytes; xByte++) {
          int byteVal = 0;
          for (int bit = 0; bit < 8; bit++) {
            int x = xByte * 8 + bit;
            if (x < width) {
              int offset = (y * width + x) * 4;
              int r = rgba[offset];
              int g = rgba[offset + 1];
              int b = rgba[offset + 2];
              int a = rgba[offset + 3];
              if (a > 64) {
                double luminance = 0.299 * r + 0.587 * g + 0.114 * b;
                if (luminance < 160) {
                  byteVal |= (0x80 >> bit);
                }
              }
            }
          }
          escPos.add(byteVal);
        }
      }
      _cachedLogoEscBytes = escPos;
      return escPos;
    } catch (e) {
      debugPrint('Error loading logo for receipt printing: $e');
      return [];
    }
  }

  Future<List<int>> _generateEscPosBytes({List<ScannedPosItem>? customList}) async {
    final itemsToPrint = customList ?? _scannedItems;
    final bytes = <int>[];

    // Initialize ESC/POS
    bytes.addAll([0x1B, 0x40]);
    // Center Align
    bytes.addAll([0x1B, 0x61, 0x01]);

    // Print Logo at the top of the receipt
    final logoEscBytes = await _getLogoEscPosBytes();
    if (logoEscBytes.isNotEmpty) {
      bytes.addAll(logoEscBytes);
      bytes.addAll(utf8.encode("\n"));
    }

    // Double height & width header
    bytes.addAll([0x1B, 0x21, 0x30]);
    bytes.addAll(utf8.encode("JEWEL POS\n"));
    // Reset Format
    bytes.addAll([0x1B, 0x21, 0x00]);
    bytes.addAll(utf8.encode("================================\n"));

    // Header Table Columns (32 columns max for 58mm paper roll)
    bytes.addAll([0x1B, 0x61, 0x00]); // Left align
    bytes.addAll(utf8.encode("Item Name               Weight  \n"));
    bytes.addAll(utf8.encode("--------------------------------\n"));

    double totalWeight = 0.0;
    for (var item in itemsToPrint) {
      totalWeight += item.weight;
      final nameStr = item.itemName.length > 20
          ? item.itemName.substring(0, 20)
          : item.itemName.padRight(20);
      final wtStr = "${item.weight.toStringAsFixed(3)} g".padLeft(12);
      bytes.addAll(utf8.encode("$nameStr$wtStr\n"));
    }

    bytes.addAll(utf8.encode("--------------------------------\n"));
    final countStr = itemsToPrint.length.toString();
    final totWtStr = "${totalWeight.toStringAsFixed(3)} g";

    final countPad = ' ' * (32 - "Items".length - countStr.length);
    bytes.addAll(utf8.encode("Items$countPad$countStr\n"));

    final wtPad = ' ' * (32 - "Total Weight".length - totWtStr.length);
    bytes.addAll(utf8.encode("Total Weight$wtPad$totWtStr\n"));

    bytes.addAll(utf8.encode("================================\n"));

    // Footer
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align
    bytes.addAll(utf8.encode("Thank You\n\n\n"));
    // Feed and Cut (GS V 66 0)
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);

    return bytes;
  }

  static const _printerChannel = MethodChannel('jewel_pos/printer');

  Future<bool> _sendToBuiltInPrinter({List<ScannedPosItem>? customList}) async {
    if (kIsWeb) return true;

    final bytes = Uint8List.fromList(await _generateEscPosBytes(customList: customList));

    // 1. Invoke Native Android MethodChannel (Serial & Native Port scanner)
    try {
      final bool? result = await _printerChannel.invokeMethod<bool>('printBytes', {
        'bytes': bytes,
        'ip': _printerIp,
        'port': _printerPort,
      });
      if (result == true) return true;
    } catch (e) {
      debugPrint('Native printer MethodChannel exception: $e');
    }

    // 2. Fallback Dart Socket Scanner across internal POS thermal ports
    final List<String> targetHosts = [_printerIp, '127.0.0.1', 'localhost', '0.0.0.0'];
    final List<int> targetPorts = [_printerPort, 9100, 9108, 8000, 8888, 9000, 6001, 7000, 5800, 3000, 9101, 9102, 20001, 10008];

    for (var host in targetHosts) {
      for (var port in targetPorts) {
        try {
          final socket = await Socket.connect(host, port, timeout: const Duration(milliseconds: 300));
          socket.add(bytes);
          await socket.flush();
          await socket.close();
          return true;
        } catch (_) {}
      }
    }
    return false;
  }

  Future<bool> _printViaAndroidSystemManager({List<ScannedPosItem>? customList}) async {
    final itemsToPrint = customList ?? _scannedItems;
    final StringBuffer sb = StringBuffer();
    sb.writeln("JEWEL POS");
    sb.writeln("================================");
    sb.writeln("Item Name               Weight  ");
    sb.writeln("--------------------------------");
    double totalWeight = 0.0;
    for (var item in itemsToPrint) {
      totalWeight += item.weight;
      final nameStr = item.itemName.length > 20
          ? item.itemName.substring(0, 20)
          : item.itemName.padRight(20);
      final wtStr = "${item.weight.toStringAsFixed(3)} g".padLeft(12);
      sb.writeln("$nameStr$wtStr");
    }
    sb.writeln("--------------------------------");
    final countStr = itemsToPrint.length.toString();
    final totWtStr = "${totalWeight.toStringAsFixed(3)} g";

    final countPad = ' ' * (32 - "Items".length - countStr.length);
    sb.writeln("Items$countPad$countStr");

    final wtPad = ' ' * (32 - "Total Weight".length - totWtStr.length);
    sb.writeln("Total Weight$wtPad$totWtStr");
    sb.writeln("================================");
    sb.writeln("Thank You");

    final bytes = Uint8List.fromList(await _generateEscPosBytes(customList: customList));

    try {
      final bool? result = await _printerChannel.invokeMethod<bool>('printText', {
        'text': sb.toString(),
        'bytes': bytes,
      });
      return result ?? true;
    } catch (e) {
      debugPrint('Android PrintManager error: $e');
    }
    return false;
  }

  Future<void> _recordPrintLog(List<ScannedPosItem> itemsToPrint) async {
    try {
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      double totalWeight = 0.0;
      for (var item in itemsToPrint) {
        totalWeight += item.weight;
      }

      final log = PrintLog(
        terminalName: _terminalName.isNotEmpty ? _terminalName : 'POS Terminal',
        date: dateStr,
        timestamp: now.toIso8601String(),
        totalItems: itemsToPrint.length,
        totalWeight: totalWeight,
        itemsJson: jsonEncode(itemsToPrint.map((i) => {
          'barcode': i.barcode,
          'itemName': i.itemName,
          'category': i.category,
          'purity': i.purity,
          'weight': i.weight,
        }).toList()),
      );

      // Save locally to SQLite database
      await InventoryDB.insertPrintLog(log);

      // HTTP Sync to Desktop Server if connected
      if (_isConnectedToDesktop && _desktopIp.isNotEmpty) {
        try {
          final url = Uri.parse('http://$_desktopIp:8080/print-log');
          await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(log.toMap()),
          ).timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error recording print log: $e');
    }
  }

  Future<void> _showDailyReportDialog() async {
    final now = DateTime.now();
    String selectedDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return FutureBuilder<List<PrintLog>>(
              future: InventoryDB.getPrintLogsByDate(selectedDate),
              builder: (context, snapshot) {
                final logs = snapshot.data ?? [];
                int totalItems = 0;
                double totalWeight = 0.0;
                final Map<String, int> termCounts = {};
                final Map<String, double> termWeights = {};

                for (var log in logs) {
                  totalItems += log.totalItems;
                  totalWeight += log.totalWeight;
                  termCounts[log.terminalName] = (termCounts[log.terminalName] ?? 0) + 1;
                  termWeights[log.terminalName] = (termWeights[log.terminalName] ?? 0.0) + log.totalWeight;
                }

                return AlertDialog(
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  title: const Row(
                    children: [
                      Icon(Icons.assessment, color: Colors.black),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Day-Wise Print Log Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Text('Date: ', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(selectedDate, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.calendar_today, size: 18),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.tryParse(selectedDate) ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    final newDate = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                                    setStateDialog(() {
                                      selectedDate = newDate;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const Divider(),
                          Container(
                            color: const Color(0xFFF1F5F9),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Receipts:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text('${logs.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Items Billed:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text('$totalItems', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Net Weight:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text('${totalWeight.toStringAsFixed(3)} g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (termCounts.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('Terminal Breakdown:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 4),
                            ...termCounts.entries.map((e) {
                              final wt = (termWeights[e.key] ?? 0.0).toStringAsFixed(3);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('${e.key} (${e.value} receipts)', style: const TextStyle(fontSize: 12)),
                                    Text('$wt g', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              );
                            }),
                          ],
                          const SizedBox(height: 12),
                          const Text('Receipt Log Entries:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                          if (logs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('No receipt print logs recorded for this date.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            )
                          else
                            ...logs.map((log) {
                              final dt = DateTime.tryParse(log.timestamp);
                              final timeStr = dt != null
                                  ? "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}"
                                  : log.timestamp;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    Text('$timeStr  |  ${log.terminalName}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    Text('${log.totalItems} items (${log.totalWeight.toStringAsFixed(3)} g)', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('CLOSE'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      onPressed: logs.isEmpty ? null : () async {
                        final pdfBytes = await TSPLPrinter.generateDailyReportPdfBytes(selectedDate, logs);
                        await Printing.layoutPdf(
                          onLayout: (format) async => pdfBytes,
                          name: 'JewelPOS_DailyReport_$selectedDate',
                          format: const PdfPageFormat(
                            58 * PdfPageFormat.mm,
                            200 * PdfPageFormat.mm,
                            marginAll: 2 * PdfPageFormat.mm,
                          ),
                        );
                      },
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('Print Final Report', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _printReceiptWithRetry() async {
    if (_scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items to print.')),
      );
      return;
    }

    // 1. Try direct raw socket / serial driver
    bool printSuccess = await _sendToBuiltInPrinter();

    // 2. If raw socket returned false, automatically send to POSPrinter system driver
    if (!printSuccess) {
      printSuccess = await _printViaAndroidSystemManager();
    }

    if (!mounted) return;

    if (printSuccess) {
      _recordPrintLog(List.from(_scannedItems));
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text('Receipt Printed (POSPrinter)', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Clear List?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('NO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _clearList();
              },
              child: const Text('YES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      );
    }
  }

  // --- CONNECTIVITY GUIDE & PAIRING HELPER DIALOG ---
  void _openConnectivityGuideDialog() {
    final desktopIpCtrl = TextEditingController(text: _desktopIp);
    final terminalNameCtrl = TextEditingController(text: _terminalName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Row(
          children: [
            Icon(Icons.wifi, color: Colors.black),
            SizedBox(width: 8),
            Text('Desktop Connection & Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.all(12),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Smart POS 1008 Alignment', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      Text('• Built-in 58mm thermal printer ready.\n• Hardware side scanner button enabled.\n• Auto-connects to Windows PC when open.', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: desktopIpCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Desktop Workstation IP',
                    hintText: 'e.g. 192.168.1.25',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: terminalNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Terminal Device Name',
                    hintText: 'e.g. Smart POS 1008',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(42),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _autoDiscoverAndConnectDesktop();
                  },
                  icon: const Icon(Icons.radar, size: 18),
                  label: const Text('Auto-Detect Desktop on WiFi', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () async {
              final newIp = desktopIpCtrl.text.trim();
              final newName = terminalNameCtrl.text.trim().isEmpty ? 'Smart POS 1008' : terminalNameCtrl.text.trim();
              Navigator.of(ctx).pop();

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('android_desktop_ip', newIp);
              await prefs.setString('android_terminal_name', newName);

              setState(() {
                _desktopIp = newIp;
                _terminalName = newName;
              });

              bool connected = await _sendConnectivityPing();

              if (!mounted) return;
              if (connected) {
                _showSimpleDialog('Connection Successful', 'Connected and synced to Desktop Workstation at $newIp:8080');
              } else {
                _showSimpleDialog('Connection Failed', 'Could not reach Desktop at http://$newIp:8080.\nPlease verify Desktop IP and WiFi connection.');
              }
            },
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Connect & Sync', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Settings Dialog with Built-in Printer Diagnostics Test
  void _openSettingsDialog() {
    final desktopIpCtrl = TextEditingController(text: _desktopIp);
    final printerIpCtrl = TextEditingController(text: _printerIp);
    final printerPortCtrl = TextEditingController(text: _printerPort.toString());
    final terminalNameCtrl = TextEditingController(text: _terminalName);
    bool tempAutoPrint = _autoPrintOnScan;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text('Smart POS 1008 Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: desktopIpCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Desktop IP',
                    hintText: '192.168.1.25',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: printerIpCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Internal Printer Address (Built-in)',
                    hintText: '127.0.0.1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: printerPortCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Internal Printer Port (9100 / 9108 / 8000 / 8888 / 6001)',
                    hintText: '9100',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: terminalNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Terminal Device Name',
                    hintText: 'Smart POS 1008 HandPOS',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Auto-Print Receipt on Scan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Automatically print receipt on built-in printer upon scanning tag', style: TextStyle(fontSize: 11)),
                  value: tempAutoPrint,
                  onChanged: (val) => setDlgState(() => tempAutoPrint = val),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  onPressed: () async {
                    final testItem = ScannedPosItem(
                      barcode: 'TEST1008',
                      itemName: 'Printer Test',
                      category: 'Test',
                      purity: '22K',
                      weight: 1.000,
                    );
                    final testOk = await _sendToBuiltInPrinter(customList: [testItem]);
                    if (!ctx.mounted) return;
                    if (testOk) {
                      _showSimpleDialog('Test Print Successful', 'Receipt output sent to built-in thermal printer.');
                    } else {
                      _showSimpleDialog('Test Print Failed', 'Could not output test print. Try changing printer port to 9108, 8000, or 8888.');
                    }
                  },
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Test Built-in Thermal Printer', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () {
                final port = int.tryParse(printerPortCtrl.text.trim()) ?? 9100;
                Navigator.of(ctx).pop();
                _saveSettings(desktopIpCtrl.text.trim(), printerIpCtrl.text.trim(), port, terminalNameCtrl.text.trim(), tempAutoPrint);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSimpleDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Calculate Totals
  double get _totalWeight => _scannedItems.fold(0.0, (sum, item) => sum + item.weight);

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('About Jewel POS', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/images/logo.png', height: 85, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Jewellery Inventory & POS System', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              const Text('Hand POS Terminal Edition (Model 1008)', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const Divider(height: 24),
              const Text('ARS Technologies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              const Text('Customer care number : 8584862931', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Customer care Email ID : customercare@arstechnologies.org', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Sales : 8584862939', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset('assets/images/logo.png', height: 26, width: 26, fit: BoxFit.cover),
            ),
            const SizedBox(width: 8),
            const Text('JEWEL POS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment),
            tooltip: 'Daily Print Report',
            onPressed: _showDailyReportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: _showAboutDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Connection Status Banner
            GestureDetector(
              onTap: _openConnectivityGuideDialog,
              child: Container(
                color: _isConnectedToDesktop ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _isConnectedToDesktop ? Icons.check_circle : Icons.wifi_off,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _connectionStatusText,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        _isConnectedToDesktop ? 'AUTO-CONNECTED' : 'AUTO-CONNECT',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Hidden Hardware Laser & One-Key Side Scanner Text Receiver
            Opacity(
              opacity: 0,
              child: SizedBox(
                height: 1,
                width: 1,
                child: TextField(
                  focusNode: _laserFocusNode,
                  controller: _laserInputController,
                  autofocus: true,
                  onSubmitted: (val) {
                    _laserInputController.clear();
                    _onBarcodeScanned(val);
                    _laserFocusNode.requestFocus();
                  },
                ),
              ),
            ),

            // Top Action Controls (Large High-Contrast Buttons for Smart POS 1008)
            Container(
              color: const Color(0xFFF1F5F9),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          ),
                          onPressed: _openCameraScanner,
                          icon: const Icon(Icons.qr_code_scanner, size: 20),
                          label: const Text('Scan Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          padding: const EdgeInsets.all(16),
                        ),
                        icon: const Icon(Icons.keyboard),
                        tooltip: 'Manual Barcode Entry',
                        onPressed: _openManualEntryDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          ),
                          onPressed: _printReceiptWithRetry,
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('Print Receipt (Built-in)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            side: const BorderSide(color: Colors.black, width: 2),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _clearList,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Clear List', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Colors.black),

            // Section Header
            Container(
              width: double.infinity,
              color: const Color(0xFFE2E8F0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Text(
                'Scanned Items',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
              ),
            ),

            // Scanned Items List View
            Expanded(
              child: _scannedItems.isEmpty
                  ? const Center(
                      child: Text(
                        'No Items Scanned Yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _scannedItems.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _scannedItems[index];
                        return Dismissible(
                          key: ValueKey('${item.barcode}_${index}_${item.weight}'),
                          direction: DismissDirection.horizontal,
                          background: Container(
                            color: const Color(0xFF991B1B),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Row(
                              children: [
                                Icon(Icons.delete, color: Colors.white),
                                SizedBox(width: 8),
                                Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          secondaryBackground: Container(
                            color: const Color(0xFF991B1B),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                SizedBox(width: 8),
                                Icon(Icons.delete, color: Colors.white),
                              ],
                            ),
                          ),
                          onDismissed: (_) {
                            final removedName = item.itemName;
                            final itemNum = index + 1;
                            setState(() {
                              _scannedItems.removeAt(index);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Item #$itemNum ($removedName) removed'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              radius: 14,
                              child: Text(
                                '#${index + 1}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  item.itemName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const Spacer(),
                                Text(
                                  '${item.weight.toStringAsFixed(3)} g',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              'Barcode: ${item.barcode}  |  Category: ${item.category}  |  Purity: ${item.purity}',
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Bottom Summary Bar
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Items: ${_scannedItems.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Total Weight: ${_totalWeight.toStringAsFixed(3)} g',
                    style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
