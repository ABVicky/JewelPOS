import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';
import 'printer.dart';
import 'server_helper.dart';

class WindowsInventoryApp extends StatefulWidget {
  const WindowsInventoryApp({super.key});

  @override
  State<WindowsInventoryApp> createState() => _WindowsInventoryAppState();
}

class _WindowsInventoryAppState extends State<WindowsInventoryApp> {
  final _formKey = GlobalKey<FormState>();

  // Left Panel Input Controllers
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController(text: 'Ring');
  final _purityController = TextEditingController(text: '22K');
  final _weightController = TextEditingController();
  String _generatedBarcode = 'JMT000000001';

  // Search & Items State
  final _searchController = TextEditingController();
  List<InventoryItem> _allItems = [];
  List<InventoryItem> _filteredItems = [];
  Set<String> _selectedBarcodes = {};
  bool _isLoading = true;

  // Settings State
  String _printerIp = '192.168.1.100';
  int _printerPort = 9100;
  int _httpServerPort = 8080;

  final List<String> _categories = [
    'Ring',
    'Chain',
    'Necklace',
    'Bangle',
    'Earrings',
    'Pendant',
    'Bracelet',
    'Coins',
    'Other'
  ];

  final List<String> _purities = [
    '24K',
    '22K (916)',
    '18K (750)',
    '14K (585)',
    'Silver (925)'
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refreshData();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _printerIp = prefs.getString('printer_ip') ?? '192.168.1.100';
        _printerPort = prefs.getInt('printer_port') ?? 9100;
        _httpServerPort = prefs.getInt('http_server_port') ?? 8080;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings(String ip, int port, int httpPort) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_ip', ip);
      await prefs.setInt('printer_port', port);
      await prefs.setInt('http_server_port', httpPort);
      setState(() {
        _printerIp = ip;
        _printerPort = port;
        _httpServerPort = httpPort;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully.')),
        );
      }
    } catch (e) {
      _showErrorDialog('Settings Error', e.toString());
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    try {
      final nextBarcode = await InventoryDB.generateNextBarcode();
      final items = await InventoryDB.getAllItems();
      if (!mounted) return;
      setState(() {
        _generatedBarcode = nextBarcode;
        _allItems = items;
        _applySearch();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorDialog('Database Error', 'Could not access database: $e');
    }
  }

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredItems = List.from(_allItems);
    } else {
      _filteredItems = _allItems.where((item) {
        return item.barcode.toLowerCase().contains(query) ||
            item.itemName.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query);
      }).toList();
    }
  }

  void _clearForm() {
    _nameController.clear();
    _weightController.clear();
    _categoryController.text = 'Ring';
    _purityController.text = '22K';
    _refreshData();
  }

  Future<void> _saveOnly() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final purity = _purityController.text.trim();
    final weight = double.tryParse(_weightController.text.trim());

    if (weight == null || weight <= 0) {
      _showErrorDialog('Invalid Weight', 'Please enter a valid positive weight in grams.');
      return;
    }

    final barcode = await InventoryDB.generateNextBarcode();

    final item = InventoryItem(
      barcode: barcode,
      itemName: name,
      category: category,
      purity: purity,
      weight: weight,
    );

    try {
      await InventoryDB.insertItem(item);
      await _refreshData();
      _clearForm();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item "$name" saved to inventory ($barcode).'),
          backgroundColor: const Color(0xFF0F172A),
        ),
      );
    } catch (e) {
      _showErrorDialog('Database Error', 'Could not save item to database.');
    }
  }

  Future<void> _saveAndPrint() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final purity = _purityController.text.trim();
    final weight = double.tryParse(_weightController.text.trim());

    if (weight == null || weight <= 0) {
      _showErrorDialog('Invalid Weight', 'Please enter a valid positive weight in grams.');
      return;
    }

    final barcode = await InventoryDB.generateNextBarcode();

    final item = InventoryItem(
      barcode: barcode,
      itemName: name,
      category: category,
      purity: purity,
      weight: weight,
    );

    // 1. ALWAYS SAVE to Database first so data is never lost!
    try {
      await InventoryDB.insertItem(item);
      await _refreshData();
      _clearForm();
    } catch (e) {
      _showErrorDialog('Database Error', 'Could not save item to database.');
      return;
    }

    // 2. Attempt TSPL label printing
    bool printSuccess = await TSPLPrinter.sendTSPLToPrinter(
      item,
      host: _printerIp,
      port: _printerPort,
    );

    if (!mounted) return;

    if (printSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item "$name" saved & label printed ($barcode).'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Saved (Printer Disconnected)'),
            ],
          ),
          content: Text(
            'Item "$name" ($barcode) was SAVED to inventory database successfully.\n\nHowever, label printing failed because printer is unreachable at IP: $_printerIp Port: $_printerPort.\n\nYou can select this item in the Inventory table to print its label at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK / Skip Print'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _reprintLabel(item);
              },
              child: const Text('Retry Print'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _reprintLabel(InventoryItem item) async {
    bool success = await TSPLPrinter.sendTSPLToPrinter(
      item,
      host: _printerIp,
      port: _printerPort,
    );

    if (!mounted) return;

    if (!success) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Row(
            children: [
              Icon(Icons.print_disabled, color: Colors.red),
              SizedBox(width: 8),
              Text('Printer Not Connected'),
            ],
          ),
          content: Text(
            'Could not send label to TSPL printer at IP: $_printerIp Port: $_printerPort.\nPlease verify printer connection and power status.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _reprintLabel(item);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _printSelectedItems() async {
    if (_selectedBarcodes.isEmpty) return;

    final selectedItems = _allItems.where((item) => _selectedBarcodes.contains(item.barcode)).toList();

    int successCount = 0;
    List<InventoryItem> failedItems = [];

    for (var item in selectedItems) {
      bool ok = await TSPLPrinter.sendTSPLToPrinter(
        item,
        host: _printerIp,
        port: _printerPort,
      );
      if (ok) {
        successCount++;
      } else {
        failedItems.add(item);
      }
    }

    if (!mounted) return;

    if (failedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully printed $successCount barcode label(s).'),
          backgroundColor: Colors.green.shade800,
        ),
      );
      setState(() {
        _selectedBarcodes.clear();
      });
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Row(
            children: [
              Icon(Icons.print_disabled, color: Colors.orange),
              SizedBox(width: 8),
              Text('Batch Printing Status'),
            ],
          ),
          content: Text(
            'Printed $successCount label(s).\nFailed to print ${failedItems.length} label(s) (Printer unreachable at IP: $_printerIp Port: $_printerPort).',
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _backupDatabase() async {
    try {
      final backupPath = await InventoryDB.backupDatabase();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Backup Successful'),
            ],
          ),
          content: Text('Database inventory.db backed up to:\n\n$backupPath'),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Backup Failed', 'Could not create database backup.');
    }
  }

  Future<void> _restoreDatabase() async {
    try {
      final backupFiles = await InventoryDB.getBackupFiles();
      if (!mounted) return;

      if (backupFiles.isEmpty) {
        _showErrorDialog('Restore Failed', 'No backup database files found in Backups folder.');
        return;
      }

      File? selectedFile = backupFiles.first;

      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            title: const Text('Restore Database'),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select a backup file to restore:'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<File>(
                    initialValue: selectedFile,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: backupFiles.map((file) {
                      final name = file.path.split(Platform.pathSeparator).last;
                      return DropdownMenuItem(value: file, child: Text(name));
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedFile = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'WARNING: Restoring will replace current inventory.db file.',
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
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
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  if (selectedFile != null) {
                    try {
                      await InventoryDB.restoreDatabase(selectedFile!);
                      await _refreshData();
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          title: const Text('Restore Successful'),
                          content: const Text('Database restored successfully.'),
                          actions: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                              ),
                              onPressed: () => Navigator.of(c).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    } catch (e) {
                      _showErrorDialog('Restore Failed', 'Database restore failed.');
                    }
                  }
                },
                child: const Text('Restore'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      _showErrorDialog('Restore Failed', 'Database restore failed.');
    }
  }

  void _showEditDialog(InventoryItem item) {
    final nameCtrl = TextEditingController(text: item.itemName);
    final categoryCtrl = TextEditingController(text: item.category);
    final purityCtrl = TextEditingController(text: item.purity);
    final weightCtrl = TextEditingController(text: item.weight.toString());
    final editFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Edit Item (${item.barcode})'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: editFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: item.barcode,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (NOT editable)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Item Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Item name required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _categories.contains(categoryCtrl.text) ? categoryCtrl.text : _categories.first,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (val) => categoryCtrl.text = val!,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _purities.contains(purityCtrl.text) ? purityCtrl.text : _purities.first,
                        decoration: const InputDecoration(
                          labelText: 'Purity',
                          border: OutlineInputBorder(),
                        ),
                        items: _purities.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                        onChanged: (val) => purityCtrl.text = val!,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Weight (grams) *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Weight is required';
                    final w = double.tryParse(val.trim());
                    if (w == null || w <= 0) return 'Enter a weight greater than zero';
                    final parts = val.trim().split('.');
                    if (parts.length > 1 && parts[1].length > 3) {
                      return 'Maximum 3 decimal places allowed';
                    }
                    return null;
                  },
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () async {
              if (!editFormKey.currentState!.validate()) return;
              final updatedItem = InventoryItem(
                id: item.id,
                barcode: item.barcode,
                itemName: nameCtrl.text.trim(),
                category: categoryCtrl.text.trim(),
                purity: purityCtrl.text.trim(),
                weight: double.parse(weightCtrl.text.trim()),
                createdAt: item.createdAt,
              );
              try {
                await InventoryDB.updateItem(updatedItem);
                if (ctx.mounted) Navigator.of(ctx).pop();
                _refreshData();
              } catch (e) {
                _showErrorDialog('Database Error', 'Update failed.');
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    final ipCtrl = TextEditingController(text: _printerIp);
    final portCtrl = TextEditingController(text: _printerPort.toString());
    final httpPortCtrl = TextEditingController(text: _httpServerPort.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Settings'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label Printer IP',
                  hintText: '192.168.1.100',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Label Printer Port',
                  hintText: '9100',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: httpPortCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'HTTP Server Port (default 8080)',
                  hintText: '8080',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showAboutDialog();
            },
            child: const Text('About'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () {
              final port = int.tryParse(portCtrl.text.trim()) ?? 9100;
              final httpPort = int.tryParse(httpPortCtrl.text.trim()) ?? 8080;
              Navigator.of(ctx).pop();
              _saveSettings(ipCtrl.text.trim(), port, httpPort);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('About Jewel POS'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jewellery Inventory Management System', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 8),
            Text('Target: Windows Desktop Workstation'),
            Text('Database: SQLite (inventory.db)'),
            Text('Printer Protocol: TSPL Raw (HPRT HT800)'),
            Text('HTTP Server: Port 8080 (Local WiFi API)'),
            SizedBox(height: 8),
            Text('Version 1.0.0 (Production Release)'),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
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

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAllSelected = _filteredItems.isNotEmpty && _filteredItems.every((item) => _selectedBarcodes.contains(item.barcode));

    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.diamond, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              const Text(
                'JEWELLERY INVENTORY MANAGEMENT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                color: const Color(0xFF059669),
                child: Row(
                  children: [
                    const Icon(Icons.wifi, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'HTTP Server Running: ${DesktopHttpServer.serverIp}:${DesktopHttpServer.serverPort}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _backupDatabase,
                icon: const Icon(Icons.backup, color: Colors.white, size: 16),
                label: const Text('Backup DB', style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _restoreDatabase,
                icon: const Icon(Icons.restore, color: Colors.white, size: 16),
                label: const Text('Restore DB', style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _showSettingsDialog,
                icon: const Icon(Icons.settings, color: Colors.white, size: 16),
                label: const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _showAboutDialog,
                icon: const Icon(Icons.info_outline, color: Colors.white, size: 16),
                label: const Text('About', style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT PANEL: Register Jewellery
          SizedBox(
            width: 380,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.only(bottom: 8),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.app_registration, color: Color(0xFF1E293B)),
                          SizedBox(width: 8),
                          Text(
                            'Register Jewellery',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Next Barcode Indicator
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xFFF1F5F9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Next Barcode (Auto-generated)',
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _generatedBarcode,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Item Name Field
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Item Name *',
                        hintText: 'e.g. Gold Necklace',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Item Name is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Category Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _categories.contains(_categoryController.text) ? _categoryController.text : _categories.first,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Category is required' : null,
                      items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setState(() => _categoryController.text = val!),
                    ),
                    const SizedBox(height: 16),

                    // Purity Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _purities.contains(_purityController.text) ? _purityController.text : _purities.first,
                      decoration: const InputDecoration(
                        labelText: 'Purity *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Purity is required' : null,
                      items: _purities.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                      onChanged: (val) => setState(() => _purityController.text = val!),
                    ),
                    const SizedBox(height: 16),

                    // Weight Input Field
                    TextFormField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Weight (grams) *',
                        hintText: 'e.g. 12.350',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Weight is required';
                        final w = double.tryParse(val.trim());
                        if (w == null || w <= 0) return 'Enter a weight greater than zero';
                        final parts = val.trim().split('.');
                        if (parts.length > 1 && parts[1].length > 3) {
                          return 'Maximum 3 decimal places allowed';
                        }
                        return null;
                      },
                    ),
                    const Spacer(),

                    // Action Buttons (Clear, Save Only, Save & Print)
                    Row(
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            side: const BorderSide(color: Color(0xFF64748B)),
                            foregroundColor: const Color(0xFF334155),
                          ),
                          onPressed: _clearForm,
                          child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF334155),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            ),
                            onPressed: _saveOnly,
                            icon: const Icon(Icons.save, size: 16),
                            label: const Text('Save Only', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            ),
                            onPressed: _saveAndPrint,
                            icon: const Icon(Icons.print, size: 16),
                            label: const Text('Save & Print', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const VerticalDivider(width: 1, color: Color(0xFFCBD5E1)),

          // RIGHT PANEL: Inventory Search & Data Table
          Expanded(
            child: Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory, color: Color(0xFF1E293B)),
                        const SizedBox(width: 8),
                        const Text(
                          'Inventory Search',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const Spacer(),
                        if (_selectedBarcodes.isNotEmpty)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            ),
                            onPressed: _printSelectedItems,
                            icon: const Icon(Icons.print, size: 16),
                            label: Text('Print Selected (${_selectedBarcodes.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        if (_selectedBarcodes.isNotEmpty) const SizedBox(width: 12),
                        Text(
                          'Total Items: ${_filteredItems.length}',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Live Search Field
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(_applySearch),
                    decoration: InputDecoration(
                      hintText: 'Search by Barcode, Item Name, or Category...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(_applySearch);
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Data Table view
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredItems.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No Items Found',
                                    style: TextStyle(fontSize: 16, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                                  ),
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: DataTable(
                                    columnSpacing: 24,
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                                    columns: [
                                      DataColumn(
                                        label: Row(
                                          children: [
                                            Checkbox(
                                              value: isAllSelected,
                                              onChanged: (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedBarcodes = _filteredItems.map((i) => i.barcode).toSet();
                                                  } else {
                                                    _selectedBarcodes.clear();
                                                  }
                                                });
                                              },
                                            ),
                                            const Text('Barcode', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                      const DataColumn(label: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Purity', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Weight (g)', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                                    ],
                                    rows: _filteredItems.map((item) {
                                      final isSelected = _selectedBarcodes.contains(item.barcode);
                                      return DataRow(
                                        selected: isSelected,
                                        onSelectChanged: (selected) {
                                          setState(() {
                                            if (selected == true) {
                                              _selectedBarcodes.add(item.barcode);
                                            } else {
                                              _selectedBarcodes.remove(item.barcode);
                                            }
                                          });
                                        },
                                        cells: [
                                          DataCell(
                                            Text(
                                              item.barcode,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(item.itemName)),
                                          DataCell(Text(item.category)),
                                          DataCell(Text(item.purity)),
                                          DataCell(Text(item.weight.toStringAsFixed(3))),
                                          DataCell(
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                                  ),
                                                  onPressed: () => _showEditDialog(item),
                                                  child: const Text('Edit'),
                                                ),
                                                const SizedBox(width: 6),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFF334155),
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                                  ),
                                                  onPressed: () => _reprintLabel(item),
                                                  child: const Text('Reprint'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
