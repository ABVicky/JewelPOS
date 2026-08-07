<div align="center">

# 💎 Jewel POS
### A Dual-Platform Jewellery Point-of-Sale & Inventory Management System

[![Build Status](https://github.com/ABVicky/JewelPOS/actions/workflows/build.yml/badge.svg)](https://github.com/ABVicky/JewelPOS/actions/workflows/build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-brightgreen)](https://github.com/ABVicky/JewelPOS)
[![License](https://img.shields.io/badge/License-Proprietary-red)](https://www.manikarnikatechnologies.in)

**Designed & Developed by [Manikarnika Technologies](https://www.manikarnikatechnologies.in)**

</div>

---

## 📖 Overview

**Jewel POS** is a production-grade, dual-platform Point-of-Sale and Inventory Management System purpose-built for jewellery retail businesses. It consists of two tightly integrated applications running on a shared local Wi-Fi network:

| Application | Platform | Role |
|---|---|---|
| **Workstation App** | Windows Desktop | Central inventory management, barcode label printing, and HTTP server host |
| **HandPOS App** | Android | Mobile billing terminal — scans barcodes and prints customer receipts |

Both apps are compiled from a **single Flutter codebase** that intelligently switches its UI and behaviour based on the target platform at runtime.

---

## ✨ Key Features

### 🖥️ Windows Workstation App

| Feature | Description |
|---|---|
| **Inventory Registration** | Add jewellery items with name, category (Pure Gold / With Stone / Others), purity (e.g. 22K), and weight in grams |
| **Auto Barcode Generation** | Each item is assigned a unique sequential barcode in the format `JMT000000001` automatically |
| **Barcode Label Printing** | Generates 38mm × 25mm PDF labels with Code-128 barcode using the system's native print dialog |
| **Batch Label Printing** | Select multiple items by checkbox or serial range and print all labels in a single print job |
| **Inventory Table & Search** | Full-text search across barcode, item name, and category; numeric serial range filter (e.g. `400-600`) |
| **Edit Items** | Update item name, category, purity, and weight inline via a dialog (barcode is immutable) |
| **Delete Items** | Delete single items or bulk-delete selected items with confirmation |
| **CSV / Excel Export** | Export the entire inventory to a UTF-8 BOM `.csv` file compatible with Microsoft Excel |
| **Database Backup & Restore** | One-click timestamped `.db` backup; restore from any backup with a single tap |
| **Day-Wise Print Log Report** | View terminal-wise receipt print statistics for any date; printable 58mm PDF day-end report |
| **Embedded HTTP Server** | Serves the Android HandPOS terminals on port `8080` over local Wi-Fi |
| **Terminal Monitor** | Live view of all connected Android HandPOS terminals and their online status |

### 📱 Android HandPOS App

| Feature | Description |
|---|---|
| **Barcode Scanning** | Supports both camera-based scanning (ML Kit) and hardware laser scanner input |
| **Auto Desktop Discovery** | Automatically scans the entire local subnet (192.168.x.x / 10.x.x.x) to find the Windows workstation |
| **Real-time Item Lookup** | Fetches item details (name, category, purity, weight) from the Desktop over HTTP in under 3 seconds |
| **Duplicate Scan Detection** | Prompts the user before adding an already-scanned item to the bill |
| **Receipt Generation & Printing** | Generates a 58mm thermal receipt PDF with logo, itemised table, carat-wise weight summary |
| **Built-in Thermal Printer** | Sends receipts directly to a network thermal printer (e.g. Smart POS 1008 on `127.0.0.1:9100`) |
| **Auto-print on Scan** | Optional mode: automatically prints a receipt every time a barcode is scanned |
| **Heartbeat Ping** | Sends a connectivity heartbeat to the Desktop every 6 seconds for live terminal tracking |
| **Print Log Sync** | After every receipt print, the log is posted to the Desktop's central database |
| **Offline Fallback** | Reads from local SQLite cache when Desktop connection is unavailable |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Local Wi-Fi Network                          │
│                                                                 │
│   ┌──────────────────────────┐    HTTP :8080    ┌────────────┐  │
│   │  Windows Workstation     │◄────────────────►│ Android    │  │
│   │  (Inventory Manager)     │                  │ HandPOS    │  │
│   │                          │                  │ Terminal 1 │  │
│   │  ┌────────────────────┐  │                  └────────────┘  │
│   │  │  SQLite Database   │  │                  ┌────────────┐  │
│   │  │  (inventory.db)    │  │◄────────────────►│ Android    │  │
│   │  └────────────────────┘  │                  │ HandPOS    │  │
│   │                          │                  │ Terminal 2 │  │
│   │  ┌────────────────────┐  │                  └────────────┘  │
│   │  │  HTTP Server       │  │                       ...        │
│   │  │  Port 8080         │  │                                  │
│   │  └────────────────────┘  │                                  │
│   └──────────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Project File Structure

```
jewel_pos/
├── lib/
│   ├── main.dart           # App entry point — platform detection & routing
│   ├── windows_ui.dart     # Windows Workstation UI (~1,770 lines)
│   ├── android_ui.dart     # Android HandPOS UI (~1,834 lines)
│   ├── db.dart             # SQLite database layer (InventoryDB, models)
│   ├── printer.dart        # PDF label & receipt generation (TSPLPrinter)
│   └── server_helper.dart  # Embedded HTTP server (DesktopHttpServer)
├── assets/
│   └── images/
│       ├── logo.png        # App icon
│       └── jewel_logo.png  # Receipt header logo
├── android/                # Android platform project
├── windows/                # Windows platform project
└── .github/
    └── workflows/
        └── build.yml       # CI/CD: Build Windows EXE & Android APK
```

---

## 🗄️ Database Schema

The app uses a **SQLite** database (`inventory.db`) stored in the application support directory.

### `Inventory` Table

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Auto-increment primary key |
| `barcode` | TEXT UNIQUE | Unique barcode (e.g. `JMT000000001`) |
| `item_name` | TEXT | Jewellery item name |
| `category` | TEXT | Category (Pure Gold / With Stone / Others / custom) |
| `purity` | TEXT | Gold purity (e.g. `22K`, `18K`) |
| `weight` | REAL | Weight in grams (3 decimal precision) |
| `created_at` | TEXT | ISO 8601 timestamp of registration |

### `PrintLogs` Table

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Auto-increment primary key |
| `terminal_name` | TEXT | Name of the HandPOS terminal |
| `date` | TEXT | Date string `YYYY-MM-DD` |
| `timestamp` | TEXT | ISO 8601 full timestamp |
| `total_items` | INTEGER | Number of items on the receipt |
| `total_weight` | REAL | Total net weight billed (grams) |
| `items_json` | TEXT | Full JSON snapshot of items on the receipt |

---

## 🌐 HTTP API Reference

The Windows Workstation hosts a lightweight HTTP server on **port 8080** that the Android terminals communicate with.

### Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Health check — returns `OK` if server is running |
| `GET/POST` | `/ping` | Terminal heartbeat & registration |
| `GET` | `/terminals` | List all connected HandPOS terminals |
| `GET` | `/item/{barcode}` | Look up a jewellery item by barcode |
| `POST` | `/print-log` | Save a receipt print event to the central database |
| `GET` | `/print-logs?date=YYYY-MM-DD` | Fetch all print logs for a specific date |

#### `POST /ping` — Request Body
```json
{
  "id": "POS-1008",
  "name": "Smart POS 1008 HandPOS"
}
```

#### `GET /item/{barcode}` — Response
```json
{
  "barcode": "JMT000000042",
  "item_name": "Gold Ring",
  "category": "Pure Gold",
  "purity": "22K",
  "weight": 5.320
}
```

#### `POST /print-log` — Request Body
```json
{
  "terminal_name": "Smart POS 1008 HandPOS",
  "date": "2026-08-07",
  "timestamp": "2026-08-07T10:30:00.000Z",
  "total_items": 3,
  "total_weight": 14.250,
  "items_json": "[{...}]"
}
```

---

## ⚙️ Setup & Installation

### Prerequisites

| Requirement | Version |
|---|---|
| Flutter SDK | 3.x stable |
| Dart SDK | ^3.11.5 |
| Java Development Kit | 17 (for Android builds) |
| Android SDK | API 21+ |
| Windows | Windows 10/11 (64-bit) |

### 1. Clone the Repository

```bash
git clone https://github.com/ABVicky/JewelPOS.git
cd JewelPOS
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run the Application

**Windows Workstation:**
```bash
flutter run -d windows
```

**Android HandPOS (connected device or emulator):**
```bash
flutter run -d android
```

### 4. Build Release Binaries

**Windows Executable:**
```bash
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

**Android APK:**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## 🔧 Configuration

### Windows Workstation

The HTTP server starts automatically on app launch and binds to all IPv4 interfaces on **port 8080**. The workstation's local IP is auto-detected and displayed in the Terminal Monitor panel.

> **Firewall Note:** Ensure Windows Firewall allows inbound connections on TCP port 8080 from the local network.

### Android HandPOS

On first launch, the app will automatically scan the local subnet for an active Desktop workstation. You can also configure settings manually:

| Setting | Default | Description |
|---|---|---|
| Desktop IP | Auto-detected | IP address of the Windows workstation |
| Printer IP | `127.0.0.1` | IP of the network thermal printer |
| Printer Port | `9100` | TCP port of the thermal printer |
| Terminal Name | `Smart POS 1008 HandPOS` | Display name for this HandPOS unit |
| Terminal ID | `POS-1008` | Unique identifier for this terminal |
| Auto-print on Scan | Off | Automatically print after each scan |

---

## 🖨️ Printing

### Barcode Labels (Windows)

- **Label Size:** 38mm × 25mm
- **Format:** PDF via Windows native print dialog
- **Content:** Item name, category, purity, weight, and Code-128 barcode

### Customer Receipts (Android)

- **Paper Width:** 58mm thermal roll
- **Format:** PDF via Android print framework
- **Content:** Store logo, itemised table (name, qty, carat, weight), carat-wise weight summary, total items and total net weight

### Day-End Report (Windows)

- **Paper Width:** 58mm
- **Format:** PDF
- **Content:** Date, total receipts printed, total items billed, total weight, terminal-wise breakdown, individual receipt log

---

## 🔄 CI/CD Pipeline

Automated builds run on every push and pull request to `main` / `master` via GitHub Actions.

| Job | Runner | Output |
|---|---|---|
| Build Windows Executable | `windows-latest` | `JewelPOS-Windows-Executable` artifact |
| Build Android APK | `ubuntu-latest` | `JewelPOS-Android-APK` artifact |

**Workflow file:** [`.github/workflows/build.yml`](.github/workflows/build.yml)

---

## 📦 Dependencies

| Package | Version | Purpose |
|---|---|---|
| `sqflite` | ^2.4.2+1 | SQLite database (Android) |
| `sqflite_common_ffi` | ^2.4.0+3 | SQLite database (Windows/Desktop) |
| `sqflite_common_ffi_web` | ^1.1.1 | SQLite database (Web fallback) |
| `path_provider` | ^2.1.6 | Platform-specific file paths |
| `path` | ^1.9.1 | Cross-platform path utilities |
| `http` | ^1.6.0 | HTTP client for Android → Desktop API calls |
| `shared_preferences` | ^2.5.5 | Persistent settings storage |
| `mobile_scanner` | ^7.4.0 | Camera-based barcode scanner (ML Kit) |
| `barcode_widget` | ^2.0.4 | Barcode rendering widget |
| `pdf` | ^3.11.1 | PDF document generation |
| `printing` | ^5.13.4 | Native print dialog & PDF layout |
| `flutter_lints` | any | Static analysis & lint rules |

---

## 🗂️ Data Management

### Database File Location

| Platform | Path |
|---|---|
| Windows | `%AppData%\Roaming\<app>\inventory.db` |
| Android | `/data/data/com.example.jewel_pos/...` |

### Backup Files
Stored in: `<db_directory>/Backups/inventory_YYYYMMDD_HHMMSS.db`

### CSV Exports
Stored in: `<db_directory>/Exports/inventory_export_YYYYMMDD_HHMMSS.csv`

---

## 🚀 Multi-Terminal Deployment

JewelPOS supports multiple Android HandPOS terminals operating simultaneously against a single Windows Workstation:

1. Ensure all devices are on the **same Wi-Fi network**
2. Launch the Windows Workstation app — the HTTP server starts automatically
3. Launch the Android HandPOS app on each tablet/phone — they will auto-discover the Desktop
4. All terminals are tracked in real-time in the Terminal Monitor panel on the Desktop
5. Print logs from all terminals are aggregated into the central database for day-end reporting

---

## 🛡️ Security & Network Notes

- The HTTP server uses **no authentication** — it is intended for use on a **private, trusted local network only**
- CORS headers are set to `*` to allow all local requests
- The server binds to `0.0.0.0` (all interfaces) on port 8080
- Terminal heartbeat interval: **6 seconds**; a terminal is considered offline after **15 seconds** without a ping

---

## 📄 License

This project is **proprietary software** developed exclusively by **Manikarnika Technologies**.  
All rights reserved. Unauthorized copying, distribution, or modification is strictly prohibited.

> 🌐 **Website:** [https://www.manikarnikatechnologies.in](https://www.manikarnikatechnologies.in)

---

<div align="center">
Made with ❤️ by <a href="https://www.manikarnikatechnologies.in">Manikarnika Technologies</a>
</div>
