import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'db.dart';

class TSPLPrinter {
  /// Build TSPL command string for HPRT HT800 label printer (38mm x 25mm)
  static String buildTSPLCommand(InventoryItem item) {
    final buffer = StringBuffer();
    buffer.writeln('SIZE 38 mm, 25 mm');
    buffer.writeln('GAP 2 mm, 0 mm');
    buffer.writeln('DIRECTION 1');
    buffer.writeln('CLS');
    buffer.writeln('TEXT 15,10,"2",0,1,1,"${item.itemName} (${item.category})"');
    buffer.writeln('TEXT 15,38,"2",0,1,1,"Pur: ${item.purity}  Wt: ${item.weight.toStringAsFixed(4)} g"');
    buffer.writeln('BARCODE 15,68,"128",55,1,0,2,2,"${item.barcode}"');
    buffer.writeln('PRINT 1,1');
    return buffer.toString();
  }

  /// Automatically fetch list of all installed Windows USB printers
  static Future<List<String>> getInstalledWindowsPrinters() async {
    if (kIsWeb || !Platform.isWindows) return [];
    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-Printer | Select-Object -ExpandProperty Name'
      ]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        return lines;
      }
    } catch (_) {}
    return [];
  }

  /// Sends raw TSPL commands to Windows Installed Printer Driver via Win32 RAW Spooler, USB COM Port, or TCP Socket
  static Future<bool> sendTSPLToPrinter(
    InventoryItem item, {
    required String host,
    required int port,
    String? usbPortName,
  }) async {
    if (kIsWeb) {
      debugPrint('TSPL Label generated (Web Simulation):\n${buildTSPLCommand(item)}');
      return true;
    }

    final tsplStr = buildTSPLCommand(item);
    final bytes = utf8.encode(tsplStr);

    if (Platform.isWindows) {
      final List<String> targetNames = [];
      if (usbPortName != null && usbPortName.trim().isNotEmpty) {
        targetNames.add(usbPortName.trim());
      }

      // Auto-detect installed Windows printers if target is generic
      try {
        final installedPrinters = await getInstalledWindowsPrinters();
        for (var p in installedPrinters) {
          if (!targetNames.contains(p)) {
            if (p.toLowerCase().contains('hprt') ||
                p.toLowerCase().contains('label') ||
                p.toLowerCase().contains('pos') ||
                p.toLowerCase().contains('tsc') ||
                p.toLowerCase().contains('barcode')) {
              targetNames.insert(0, p);
            } else {
              targetNames.add(p);
            }
          }
        }
      } catch (_) {}

      // Add standard USB / COM serial targets
      targetNames.addAll([
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8',
        '\\\\.\\COM1', '\\\\.\\COM2', '\\\\.\\COM3', '\\\\.\\COM4', '\\\\.\\COM5',
        'LPT1', 'PRN'
      ]);

      for (var target in targetNames) {
        // 1. Attempt Win32 RAW Spooler API via PowerShell Script for Installed Windows Drivers
        if (!target.startsWith('COM') && !target.startsWith('LPT') && !target.startsWith('\\\\')) {
          try {
            final tempFile = File('${Directory.systemTemp.path}\\tspl_${DateTime.now().millisecondsSinceEpoch}.tspl');
            await tempFile.writeAsBytes(bytes);

            final psScript = '''
\$code = @"
using System;
using System.IO;
using System.Runtime.InteropServices;
public class Win32RawPrinter {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public class DOCINFOA {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }
    [DllImport("winspool.drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool OpenPrinter([MarshalAs(UnmanagedType.LPStr)] string szPrinter, out IntPtr hPrinter, IntPtr pd);
    [DllImport("winspool.drv", EntryPoint = "ClosePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool ClosePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, Int32 level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);
    [DllImport("winspool.drv", EntryPoint = "EndDocPrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", EntryPoint = "StartPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", EntryPoint = "EndPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", EntryPoint = "WritePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, Int32 dwCount, out Int32 dwWritten);

    public static bool PrintRaw(string printerName, string filePath) {
        byte[] pBytes = File.ReadAllBytes(filePath);
        IntPtr hPrinter = IntPtr.Zero;
        DOCINFOA di = new DOCINFOA();
        di.pDocName = "JewelPOS_TSPL_Label";
        di.pDataType = "RAW";
        if (OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) {
            if (StartDocPrinter(hPrinter, 1, di)) {
                if (StartPagePrinter(hPrinter)) {
                    IntPtr pUnmanagedBytes = Marshal.AllocCoTaskMem(pBytes.Length);
                    Marshal.Copy(pBytes, 0, pUnmanagedBytes, pBytes.Length);
                    Int32 dwWritten = 0;
                    bool bSuccess = WritePrinter(hPrinter, pUnmanagedBytes, pBytes.Length, out dwWritten);
                    Marshal.FreeCoTaskMem(pUnmanagedBytes);
                    EndPagePrinter(hPrinter);
                    EndDocPrinter(hPrinter);
                    ClosePrinter(hPrinter);
                    return bSuccess && dwWritten == pBytes.Length;
                }
                EndDocPrinter(hPrinter);
            }
            ClosePrinter(hPrinter);
        }
        return false;
    }
}
"@
if (-not ([System.Management.Automation.PSTypeName]'Win32RawPrinter').Type) {
    Add-Type -TypeDefinition \$code
}
\$res = [Win32RawPrinter]::PrintRaw('$target', '${tempFile.path.replaceAll('\\', '\\\\')}')
if (\$res) { Write-Host "SUCCESS_RAW" } else { Write-Host "FAILED_RAW" }
''';

            final scriptFile = File('${Directory.systemTemp.path}\\raw_spool_${DateTime.now().millisecondsSinceEpoch}.ps1');
            await scriptFile.writeAsString(psScript);

            final psResult = await Process.run('powershell', [
              '-ExecutionPolicy', 'Bypass',
              '-File', scriptFile.path
            ]);

            try { await tempFile.delete(); } catch (_) {}
            try { await scriptFile.delete(); } catch (_) {}

            if ((psResult.stdout as String).contains('SUCCESS_RAW')) {
              return true;
            }
          } catch (_) {}
        }

        // 2. Attempt Direct Binary Copy to COM / LPT port or Local Spool Share
        try {
          final tempFile = File('${Directory.systemTemp.path}\\raw_copy.tspl');
          await tempFile.writeAsBytes(bytes);

          final rawResult = await Process.run('cmd.exe', [
            '/c',
            'copy',
            '/b',
            tempFile.path,
            target.startsWith('COM') || target.startsWith('LPT') ? target : "\\\\localhost\\$target"
          ]);

          try { await tempFile.delete(); } catch (_) {}

          if (rawResult.exitCode == 0) {
            return true;
          }
        } catch (_) {}
      }
    }

    // 3. Try Network TCP Socket Connection (Ethernet / WiFi / USB Virtual IP)
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {}

    return false;
  }
}
