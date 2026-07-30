package com.jewelpos.jewel_pos

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
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
                val text = call.argument<String>("text")

                if (bytes == null) {
                    result.error("INVALID_ARGS", "Print bytes cannot be null", null)
                    return@setMethodCallHandler
                }

                Thread {
                    val status = printToInternalPrinter(bytes, customIp, customPort, text)
                    runOnUiThread {
                        result.success(status)
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun printToInternalPrinter(bytes: ByteArray, customIp: String?, customPort: Int?, text: String?): String {
        // 1. Try Custom IP & Port if specified and non-loopback
        if (!customIp.isNullOrEmpty() && customPort != null && customIp != "127.0.0.1" && customIp != "localhost") {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(customIp, customPort), 1500)
                val out = socket.getOutputStream()
                out.write(bytes)
                out.flush()
                socket.close()
                return "SUCCESS_CUSTOM_SOCKET"
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 2. Try Internal Loopback TCP Ports used by Smart POS 1008 & Android thermal printers
        val targetHosts = arrayOf("127.0.0.1", "localhost", "0.0.0.0")
        val targetPorts = intArrayOf(9100, 9108, 8000, 8888, 9000, 6001, 7000, 5800, 3000, 9101, 9102, 20001, 10008, 8080, 8081)

        for (host in targetHosts) {
            for (port in targetPorts) {
                try {
                    val socket = Socket()
                    socket.connect(InetSocketAddress(host, port), 200)
                    val out = socket.getOutputStream()
                    out.write(bytes)
                    out.flush()
                    socket.close()
                    return "SUCCESS_SOCKET_$port"
                } catch (_: Exception) {}
            }
        }

        // 3. Try Internal Unix Serial Device Files for Smart POS 1008 thermal printer hardware
        val serialPaths = arrayOf(
            "/dev/ttyS1", "/dev/ttyS0", "/dev/ttyS2", "/dev/ttyS3", "/dev/ttyS4",
            "/dev/ttyMT0", "/dev/ttyMT1", "/dev/ttyMT2", "/dev/ttyUSB0", "/dev/ttyUSB1",
            "/dev/userial0", "/dev/gprinter", "/dev/printer", "/dev/pos_printer"
        )

        for (path in serialPaths) {
            try {
                val file = File(path)
                if (file.exists()) {
                    try {
                        Runtime.getRuntime().exec(arrayOf("chmod", "666", path)).waitFor()
                    } catch (_: Exception) {}

                    try {
                        val fos = FileOutputStream(file)
                        fos.write(bytes)
                        fos.flush()
                        fos.close()
                        return "SUCCESS_SERIAL_$path"
                    } catch (_: Exception) {
                        // Shell fallback to write bytes to serial device
                        try {
                            val tempFile = File.createTempFile("receipt", ".bin", cacheDir)
                            tempFile.writeBytes(bytes)
                            Runtime.getRuntime().exec(arrayOf("sh", "-c", "cat ${tempFile.absolutePath} > $path")).waitFor()
                            tempFile.delete()
                            return "SUCCESS_SHELL_SERIAL_$path"
                        } catch (_: Exception) {}
                    }
                }
            } catch (_: Exception) {}
        }

        // 4. Send Vendor POS Printer Broadcast Intents
        val vendorIntents = arrayOf(
            "com.pos.print",
            "com.gprinter.service",
            "woyou.aio.service.action.PRINT",
            "android.intent.action.PRINTER",
            "com.zcs.postest",
            "com.android.print"
        )

        for (intentAction in vendorIntents) {
            try {
                val intent = Intent(intentAction)
                intent.putExtra("bytes", bytes)
                intent.putExtra("data", bytes)
                if (!text.isNullOrEmpty()) {
                    intent.putExtra("text", text)
                    intent.putExtra("msg", text)
                }
                sendBroadcast(intent)
            } catch (_: Exception) {}
        }

        // 5. Try Android PrintManager System Service Fallback
        if (!text.isNullOrEmpty()) {
            try {
                val printManager = getSystemService(Context.PRINT_SERVICE) as? PrintManager
                if (printManager != null) {
                    runOnUiThread {
                        try {
                            val printAdapter = object : PrintDocumentAdapter() {
                                override fun onLayout(
                                    oldAttributes: PrintAttributes?,
                                    newAttributes: PrintAttributes?,
                                    cancellationSignal: CancellationSignal?,
                                    callback: LayoutResultCallback?,
                                    extras: Bundle?
                                ) {
                                    if (cancellationSignal?.isCanceled == true) {
                                        callback?.onLayoutCancelled()
                                        return
                                    }
                                    val builder = PrintDocumentInfo.Builder("JewelPOS_Receipt")
                                        .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                                        .setPageCount(1)
                                    callback?.onLayoutFinished(builder.build(), true)
                                }

                                override fun onWrite(
                                    pages: Array<out PageRange>?,
                                    destination: ParcelFileDescriptor?,
                                    cancellationSignal: CancellationSignal?,
                                    callback: WriteResultCallback?
                                ) {
                                    try {
                                        val out = FileOutputStream(destination?.fileDescriptor)
                                        out.write(text.toByteArray())
                                        out.flush()
                                        out.close()
                                        callback?.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                                    } catch (e: Exception) {
                                        callback?.onWriteFailed(e.message)
                                    }
                                }
                            }
                            printManager.print("JewelPOS_Receipt", printAdapter, PrintAttributes.Builder().build())
                        } catch (_: Exception) {}
                    }
                    return "SUCCESS_SYSTEM_PRINT"
                }
            } catch (_: Exception) {}
        }

        return "FAILED_PRINTER_UNREACHABLE"
    }
}
