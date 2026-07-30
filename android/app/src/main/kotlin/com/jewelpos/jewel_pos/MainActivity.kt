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

                if (bytes == null) {
                    result.error("INVALID_ARGS", "Print bytes cannot be null", null)
                    return@setMethodCallHandler
                }

                // Run printer connection in background thread to avoid blocking main UI thread
                Thread {
                    val success = printToInternalPrinter(bytes, customIp, customPort)
                    runOnUiThread {
                        result.success(success)
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun printToInternalPrinter(bytes: ByteArray, customIp: String?, customPort: Int?): Boolean {
        // 1. Try Custom IP & Port if specified and non-loopback
        if (!customIp.isNullOrEmpty() && customPort != null && customIp != "127.0.0.1" && customIp != "localhost") {
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

        // 2. Try Internal Loopback TCP Ports used by Smart POS / Android thermal printers
        val targetHosts = arrayOf("127.0.0.1", "localhost", "0.0.0.0")
        val targetPorts = intArrayOf(9100, 9108, 8000, 8888, 9000, 6001, 7000, 5800, 3000, 9101, 9102, 20001, 10008)

        for (host in targetHosts) {
            for (port in targetPorts) {
                try {
                    val socket = Socket()
                    socket.connect(InetSocketAddress(host, port), 400)
                    val out = socket.getOutputStream()
                    out.write(bytes)
                    out.flush()
                    socket.close()
                    return true
                } catch (_: Exception) {}
            }
        }

        // 3. Try Internal Unix Serial Device Files for POS thermal printer hardware
        val serialPaths = arrayOf(
            "/dev/ttyS1", "/dev/ttyS0", "/dev/ttyMT0", "/dev/ttyMT1",
            "/dev/ttyS3", "/dev/userial0", "/dev/ttyUSB0"
        )

        for (path in serialPaths) {
            try {
                val file = File(path)
                if (file.exists() && file.canWrite()) {
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
