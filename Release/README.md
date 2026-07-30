# JEWEL POS V2 - Production Release

Jewel POS V2 is an offline Jewellery Inventory Management and HandPOS solution designed for jewellery shop owners.

## System Overview

1. **Windows Workstation App (`JewelPOS_Setup.exe`)**:
   - Register jewellery items with auto-generated barcodes (`JMT000000001`).
   - Print TSPL barcode labels on HPRT HT800 label printer (38mm x 25mm).
   - Search, edit, and reprint inventory labels.
   - Built-in automatic HTTP server (Port 8080) for Android connectivity.
   - One-click Database Backup & Restore (`inventory.db`).

2. **Android HandPOS App (`JewelPOS.apk`)**:
   - Mobile barcode scanning via laser scanner, camera, or manual entry.
   - Real-time stock lookup over Local WiFi via HTTP.
   - ESC/POS thermal receipt printing.
   - Automatic totals calculation (Total Items & Total Weight).

## Hardware Requirements
- **Windows Workstation**: Windows 10/11 Desktop PC.
- **Label Printer**: HPRT HT800 TSPL Label Printer (or compatible TSPL printer).
- **HandPOS Device**: Android 14 HandPOS device or mobile phone with WiFi.
- **Receipt Printer**: ESC/POS Thermal Receipt Printer.

## Quick Start
1. Run `JewelPOS_Setup.exe` on Windows.
2. Note the HTTP Server IP shown at the top of the screen (e.g. `192.168.1.25`).
3. Install `JewelPOS.apk` on Android HandPOS.
4. Open Settings in Android app, enter Desktop IP (`192.168.1.25`), and tap **Test Connection**.
5. Start registering items and printing receipts!
