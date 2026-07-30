import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Settings (Desktop IP saved locally in shared_preferences)
  String _desktopIp = '192.168.1.25';
  String _printerIp = '192.168.1.200';
  int _printerPort = 9100;

  // Scanner Hardware Focus
  final FocusNode _laserFocusNode = FocusNode();
  final TextEditingController _laserInputController = TextEditingController();

  bool _isProcessingScan = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _desktopIp = prefs.getString('android_desktop_ip') ?? '192.168.1.25';
        _printerIp = prefs.getString('android_printer_ip') ?? '192.168.1.200';
        _printerPort = prefs.getInt('android_printer_port') ?? 9100;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings(String desktopIp, String printerIp, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('android_desktop_ip', desktopIp);
      await prefs.setString('android_printer_ip', printerIp);
      await prefs.setInt('android_printer_port', port);
      setState(() {
        _desktopIp = desktopIp;
        _printerIp = printerIp;
        _printerPort = port;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings Saved')),
        );
      }
    } catch (e) {
      _showSimpleDialog('Error', e.toString());
    }
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
        });
      } else if (response.statusCode == 404) {
        _showSimpleDialog('Item Not Found', 'The item barcode $barcode was not found in inventory.');
      } else {
        _showSimpleDialog('Item Not Found', 'Server returned status ${response.statusCode}');
      }
    } on TimeoutException {
      if (!mounted) return;
      _showSimpleDialog('Desktop Not Reachable', 'HTTP connection timed out (Max 3s). Ensure Desktop app is running.');
    } on SocketException {
      if (!mounted) return;
      _showSimpleDialog('Check WiFi Connection', 'Could not reach Desktop at http://$_desktopIp:8080. Verify WiFi network connection.');
    } catch (e) {
      if (!mounted) return;
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

  // --- ESC/POS RECEIPT PRINTING ---
  List<int> _generateEscPosBytes() {
    final bytes = <int>[];

    // Initialize ESC/POS
    bytes.addAll([0x1B, 0x40]);
    // Center Align
    bytes.addAll([0x1B, 0x61, 0x01]);
    // Double height & width header
    bytes.addAll([0x1B, 0x21, 0x30]);
    bytes.addAll(utf8.encode("JEWEL POS\n"));
    // Reset Format
    bytes.addAll([0x1B, 0x21, 0x00]);
    bytes.addAll(utf8.encode("================================\n"));

    // Header Table Columns
    bytes.addAll([0x1B, 0x61, 0x00]); // Left align
    bytes.addAll(utf8.encode("Barcode      Item      Weight   \n"));
    bytes.addAll(utf8.encode("--------------------------------\n"));

    double totalWeight = 0.0;
    for (var item in _scannedItems) {
      totalWeight += item.weight;
      final bcStr = item.barcode.padRight(12).substring(0, 12);
      final itemStr = item.itemName.padRight(10).substring(0, 10);
      final wtStr = item.weight.toStringAsFixed(3).padLeft(8);
      bytes.addAll(utf8.encode("$bcStr$itemStr$wtStr\n"));
    }

    bytes.addAll(utf8.encode("--------------------------------\n"));
    final countStr = _scannedItems.length.toString();
    final totWtStr = "${totalWeight.toStringAsFixed(3)} g";

    final countPad = ' ' * (32 - "Items".length - countStr.length);
    bytes.addAll(utf8.encode("Items$countPad$countStr\n"));

    final wtPad = ' ' * (32 - "Weight".length - totWtStr.length);
    bytes.addAll(utf8.encode("Weight$wtPad$totWtStr\n"));

    bytes.addAll(utf8.encode("================================\n"));

    // Footer
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align
    bytes.addAll(utf8.encode("Thank You\n\n\n"));
    // Feed and Cut (GS V 66 0)
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);

    return bytes;
  }

  Future<void> _printReceiptWithRetry() async {
    if (_scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items to print.')),
      );
      return;
    }

    bool printSuccess = false;

    if (kIsWeb) {
      debugPrint('ESC/POS Receipt Printed (Web Mode): ${_scannedItems.length} items');
      printSuccess = true;
    } else {
      try {
        final socket = await Socket.connect(_printerIp, _printerPort, timeout: const Duration(seconds: 3));
        socket.add(_generateEscPosBytes());
        await socket.flush();
        await socket.close();
        printSuccess = true;
      } catch (_) {
        printSuccess = false;
      }
    }

    if (!mounted) return;

    if (printSuccess) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text('Receipt Printed Successfully', style: TextStyle(fontWeight: FontWeight.bold)),
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
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text('Printer Error', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          content: Text('Could not print receipt to printer at $_printerIp:$_printerPort.\nPlease check printer power & paper status.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _printReceiptWithRetry();
              },
              child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  // --- SETTINGS & CONNECTION TEST ---
  void _openSettingsDialog() {
    final desktopIpCtrl = TextEditingController(text: _desktopIp);
    final printerIpCtrl = TextEditingController(text: _printerIp);
    final printerPortCtrl = TextEditingController(text: _printerPort.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('HandPOS Settings', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  labelText: 'Receipt Printer IP',
                  hintText: '192.168.1.200',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: printerPortCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Receipt Printer Port',
                  hintText: '9100',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(42),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                onPressed: () async {
                  final targetIp = desktopIpCtrl.text.trim();
                  final url = Uri.parse('http://$targetIp:8080/health');
                  try {
                    final res = await http.get(url).timeout(const Duration(seconds: 3));
                    if (res.statusCode == 200 && (res.body.trim() == 'OK' || res.body.contains('ok')) && ctx.mounted) {
                      _showSimpleDialog('Test Connection', 'Connected');
                    } else if (ctx.mounted) {
                      _showSimpleDialog('Test Connection', 'Connection Failed');
                    }
                  } catch (_) {
                    if (ctx.mounted) {
                      _showSimpleDialog('Test Connection', 'Connection Failed');
                    }
                  }
                },
                icon: const Icon(Icons.network_check, size: 18),
                label: const Text('Test Connection', style: TextStyle(fontWeight: FontWeight.bold)),
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
              _saveSettings(desktopIpCtrl.text.trim(), printerIpCtrl.text.trim(), port);
            },
            child: const Text('Save'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('JEWEL POS (Android HandPOS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
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
            // Hidden Hardware Laser Scanner Text Receiver
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

            // Top Action Controls (Large High-Contrast Buttons)
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
                          icon: const Icon(Icons.receipt, size: 18),
                          label: const Text('Print Receipt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                        return ListTile(
                          dense: true,
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
