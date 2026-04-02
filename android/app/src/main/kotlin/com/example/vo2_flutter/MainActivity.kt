package com.example.vo2_flutter

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var bluetoothSocket: BluetoothSocket? = null
    private var readerThread: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler(::onMethodCall)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestBluetoothPermissions(result)
            "isBluetoothEnabled" -> result.success(bluetoothAdapter()?.isEnabled == true)
            "getBondedDevices" -> getBondedDevices(result)
            "connect" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrBlank()) {
                    result.error("invalid_argument", "Bluetooth address is required.", null)
                    return
                }
                connect(address, result)
            }
            "disconnect" -> {
                disconnectInternal()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        val missingPermissions = missingRuntimePermissions()
        if (missingPermissions.isEmpty()) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.error("permission_busy", "A permission request is already in progress.", null)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            missingPermissions.toTypedArray(),
            REQUEST_PERMISSIONS_CODE,
        )
    }

    private fun getBondedDevices(result: MethodChannel.Result) {
        if (!ensureBluetoothAccess(result)) {
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("bluetooth_unavailable", "Bluetooth is not available on this device.", null)
            return
        }

        if (!adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth is turned off.", null)
            return
        }

        val devices = adapter.bondedDevices
            .orEmpty()
            .sortedBy { it.name ?: it.address }
            .map {
                mapOf(
                    "name" to (it.name ?: "Unknown device"),
                    "address" to it.address,
                )
            }
        result.success(devices)
    }

    private fun connect(address: String, result: MethodChannel.Result) {
        if (!ensureBluetoothAccess(result)) {
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("bluetooth_unavailable", "Bluetooth is not available on this device.", null)
            return
        }

        if (!adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth is turned off.", null)
            return
        }

        val device = try {
            adapter.getRemoteDevice(address)
        } catch (_: IllegalArgumentException) {
            null
        }

        if (device == null) {
            result.error("device_not_found", "Bluetooth device $address could not be resolved.", null)
            return
        }

        ioExecutor.execute {
            try {
                disconnectInternal()
                emitStatus("connecting", "Connecting to ${device.name ?: device.address}...")
                adapter.cancelDiscovery()

                val socket = connectWithFallbacks(device)
                bluetoothSocket = socket
                emitStatus("connected", "Connected to ${device.name ?: device.address}.")
                startReader(socket)
                mainHandler.post { result.success(true) }
            } catch (exception: Exception) {
                disconnectInternal()
                emitError("connect_error", exception.message ?: "Bluetooth connection failed.")
                mainHandler.post {
                    result.error(
                        "connect_error",
                        exception.message ?: "Bluetooth connection failed.",
                        null,
                    )
                }
            }
        }
    }

    private fun startReader(socket: BluetoothSocket) {
        readerThread = Thread {
            val lineBuffer = StringBuilder()

            try {
                val inputStream = socket.inputStream
                val buffer = ByteArray(1024)

                while (!Thread.currentThread().isInterrupted) {
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead <= 0) {
                        break
                    }

                    lineBuffer.append(String(buffer, 0, bytesRead, Charsets.UTF_8))
                    emitCompleteLines(lineBuffer)
                }
            } catch (exception: IOException) {
                emitError(
                    "stream_error",
                    exception.message ?: "Bluetooth stream closed unexpectedly.",
                )
            } finally {
                if (bluetoothSocket == socket) {
                    disconnectInternal()
                }
            }
        }.apply { start() }
    }

    private fun emitCompleteLines(lineBuffer: StringBuilder) {
        var delimiterIndex = findNextLineDelimiter(lineBuffer)
        while (delimiterIndex >= 0) {
            val line = lineBuffer.substring(0, delimiterIndex).trim()
            var deleteUntil = delimiterIndex + 1
            while (deleteUntil < lineBuffer.length &&
                (lineBuffer[deleteUntil] == '\n' || lineBuffer[deleteUntil] == '\r')
            ) {
                deleteUntil += 1
            }
            lineBuffer.delete(0, deleteUntil)
            if (line.isNotEmpty()) {
                emitEvent(
                    mapOf(
                        "type" to "data",
                        "line" to line,
                    ),
                )
            }
            delimiterIndex = findNextLineDelimiter(lineBuffer)
        }
    }

    private fun findNextLineDelimiter(lineBuffer: StringBuilder): Int {
        for (index in 0 until lineBuffer.length) {
            val char = lineBuffer[index]
            if (char == '\n' || char == '\r') {
                return index
            }
        }
        return -1
    }

    private fun connectWithFallbacks(device: BluetoothDevice): BluetoothSocket {
        val attempts = listOf<Pair<String, () -> BluetoothSocket>>(
            "rfcomm_channel_1" to { createChannelOneSocket(device) },
            "rfcomm_spp_secure" to { device.createRfcommSocketToServiceRecord(SPP_UUID) },
            "rfcomm_spp_insecure" to { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) },
        )

        var lastError: Exception? = null
        for ((label, createSocket) in attempts) {
            val socket = try {
                createSocket()
            } catch (exception: Exception) {
                lastError = exception
                continue
            }

            try {
                emitStatus("connecting", "Trying $label ...")
                socket.connect()
                return socket
            } catch (exception: Exception) {
                lastError = exception
                try {
                    socket.close()
                } catch (_: IOException) {
                }
            }
        }

        throw IOException(lastError?.message ?: "Bluetooth connection failed for every socket strategy.")
    }

    private fun createChannelOneSocket(device: BluetoothDevice): BluetoothSocket {
        val method = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
        return method.invoke(device, RFCOMM_CHANNEL) as BluetoothSocket
    }

    private fun disconnectInternal() {
        readerThread?.interrupt()
        readerThread = null

        try {
            bluetoothSocket?.close()
        } catch (_: IOException) {
        }

        bluetoothSocket = null
        emitStatus("disconnected", "Bluetooth disconnected.")
    }

    private fun ensureBluetoothAccess(result: MethodChannel.Result): Boolean {
        val missingPermissions = missingRuntimePermissions()
        if (missingPermissions.isNotEmpty()) {
            result.error(
                "permission_denied",
                "Bluetooth permission is required before accessing paired devices.",
                null,
            )
            return false
        }
        return true
    }

    private fun missingRuntimePermissions(): List<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return emptyList()
        }

        val requiredPermissions = listOf(Manifest.permission.BLUETOOTH_CONNECT)
        return requiredPermissions.filter {
            ActivityCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        val manager = getSystemService(BluetoothManager::class.java)
        return manager?.adapter ?: BluetoothAdapter.getDefaultAdapter()
    }

    private fun emitStatus(state: String, message: String) {
        emitEvent(
            mapOf(
                "type" to "status",
                "state" to state,
                "message" to message,
            ),
        )
    }

    private fun emitError(code: String, message: String) {
        emitEvent(
            mapOf(
                "type" to "error",
                "code" to code,
                "message" to message,
            ),
        )
    }

    private fun emitEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != REQUEST_PERMISSIONS_CODE) {
            return
        }

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { grantResult -> grantResult == PackageManager.PERMISSION_GRANTED }

        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    companion object {
        private const val METHOD_CHANNEL = "vo2_flutter/bluetooth_methods"
        private const val EVENT_CHANNEL = "vo2_flutter/bluetooth_stream"
        private const val REQUEST_PERMISSIONS_CODE = 4101
        private const val RFCOMM_CHANNEL = 1
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
