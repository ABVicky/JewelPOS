# JEWEL POS V2 - User Manual

Written for Jewellery Shop Owners. Simple, clear, and easy to follow.

---

## 1. Registering New Jewellery Items (Windows)

1. Open **Jewel POS** on your Windows computer.
2. Under **Register Jewellery** (Left Panel):
   - **Item Name**: Enter description (e.g. `Gold Necklace`).
   - **Category**: Select category (`Ring`, `Chain`, `Necklace`, `Bangle`, etc.).
   - **Purity**: Select gold/silver purity (`24K`, `22K (916)`, `18K (750)`, etc.).
   - **Weight**: Enter weight in grams up to 3 decimal places (e.g. `12.350`).
3. Click **Save & Print**.
4. The barcode (e.g. `JMT000000001`) is generated automatically, saved into the database, and printed onto the HPRT HT800 label printer.

---

## 2. Searching & Editing Inventory (Windows)

- Use the **Search Box** on the Right Panel to search by Barcode, Item Name, or Category.
- Click **Edit** next to any item to update its Name, Category, Purity, or Weight. (Barcode cannot be changed).
- Click **Reprint** to print another barcode label for an existing item without generating a new barcode.

---

## 3. Database Backup & Restore (Windows)

- **Backup DB**: Click **Backup DB** in the top bar to create a timestamped copy of your inventory in the `Backups/` folder.
- **Restore DB**: Click **Restore DB** in the top bar, choose a backup file from the list, and confirm to restore your saved data.

---

## 4. Mobile Billing & Receipt Printing (Android HandPOS)

1. Open **Jewel POS** on your Android device.
2. Tap **Scan Item** (or use the built-in laser scanner / keyboard entry) to scan a barcode label.
3. The item details (Name, Weight, Barcode) will automatically appear in your temporary list and update the total items and weight.
4. Tap **Print Receipt** to print an ESC/POS thermal receipt.
5. After printing, confirm whether to clear the list for the next customer.
