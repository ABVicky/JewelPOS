import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barcode_widget/barcode_widget.dart';
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

  // Inventory Registration Controllers
  final _nameController = TextEditingController();
  final List<String> _categoryOptions = ['Pure Gold', 'With Stone', 'Others'];
  String _selectedCategoryOption = 'Pure Gold';
  final _customCategoryController = TextEditingController();

  final _purityNumberController = TextEditingController(text: '22');
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
  String _printerUsbPort = 'COM3';
  int _httpServerPort = 8080;

  String get _finalCategory {
    if (_selectedCategoryOption == 'Others') {
      final custom = _customCategoryController.text.trim();
      return custom.isEmpty ? 'Others' : custom;
    }
    return _selectedCategoryOption;
  }

  String get _finalPurity {
    final raw = _purityNumberController.text.trim();
    if (raw.isEmpty) return '22K';
    if (raw.toUpperCase().endsWith('K')) {
      return raw.toUpperCase();
    }
    return '${raw}K';
  }

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
        _printerUsbPort = prefs.getString('printer_usb_port') ?? 'COM3';
        _httpServerPort = prefs.getInt('http_server_port') ?? 8080;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings(String ip, int port, String usbPort, int httpPort) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_ip', ip);
      await prefs.setInt('printer_port', port);
      await prefs.setString('printer_usb_port', usbPort);
      await prefs.setInt('http_server_port', httpPort);
      setState(() {
        _printerIp = ip;
        _printerPort = port;
        _printerUsbPort = usbPort;
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
    _customCategoryController.clear();
    _purityNumberController.text = '22';
    setState(() {
      _selectedCategoryOption = 'Pure Gold';
    });
    _refreshData();
  }

  Future<void> _saveOnly() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final category = _finalCategory;
    final purity = _finalPurity;
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
    final category = _finalCategory;
    final purity = _finalPurity;
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
      usbPortName: _printerUsbPort,
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
    bool printSuccess = await TSPLPrinter.sendTSPLToPrinter(
      item,
      host: _printerIp,
      port: _printerPort,
      usbPortName: _printerUsbPort,
    );

    if (!mounted) return;

    if (printSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Label printed for item ${item.barcode}.'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } else {
      _showErrorDialog(
        'Printer Disconnected',
        'Could not connect to TSPL printer at IP: $_printerIp Port: $_printerPort.\nPlease verify printer connection or update Printer IP in Settings.',
      );
    }
  }

  Future<void> _printSelectedLabels() async {
    if (_selectedBarcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items selected for printing.')),
      );
      return;
    }

    final itemsToPrint = _allItems.where((item) => _selectedBarcodes.contains(item.barcode)).toList();
    int printedCount = 0;
    int failedCount = 0;

    for (var item in itemsToPrint) {
      bool ok = await TSPLPrinter.sendTSPLToPrinter(
        item,
        host: _printerIp,
        port: _printerPort,
        usbPortName: _printerUsbPort,
      );
      if (ok) {
        printedCount++;
      } else {
        failedCount++;
      }
    }

    if (!mounted) return;

    if (failedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully printed $printedCount selected label(s).'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } else if (printedCount > 0) {
      _showErrorDialog(
        'Partial Print Result',
        'Printed $printedCount label(s). Failed $failedCount label(s) because printer disconnected.',
      );
    } else {
      _showErrorDialog(
        'Printer Disconnected',
        'Could not print $failedCount selected label(s). Printer unreachable at IP: $_printerIp Port: $_printerPort.',
      );
    }
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete item "${item.itemName}" (${item.barcode})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && item.id != null) {
      try {
        await InventoryDB.deleteItem(item.id!);
        _selectedBarcodes.remove(item.barcode);
        await _refreshData();
      } catch (e) {
        _showErrorDialog('Delete Error', 'Could not delete item.');
      }
    }
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

  Future<void> _backupDatabase() async {
    try {
      final destPath = await InventoryDB.backupDatabase();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Database backed up successfully to $destPath'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      _showErrorDialog('Backup Failed', 'Could not backup database: $e');
    }
  }

  Future<void> _restoreDatabase() async {
    try {
      final files = await InventoryDB.getBackupFiles();

      if (files.isEmpty) {
        _showErrorDialog('No Backups Found', 'No backup files found in backup directory.');
        return;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text('Select Backup to Restore'),
          content: SizedBox(
            width: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (c, i) {
                final file = files[i];
                final name = file.path.split(Platform.pathSeparator).last;
                return ListTile(
                  title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('Modified: ${file.lastModifiedSync()}'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await InventoryDB.restoreDatabase(file);
                    await _refreshData();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Database restored from $name'),
                        backgroundColor: Colors.green.shade800,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Restore Failed', 'Database restore failed: $e');
    }
  }

  void _showEditDialog(InventoryItem item) {
    final nameCtrl = TextEditingController(text: item.itemName);
    String selCatOpt = _categoryOptions.contains(item.category) ? item.category : 'Others';
    final customCatCtrl = TextEditingController(text: _categoryOptions.contains(item.category) ? '' : item.category);

    final rawPurity = item.purity.replaceAll(RegExp(r'[^0-9]'), '');
    final purityNumCtrl = TextEditingController(text: rawPurity.isEmpty ? '22' : rawPurity);
    final weightCtrl = TextEditingController(text: item.weight.toStringAsFixed(4));
    final editFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
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
                  DropdownButtonFormField<String>(
                    initialValue: selCatOpt,
                    decoration: const InputDecoration(
                      labelText: 'Category / Type *',
                      border: OutlineInputBorder(),
                    ),
                    items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDlgState(() => selCatOpt = val);
                      }
                    },
                  ),
                  if (selCatOpt == 'Others') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: customCatCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Custom Type / Category *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) => (selCatOpt == 'Others' && (val == null || val.trim().isEmpty))
                          ? 'Custom category required'
                          : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: purityNumCtrl,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: 'Purity *',
                      suffixText: 'K',
                      hintText: 'e.g. 24 or 22',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Purity required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Weight (grams) *',
                      hintText: 'e.g. 19.1000',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Weight is required';
                      final w = double.tryParse(val.trim());
                      if (w == null || w <= 0) return 'Enter a weight greater than zero';
                      final parts = val.trim().split('.');
                      if (parts.length > 1 && parts[1].length > 4) {
                        return 'Maximum 4 decimal places allowed';
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
                final finalCat = selCatOpt == 'Others'
                    ? (customCatCtrl.text.trim().isEmpty ? 'Others' : customCatCtrl.text.trim())
                    : selCatOpt;

                final rawP = purityNumCtrl.text.trim();
                final finalP = rawP.toUpperCase().endsWith('K') ? rawP.toUpperCase() : '${rawP}K';

                final updatedItem = InventoryItem(
                  id: item.id,
                  barcode: item.barcode,
                  itemName: nameCtrl.text.trim(),
                  category: finalCat,
                  purity: finalP,
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
      ),
    );
  }

  void _showSettingsDialog() async {
    final ipCtrl = TextEditingController(text: _printerIp);
    final portCtrl = TextEditingController(text: _printerPort.toString());
    final usbPortCtrl = TextEditingController(text: _printerUsbPort);
    final httpPortCtrl = TextEditingController(text: _httpServerPort.toString());

    List<String> installedPrinters = [];
    try {
      installedPrinters = await TSPLPrinter.getInstalledWindowsPrinters();
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Row(
            children: [
              Icon(Icons.print, color: Color(0xFF0F172A)),
              SizedBox(width: 8),
              Text('Label Printer & Network Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('USB Label Printer (HPRT HT800)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (installedPrinters.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: installedPrinters.contains(usbPortCtrl.text.trim()) ? usbPortCtrl.text.trim() : null,
                      decoration: const InputDecoration(
                        labelText: 'Select Installed Windows USB Printer',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      hint: const Text('Select Installed Printer Driver...'),
                      items: installedPrinters.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDlgState(() => usbPortCtrl.text = val);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: usbPortCtrl,
                    decoration: const InputDecoration(
                      labelText: 'USB Printer / COM Port / Driver Name',
                      hintText: 'e.g. HPRT HT800, HPRT, or COM3',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(40),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                    onPressed: () async {
                      final testItem = InventoryItem(
                        barcode: 'TEST1008',
                        itemName: 'Test Ring',
                        category: 'Test',
                        purity: '22K',
                        weight: 1.0000,
                      );
                      final testOk = await TSPLPrinter.sendTSPLToPrinter(
                        testItem,
                        host: ipCtrl.text.trim(),
                        port: int.tryParse(portCtrl.text.trim()) ?? 9100,
                        usbPortName: usbPortCtrl.text.trim(),
                      );
                      if (!ctx.mounted) return;
                      if (testOk) {
                        showDialog(
                          context: ctx,
                          builder: (c2) => AlertDialog(
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            title: const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Printer Connected!'),
                              ],
                            ),
                            content: Text('Test label printed successfully on "${usbPortCtrl.text.trim()}".'),
                            actions: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                onPressed: () => Navigator.of(c2).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      } else {
                        showDialog(
                          context: ctx,
                          builder: (c2) => AlertDialog(
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            title: const Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Printer Disconnected'),
                              ],
                            ),
                            content: Text(
                              'Could not send test label to "${usbPortCtrl.text.trim()}".\n\n1. Verify USB cable is plugged into PC.\n2. Ensure HPRT HT800 driver is turned ON in Windows.\n3. Try selecting your printer name from dropdown.',
                            ),
                            actions: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                onPressed: () => Navigator.of(c2).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Test Print TSPL Label', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Ethernet Network Printer (Optional IP)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: ipCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ethernet Printer IP',
                      hintText: '192.168.1.100',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: portCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ethernet Printer Port',
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
                _saveSettings(ipCtrl.text.trim(), port, usbPortCtrl.text.trim(), httpPort);
              },
              child: const Text('Save'),
            ),
          ],
        ),
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

  void _showConnectedTerminalsDialog() {
    final terminals = DesktopHttpServer.getConnectedTerminals();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Row(
          children: [
            const Icon(Icons.phonelink, color: Color(0xFF1E293B)),
            const SizedBox(width: 8),
            Text('Paired POS Terminals (${terminals.where((t) => t.isOnline).length} Active)'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: terminals.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No POS Terminals connected yet.\nConnect Android HandPOS devices using Desktop IP: ${DesktopHttpServer.serverIp}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: terminals.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final t = terminals[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.circle,
                        color: t.isOnline ? Colors.green : Colors.grey,
                        size: 14,
                      ),
                      title: Text(
                        t.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('IP: ${t.ip}  |  ID: ${t.id}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        color: t.isOnline ? Colors.green.shade100 : Colors.grey.shade200,
                        child: Text(
                          t.isOnline ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            color: t.isOnline ? Colors.green.shade900 : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  },
                ),
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

  void _showBarcodeDetailsDialog(InventoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Row(
          children: [
            const Icon(Icons.qr_code_2, color: Color(0xFF0F172A), size: 24),
            const SizedBox(width: 8),
            Text('Barcode Details (${item.barcode})'),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  children: [
                    BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: item.barcode,
                      width: 290,
                      height: 85,
                      drawText: true,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    BarcodeWidget(
                      barcode: Barcode.qrCode(),
                      data: item.barcode,
                      width: 90,
                      height: 90,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scannable Barcode Tag — Point HandPOS Laser or Camera at Screen',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(2),
                },
                children: [
                  TableRow(children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Item Name:', style: TextStyle(fontWeight: FontWeight.bold))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(item.itemName)),
                  ]),
                  TableRow(children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Category:', style: TextStyle(fontWeight: FontWeight.bold))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(item.category)),
                  ]),
                  TableRow(children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Purity:', style: TextStyle(fontWeight: FontWeight.bold))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(item.purity)),
                  ]),
                  TableRow(children: [
                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Weight:', style: TextStyle(fontWeight: FontWeight.bold))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${item.weight.toStringAsFixed(4)} g')),
                  ]),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _reprintLabel(item);
            },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('Print Label'),
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
                onPressed: _showConnectedTerminalsDialog,
                icon: const Icon(Icons.phonelink, color: Colors.white, size: 16),
                label: Text('Terminals (${DesktopHttpServer.activeOnlineTerminalsCount})', style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const SizedBox(width: 4),
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

                    // 1. Item Name Field
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Item Name *',
                        hintText: 'e.g. Ring / Gold Necklace',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Item Name is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // 2. Category / Type Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategoryOption,
                      decoration: const InputDecoration(
                        labelText: 'Category / Type *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedCategoryOption = val;
                          });
                        }
                      },
                    ),
                    if (_selectedCategoryOption == 'Others') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _customCategoryController,
                        decoration: const InputDecoration(
                          labelText: 'Custom Type / Category *',
                          hintText: 'e.g. Antique Bangle',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        validator: (val) => (_selectedCategoryOption == 'Others' && (val == null || val.trim().isEmpty))
                            ? 'Please enter custom type'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 16),

                    // 3. Purity Input Field (Number + K placed)
                    TextFormField(
                      controller: _purityNumberController,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'Purity *',
                        suffixText: 'K',
                        hintText: 'e.g. 24 or 22',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Purity is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // 4. Weight (grams) Field (4 digits after .)
                    TextFormField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Weight (grams) *',
                        hintText: 'e.g. 19.1000',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Weight is required';
                        final w = double.tryParse(val.trim());
                        if (w == null || w <= 0) return 'Enter a weight greater than zero';
                        final parts = val.trim().split('.');
                        if (parts.length > 1 && parts[1].length > 4) {
                          return 'Maximum 4 decimal places allowed';
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

          // VERTICAL SEPARATOR
          const VerticalDivider(width: 1, color: Color(0xFFCBD5E1)),

          // RIGHT PANEL: Inventory Search & Data Table
          Expanded(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: _printSelectedLabels,
                          icon: const Icon(Icons.print, size: 16),
                          label: Text('Print Selected Labels (${_selectedBarcodes.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 12),
                      Text(
                        'Total Items: ${_filteredItems.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search Bar
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() => _applySearch()),
                    decoration: InputDecoration(
                      hintText: 'Search by Barcode, Item Name, or Category...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _applySearch());
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Inventory Table
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _filteredItems.isEmpty
                            ? const Center(
                                child: Text(
                                  'No items found in inventory database.',
                                  style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                                    dataRowMinHeight: 48,
                                    dataRowMaxHeight: 48,
                                    columns: [
                                      DataColumn(
                                        label: Checkbox(
                                          value: isAllSelected,
                                          onChanged: (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedBarcodes = _filteredItems.map((e) => e.barcode).toSet();
                                              } else {
                                                _selectedBarcodes.clear();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                      const DataColumn(label: Text('Barcode', style: TextStyle(fontWeight: FontWeight.bold))),
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
                                            Checkbox(
                                              value: isSelected,
                                              onChanged: (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedBarcodes.add(item.barcode);
                                                  } else {
                                                    _selectedBarcodes.remove(item.barcode);
                                                  }
                                                });
                                              },
                                            ),
                                          ),
                                          DataCell(
                                            Tooltip(
                                              message: 'Click to view barcode & QR code',
                                              child: InkWell(
                                                onTap: () => _showBarcodeDetailsDialog(item),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.qr_code, size: 16, color: Color(0xFF0F172A)),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      item.barcode,
                                                      style: const TextStyle(
                                                        fontFamily: 'monospace',
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(item.itemName)),
                                          DataCell(Text(item.category)),
                                          DataCell(Text(item.purity)),
                                          DataCell(Text(item.weight.toStringAsFixed(4))),
                                          DataCell(
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.visibility, size: 18, color: Color(0xFF0F172A)),
                                                  tooltip: 'View Barcode Details',
                                                  onPressed: () => _showBarcodeDetailsDialog(item),
                                                ),
                                                OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                                  ),
                                                  onPressed: () => _showEditDialog(item),
                                                  child: const Text('Edit', style: TextStyle(fontSize: 12)),
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
                                                  child: const Text('Reprint', style: TextStyle(fontSize: 12)),
                                                ),
                                                const SizedBox(width: 6),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                                  tooltip: 'Delete Item',
                                                  onPressed: () => _deleteItem(item),
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
