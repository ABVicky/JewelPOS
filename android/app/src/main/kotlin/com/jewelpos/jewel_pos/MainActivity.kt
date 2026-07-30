package com.jewelpos.jewel_pos

import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
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
            when (call.method) {
                "printText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val bytes = call.argument<ByteArray>("bytes")
                    try {
                        if (bytes != null) {
                            sendDirectPosPrinterIntents(text, bytes)
                        }
                        printReceiptViaSystemManager(text)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "printBytes" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val customIp = call.argument<String>("ip")
                    val customPort = call.argument<Int>("port")
                    val mode = call.argument<String>("mode") ?: "auto"

                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Print bytes cannot be null", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        val success = printToInternalPrinter(bytes, customIp, customPort, mode)
                        runOnUiThread {
                            result.success(success)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sendDirectPosPrinterIntents(text: String, bytes: ByteArray) {
        val actions = arrayOf(
            "com.pos.printer.PRINT",
            "net.pos.printer.PRINT",
            "com.pos.print",
            "android.intent.action.POS_PRINT",
            "com.gprinter.postest"
        )
        for (act in actions) {
            try {
                val intent = Intent(act)
                intent.putExtra("text", text)
                intent.putExtra("bytes", bytes)
                intent.putExtra("content", text)
                sendBroadcast(intent)
            } catch (_: Exception) {}
        }
    }

    private fun printReceiptViaSystemManager(receiptText: String) {
        val printManager = getSystemService(Context.PRINT_SERVICE) as PrintManager
        val jobName = "JewelPOS_Receipt_${System.currentTimeMillis()}"

        printManager.print(jobName, object : PrintDocumentAdapter() {
            private var pdfDocument: PdfDocument? = null

            override fun onLayout(
                oldAttributes: PrintAttributes?,
                newAttributes: PrintAttributes,
                cancellationSignal: CancellationSignal?,
                callback: LayoutResultCallback,
                extras: Bundle?
            ) {
                pdfDocument = PdfDocument()
                val pageInfo = PdfDocument.PageInfo.Builder(200, 600, 1).create()
                val page = pdfDocument!!.startPage(pageInfo)

                val canvas: Canvas = page.canvas
                val paint = Paint()
                paint.color = Color.BLACK
                paint.textSize = 10f

                var y = 20f
                val lines = receiptText.split("\n")
                for (line in lines) {
                    canvas.drawText(line, 10f, y, paint)
                    y += 14f
                }

                pdfDocument!!.finishPage(page)

                if (cancellationSignal?.isCanceled == true) {
                    callback.onLayoutCancelled()
                    return
                }

                val info = PrintDocumentInfo.Builder("receipt.pdf")
                    .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                    .setPageCount(1)
                    .build()
                callback.onLayoutFinished(info, true)
            }

            override fun onWrite(
                pages: Array<out PageRange>?,
                destination: ParcelFileDescriptor,
                cancellationSignal: CancellationSignal?,
                callback: WriteResultCallback
            ) {
                try {
                    pdfDocument?.writeTo(FileOutputStream(destination.fileDescriptor))
                    callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                } catch (e: Exception) {
                    callback.onWriteFailed(e.message)
                } finally {
                    pdfDocument?.close()
                    pdfDocument = null
                }
            }
        }, null)
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
