/*
 * Designed and Developed by Manikarnika Technologies
 * Website: https://www.manikarnikatechnologies.in
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
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
  final _rangeFromController = TextEditingController();
  final _rangeToController = TextEditingController();
  List<InventoryItem> _allItems = [];
  List<InventoryItem> _filteredItems = [];
  Set<String> _selectedBarcodes = {};
  bool _isLoading = true;

  // Settings State
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

  @override
  void dispose() {
    _nameController.dispose();
    _customCategoryController.dispose();
    _purityNumberController.dispose();
    _weightController.dispose();
    _searchController.dispose();
    _rangeFromController.dispose();
    _rangeToController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _httpServerPort = prefs.getInt('http_server_port') ?? 8080;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings(int httpPort) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('http_server_port', httpPort);
      setState(() {
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

  int? _getBarcodeNumericValue(String barcode) {
    final numStr = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (numStr.isEmpty) return null;
    return int.tryParse(numStr);
  }

  int _getSerialNumber(InventoryItem item) {
    final numVal = _getBarcodeNumericValue(item.barcode);
    if (numVal != null) return numVal;
    return item.id ?? 0;
  }

  void _applySearch() {
    final rawQuery = _searchController.text.trim();
    final query = rawQuery.toLowerCase();

    int? fromRange = int.tryParse(_rangeFromController.text.trim());
    int? toRange = int.tryParse(_rangeToController.text.trim());

    // Auto-detect hyphenated range pattern in search query e.g. "400-600"
    final rangeMatch = RegExp(r'^(?:[A-Za-z]*)(\d+)\s*-\s*(?:[A-Za-z]*)(\d+)$').firstMatch(rawQuery);
    if (rangeMatch != null) {
      fromRange = int.tryParse(rangeMatch.group(1)!);
      toRange = int.tryParse(rangeMatch.group(2)!);
    }

    if (query.isEmpty && fromRange == null && toRange == null) {
      _filteredItems = List.from(_allItems);
    } else {
      _filteredItems = _allItems.where((item) {
        final slNo = _getSerialNumber(item);

        // Apply numeric serial number range filter if set
        if (fromRange != null || toRange != null) {
          if (fromRange != null && slNo < fromRange) return false;
          if (toRange != null && slNo > toRange) return false;
        }

        if (rangeMatch != null) return true;
        if (query.isEmpty) return true;

        return item.barcode.toLowerCase().contains(query) ||
            item.itemName.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query) ||
            item.purity.toLowerCase().contains(query) ||
            slNo.toString() == query;
      }).toList();
    }
  }

  void _selectRange() {
    final from = int.tryParse(_rangeFromController.text.trim());
    final to = int.tryParse(_rangeToController.text.trim());
    if (from == null && to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a From or To Serial Number range.')),
      );
      return;
    }

    setState(() {
      for (final item in _allItems) {
        final slNo = _getSerialNumber(item);
        bool match = true;
        if (from != null && slNo < from) match = false;
        if (to != null && slNo > to) match = false;
        if (match) {
          _selectedBarcodes.add(item.barcode);
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Selected all items in Serial No. range ${from ?? ''} - ${to ?? ''}.'),
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
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

    // 2. Direct label printing
    bool printSuccess = await TSPLPrinter.sendTSPLToPrinter(item);

    if (!mounted) return;

    if (printSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item "$name" saved & label printed ($barcode).'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item "$name" saved to inventory database ($barcode).'),
          backgroundColor: const Color(0xFF0F172A),
        ),
      );
    }
  }

  Future<void> _reprintLabel(InventoryItem item) async {
    bool printSuccess = await TSPLPrinter.sendTSPLToPrinter(item);

    if (!mounted) return;

    if (printSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Label printed for item ${item.barcode}.'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not print label for item ${item.barcode}.'),
          backgroundColor: Colors.red.shade800,
        ),
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
    bool ok = await TSPLPrinter.sendMultipleTSPLToPrinter(itemsToPrint);

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening print window for ${itemsToPrint.length} selected label(s)...'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    }
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedBarcodes.isEmpty) return;

    final count = _selectedBarcodes.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Delete $count Selected Item(s)?', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to permanently delete $count selected item(s) from the inventory database? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final deleted = await InventoryDB.deleteItemsByBarcodes(_selectedBarcodes.toList());
        setState(() {
          _selectedBarcodes.clear();
        });
        await _refreshData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully deleted $deleted item(s) from database.'),
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      } catch (e) {
        _showErrorDialog('Delete Error', 'Failed to delete selected items: $e');
      }
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
                      Icon(Icons.assessment, color: Color(0xFF1E293B)),
                      SizedBox(width: 8),
                      Text('Day-Wise Terminal Print Log Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  content: SizedBox(
                    width: 550,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Text('Date: ', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(selectedDate, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7), fontSize: 15)),
                              const Spacer(),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E293B),
                                  foregroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                icon: const Icon(Icons.calendar_today, size: 14),
                                label: const Text('Change Date'),
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
                          const SizedBox(height: 12),
                          Container(
                            color: const Color(0xFFF1F5F9),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Receipts Printed:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('${logs.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Items Billed:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('$totalItems', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Net Weight Billed:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('${totalWeight.toStringAsFixed(3)} g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (termCounts.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('Terminal Breakdown:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 6),
                            ...termCounts.entries.map((e) {
                              final wt = (termWeights[e.key] ?? 0.0).toStringAsFixed(3);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                color: Colors.white,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('${e.key} (${e.value} receipts)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                    Text('$wt g', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                  ],
                                ),
                              );
                            }),
                          ],
                          const SizedBox(height: 16),
                          const Text('Receipt Print Logs:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 6),
                          if (logs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Text('No receipt print logs recorded for this date.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            )
                          else
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: logs.length,
                                itemBuilder: (ctx, idx) {
                                  final log = logs[idx];
                                  final dt = DateTime.tryParse(log.timestamp);
                                  final timeStr = dt != null
                                      ? "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}"
                                      : log.timestamp;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.all(8),
                                    color: Colors.white,
                                    child: Row(
                                      children: [
                                        Text('$timeStr  |  ${log.terminalName}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        const Spacer(),
                                        Text('${log.totalItems} items (${log.totalWeight.toStringAsFixed(3)} g)', style: const TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      label: const Text('Print Final Day Report', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _exportDatabaseToExcel() async {
    try {
      final filePath = await InventoryDB.exportDatabaseToExcel();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: const Text('Export Successful', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SelectableText('The inventory database has been successfully exported to Excel format:\n\n$filePath'),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Export Failed', 'Could not export database to Excel: $e');
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
    final weightCtrl = TextEditingController(text: item.weight.toStringAsFixed(3));
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

  void _showSettingsDialog() {
    final httpPortCtrl = TextEditingController(text: _httpServerPort.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Color(0xFF0F172A)),
            SizedBox(width: 8),
            Text('Network & Server Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('HandPOS Sync Server Port', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
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
              final httpPort = int.tryParse(httpPortCtrl.text.trim()) ?? 8080;
              Navigator.of(ctx).pop();
              _saveSettings(httpPort);
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
        title: const Text('About Jewel POS', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 400,
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
              const Text('Jewellery Inventory Management System', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              const Text('Version 1.0.0 (Production Release)', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${item.weight.toStringAsFixed(3)} g')),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset('assets/images/logo.png', height: 26, width: 26, fit: BoxFit.cover),
              ),
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
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: _showConnectedTerminalsDialog,
                        icon: const Icon(Icons.phonelink, color: Colors.white, size: 16),
                        label: Text('Terminals (${DesktopHttpServer.activeOnlineTerminalsCount})', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: _showDailyReportDialog,
                        icon: const Icon(Icons.assessment, color: Colors.white, size: 16),
                        label: const Text('Daily Report', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: _exportDatabaseToExcel,
                        icon: const Icon(Icons.file_download, color: Colors.white, size: 16),
                        label: const Text('Export Excel', style: TextStyle(color: Colors.white, fontSize: 13)),
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
                      if (_selectedBarcodes.isNotEmpty) ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: _printSelectedLabels,
                          icon: const Icon(Icons.print, size: 16),
                          label: Text('Print Selected (${_selectedBarcodes.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade800,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: _deleteSelectedItems,
                          icon: const Icon(Icons.delete_forever, size: 16),
                          label: Text('Delete Selected (${_selectedBarcodes.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                      const SizedBox(width: 12),
                      Text(
                        'Total Items: ${_filteredItems.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Search Bar & Serial Number Range Filter Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() => _applySearch()),
                          decoration: InputDecoration(
                            hintText: 'Search by Name, Category, Barcode, or Serial No. Range (e.g. 400-600)...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: (_searchController.text.isNotEmpty || _rangeFromController.text.isNotEmpty || _rangeToController.text.isNotEmpty)
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _rangeFromController.clear();
                                      _rangeToController.clear();
                                      setState(() => _applySearch());
                                    },
                                  )
                                : null,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _rangeFromController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() => _applySearch()),
                          decoration: const InputDecoration(
                            labelText: 'From Sl. No.',
                            hintText: '400',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _rangeToController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() => _applySearch()),
                          decoration: const InputDecoration(
                            labelText: 'To Sl. No.',
                            hintText: '600',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        onPressed: _selectRange,
                        icon: const Icon(Icons.select_all, size: 16),
                        label: const Text('Select Range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
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
                                    showCheckboxColumn: false,
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
                                      const DataColumn(label: Text('Sl. No.', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Barcode', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Purity', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Weight (g)', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                                    ],
                                    rows: _filteredItems.map((item) {
                                      final isSelected = _selectedBarcodes.contains(item.barcode);
                                      final slNo = _getSerialNumber(item);
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
                                            Text(
                                              '$slNo',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                                          DataCell(Text(item.weight.toStringAsFixed(3))),
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
