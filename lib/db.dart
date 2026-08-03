import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class InventoryItem {
  final int? id;
  final String barcode;
  final String itemName;
  final String category;
  final String purity;
  final double weight;
  final String createdAt;

  InventoryItem({
    this.id,
    required this.barcode,
    required this.itemName,
    required this.category,
    required this.purity,
    required this.weight,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'barcode': barcode,
      'item_name': itemName,
      'category': category,
      'purity': purity,
      'weight': weight,
      'created_at': createdAt,
    };
  }

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as int?,
      barcode: map['barcode'] as String,
      itemName: map['item_name'] as String,
      category: map['category'] as String,
      purity: map['purity'] as String,
      weight: (map['weight'] as num).toDouble(),
      createdAt: map['created_at'] as String,
    );
  }
}

class PrintLog {
  final int? id;
  final String terminalName;
  final String date;
  final String timestamp;
  final int totalItems;
  final double totalWeight;
  final String itemsJson;

  PrintLog({
    this.id,
    required this.terminalName,
    required this.date,
    required this.timestamp,
    required this.totalItems,
    required this.totalWeight,
    required this.itemsJson,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'terminal_name': terminalName,
      'date': date,
      'timestamp': timestamp,
      'total_items': totalItems,
      'total_weight': totalWeight,
      'items_json': itemsJson,
    };
  }

  factory PrintLog.fromMap(Map<String, dynamic> map) {
    return PrintLog(
      id: map['id'] as int?,
      terminalName: map['terminal_name'] as String? ?? 'Terminal POS',
      date: map['date'] as String? ?? '',
      timestamp: map['timestamp'] as String? ?? '',
      totalItems: (map['total_items'] as num?)?.toInt() ?? 0,
      totalWeight: (map['total_weight'] as num?)?.toDouble() ?? 0.0,
      itemsJson: map['items_json'] as String? ?? '[]',
    );
  }
}

class InventoryDB {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<String> getDatabasePath() async {
    if (kIsWeb) return 'inventory.db';
    try {
      final appDir = await getApplicationSupportDirectory();
      return p.join(appDir.path, 'inventory.db');
    } catch (_) {
      return p.join(Directory.current.path, 'inventory.db');
    }
  }

  static Future<Database> _initDB() async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      return await openDatabase('inventory.db', version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
    } else {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final path = await getDatabasePath();
      return await openDatabase(
        path,
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT UNIQUE,
        item_name TEXT,
        category TEXT,
        purity TEXT,
        weight REAL,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS PrintLogs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        terminal_name TEXT,
        date TEXT,
        timestamp TEXT,
        total_items INTEGER,
        total_weight REAL,
        items_json TEXT
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS PrintLogs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        terminal_name TEXT,
        date TEXT,
        timestamp TEXT,
        total_items INTEGER,
        total_weight REAL,
        items_json TEXT
      )
    ''');
  }

  static Future<String> generateNextBarcode() async {
    final db = await instance;
    final res = await db.rawQuery(
      "SELECT barcode FROM Inventory ORDER BY id DESC LIMIT 1",
    );
    int nextId = 1;
    if (res.isNotEmpty) {
      final lastBarcode = res.first['barcode'] as String? ?? '';
      final numStr = lastBarcode.replaceAll(RegExp(r'[^0-9]'), '');
      if (numStr.isNotEmpty) {
        nextId = (int.tryParse(numStr) ?? 0) + 1;
      }
    }
    return 'JMT${nextId.toString().padLeft(9, '0')}';
  }

  static Future<int> insertItem(InventoryItem item) async {
    final db = await instance;
    return await db.insert('Inventory', item.toMap());
  }

  static Future<int> updateItem(InventoryItem item) async {
    final db = await instance;
    return await db.update(
      'Inventory',
      {
        'item_name': item.itemName,
        'category': item.category,
        'purity': item.purity,
        'weight': item.weight,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  static Future<int> deleteItem(int id) async {
    final db = await instance;
    return await db.delete('Inventory', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<InventoryItem>> getAllItems() async {
    final db = await instance;
    final res = await db.query('Inventory', orderBy: 'id DESC');
    return res.map((map) => InventoryItem.fromMap(map)).toList();
  }

  static Future<List<InventoryItem>> searchItems(String query) async {
    final db = await instance;
    final q = '%${query.trim().toLowerCase()}%';
    final res = await db.rawQuery('''
      SELECT * FROM Inventory 
      WHERE LOWER(barcode) LIKE ? 
         OR LOWER(item_name) LIKE ? 
         OR LOWER(category) LIKE ?
      ORDER BY id DESC
    ''', [q, q, q]);
    return res.map((map) => InventoryItem.fromMap(map)).toList();
  }

  // --- PRINT LOG DATABASE METHODS ---
  static Future<int> insertPrintLog(PrintLog log) async {
    final db = await instance;
    return await db.insert('PrintLogs', log.toMap());
  }

  static Future<List<PrintLog>> getPrintLogsByDate(String date) async {
    final db = await instance;
    final res = await db.query(
      'PrintLogs',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id DESC',
    );
    return res.map((map) => PrintLog.fromMap(map)).toList();
  }

  static Future<List<String>> getDistinctPrintDates() async {
    final db = await instance;
    final res = await db.rawQuery('SELECT DISTINCT date FROM PrintLogs ORDER BY date DESC');
    return res.map((row) => row['date'] as String? ?? '').where((d) => d.isNotEmpty).toList();
  }

  static Future<String> backupDatabase() async {
    if (kIsWeb) {
      return "Web Local Storage (inventory.db backed up)";
    }
    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception("Database file does not exist yet.");
    }

    final parentDir = dbFile.parent.path;
    final backupsDir = Directory(p.join(parentDir, 'Backups'));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }

    final now = DateTime.now();
    final timestamp = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_"
        "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    final backupFileName = 'inventory_$timestamp.db';
    final destinationPath = p.join(backupsDir.path, backupFileName);

    await dbFile.copy(destinationPath);
    return destinationPath;
  }

  static Future<List<File>> getBackupFiles() async {
    if (kIsWeb) return [];
    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);
    final parentDir = dbFile.parent.path;
    final backupsDir = Directory(p.join(parentDir, 'Backups'));
    if (!await backupsDir.exists()) return [];

    final list = backupsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList();
    list.sort((a, b) => b.path.compareTo(a.path));
    return list;
  }

  static Future<void> restoreDatabase(File backupFile) async {
    if (kIsWeb) return;
    if (!await backupFile.exists()) {
      throw Exception("Selected backup file does not exist.");
    }
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }

    final dbPath = await getDatabasePath();
    await backupFile.copy(dbPath);
    _db = await _initDB();
  }
}
