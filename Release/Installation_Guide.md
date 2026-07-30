# JEWEL POS V2 - Installation Guide

Step-by-step setup guide for Windows Workstations and Android HandPOS devices.

---

## Part 1: Windows Workstation Setup

1. Double-click `JewelPOS_Setup.exe` to run the installer.
2. Follow the prompt to install the desktop application.
3. Connect your **HPRT HT800 TSPL Label Printer** to your local network or PC via Ethernet/IP (default port `9100`).
4. Launch **Jewel POS** from your desktop icon or Start Menu.
5. In **Settings**, enter your Label Printer IP address and click **Save**.

---

## Part 2: Android HandPOS Setup

1. Copy `JewelPOS.apk` to your Android HandPOS device.
2. Tap the APK file to install the application. (If prompted, allow installation from unknown sources).
3. Connect your Android device to the **same WiFi network** as your Windows computer.
4. Launch **Jewel POS** on your Android device.
5. Tap the **Settings** icon at the top right:
   - Enter your **Desktop IP** (displayed at the top of the Windows application, e.g. `192.168.1.25`).
   - Enter your **Receipt Printer IP** and Port.
   - Tap **Test Connection**. You should see **Connected**.
   - Tap **Save**.

---

## Part 3: Troubleshooting

- **Desktop Not Reachable**: Check that both Windows PC and Android device are connected to the same WiFi network.
- **Printer Error**: Ensure printers are powered on, loaded with labels/paper, and reachable on port 9100.
