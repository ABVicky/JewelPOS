package com.jewelpos.jewel_pos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.Socket

class MainActivity : FlutterActivity() {
    private val CHANNEL = "jewel_pos/printer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "printBytes") {
                val bytes = call.argument<ByteArray>("bytes")
                val customIp = call.argument<String>("ip")
                val customPort = call.argument<Int>("port")
                val mode = call.argument<String>("mode") ?: "auto"

                if (bytes == null) {
                    result.error("INVALID_ARGS", "Print bytes cannot be null", null)
                    return@setMethodCallHandler
                }

                // Run printer connection in background thread to avoid blocking main UI thread
                Thread {
                    val success = printToInternalPrinter(bytes, customIp, customPort, mode)
                    runOnUiThread {
                        result.success(success)
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun printToInternalPrinter(bytes: ByteArray, customIp: String?, customPort: Int?, mode: String): Boolean {
        // 1. If explicit custom socket IP & Port provided (non-loopback or explicit port)
        if (!customIp.isNullOrEmpty() && customPort != null && customPort > 0 && customIp != "127.0.0.1" && customIp != "localhost") {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(customIp, customPort), 1500)
                val out = socket.getOutputStream()
                out.write(bytes)
                out.flush()
                socket.close()
                return true
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 2. Try Loopback TCP Sockets (127.0.0.1 / localhost)
        val targetHosts = arrayOf("127.0.0.1", "localhost", "0.0.0.0")
        val targetPorts = if (customPort != null && customPort > 0) {
            intArrayOf(customPort, 9100, 9108, 8000, 8888, 9000, 6001, 7000, 5800, 3000, 9101, 9102, 20001, 10008, 8080, 8081)
        } else {
            intArrayOf(9100, 9108, 8000, 8888, 9000, 6001, 7000, 5800, 3000, 9101, 9102, 20001, 10008, 8080, 8081)
        }

        for (host in targetHosts) {
            for (port in targetPorts) {
                try {
                    val socket = Socket()
                    socket.connect(InetSocketAddress(host, port), 250)
                    val out = socket.getOutputStream()
                    out.write(bytes)
                    out.flush()
                    socket.close()
                    return true
                } catch (_: Exception) {}
            }
        }

        // 3. Try High-Priority Verified Thermal Printer Serial Paths for SRK POS / POS Tektronics Model 1008
        val serialPaths = arrayOf(
            "/dev/ttyS1", "/dev/ttyMT1", "/dev/ttyS3", "/dev/userial0",
            "/dev/gprinter", "/dev/printer", "/dev/pos_printer", "/dev/ttyUSB0"
        )

        for (path in serialPaths) {
            try {
                val file = File(path)
                if (file.exists()) {
                    // Set baud rate 115200 raw mode via stty before writing
                    try {
                        Runtime.getRuntime().exec(arrayOf("sh", "-c", "stty -F $path 115200 raw 2>/dev/null || chmod 666 $path"))
                    } catch (_: Exception) {}

                    val fos = FileOutputStream(file)
                    fos.write(bytes)
                    fos.flush()
                    fos.close()
                    return true
                }
            } catch (_: Exception) {}
        }

        return false
    }
}
