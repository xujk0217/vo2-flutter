package com.example.vo2_flutter

import android.annotation.SuppressLint
import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
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

    private var bleEventSink: EventChannel.EventSink? = null
    private var pendingBlePermissionResult: MethodChannel.Result? = null
    private var pendingBleScanResult: MethodChannel.Result? = null
    private var pendingBleConnectResult: MethodChannel.Result? = null
    private var pendingBleWriteResult: MethodChannel.Result? = null
    private var bleScanCallback: ScanCallback? = null
    private val bleScanDevices = linkedMapOf<String, Map<String, String>>()
    private var bleGatt: BluetoothGatt? = null
    private var bleWriteCharacteristic: BluetoothGattCharacteristic? = null
    private var bleNotifyCharacteristic: BluetoothGattCharacteristic? = null
    private var expectedBleServiceUuid: UUID = BLE_SERVICE_UUID
    private var expectedBleWriteUuid: UUID = BLE_WRITE_CHARACTERISTIC_UUID
    private var expectedBleNotifyUuid: UUID = BLE_NOTIFY_CHARACTERISTIC_UUID

    private val bleGattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failPendingBleConnect("gatt_error", "BLE GATT connection failed with status $status.")
                cleanupBleGatt(gatt)
                return
            }

            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    emitBleStatus("discovering_services", "BLE connected. Discovering services...")
                    if (!gatt.discoverServices()) {
                        failPendingBleConnect("service_discovery_error", "BLE service discovery could not start.")
                        cleanupBleGatt(gatt)
                    }
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    failPendingBleConnect("disconnected", "BLE disconnected before setup completed.")
                    failPendingBleWrite("disconnected", "BLE disconnected before write completed.")
                    cleanupBleGatt(gatt)
                    emitBleStatus("disconnected", "BLE disconnected.")
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failPendingBleConnect("service_discovery_error", "BLE service discovery failed with status $status.")
                cleanupBleGatt(gatt)
                return
            }

            val service = gatt.getService(expectedBleServiceUuid)
            if (service == null) {
                failPendingBleConnect("service_not_found", "BLE device service $expectedBleServiceUuid was not found.")
                cleanupBleGatt(gatt)
                return
            }

            val writeCharacteristic = service.getCharacteristic(expectedBleWriteUuid)
            val notifyCharacteristic = service.getCharacteristic(expectedBleNotifyUuid)
            if (writeCharacteristic == null || notifyCharacteristic == null) {
                failPendingBleConnect(
                    "characteristic_not_found",
                    "BLE write or notify characteristic was not found.",
                )
                cleanupBleGatt(gatt)
                return
            }

            bleWriteCharacteristic = writeCharacteristic
            bleNotifyCharacteristic = notifyCharacteristic
            enableBleNotifications(gatt, notifyCharacteristic)
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (descriptor.uuid != CLIENT_CHARACTERISTIC_CONFIG_UUID) {
                return
            }

            if (status == BluetoothGatt.GATT_SUCCESS) {
                emitBleStatus("connected", "BLE connected and notifications enabled.")
                pendingBleConnectResult?.success(true)
                pendingBleConnectResult = null
            } else {
                failPendingBleConnect("notify_setup_error", "BLE notify descriptor write failed with status $status.")
                cleanupBleGatt(gatt)
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                emitBleStatus("write_complete", "BLE write complete.")
                pendingBleWriteResult?.success(true)
            } else {
                pendingBleWriteResult?.error(
                    "write_error",
                    "BLE write failed with status $status.",
                    null,
                )
                emitBleError("write_error", "BLE write failed with status $status.")
            }
            pendingBleWriteResult = null
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (characteristic.uuid == expectedBleNotifyUuid) {
                emitBleData(characteristic.value ?: ByteArray(0))
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            if (characteristic.uuid == expectedBleNotifyUuid) {
                emitBleData(value)
            }
        }
    }

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLE_METHOD_CHANNEL,
        ).setMethodCallHandler(::onBleMethodCall)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLE_EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                bleEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                bleEventSink = null
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

    private fun onBleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestBlePermissions(result)
            "isBluetoothEnabled" -> result.success(bluetoothAdapter()?.isEnabled == true)
            "scanDevices" -> scanBleDevices(call, result)
            "connect" -> connectBle(call, result)
            "disconnect" -> {
                disconnectBleInternal()
                result.success(true)
            }
            "write" -> writeBle(call, result)
            else -> result.notImplemented()
        }
    }

    private fun requestBlePermissions(result: MethodChannel.Result) {
        val missingPermissions = missingBleRuntimePermissions()
        if (missingPermissions.isEmpty()) {
            result.success(true)
            return
        }

        if (pendingBlePermissionResult != null) {
            result.error("permission_busy", "A BLE permission request is already in progress.", null)
            return
        }

        pendingBlePermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            missingPermissions.toTypedArray(),
            REQUEST_BLE_PERMISSIONS_CODE,
        )
    }

    @SuppressLint("MissingPermission")
    private fun scanBleDevices(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureBleAccess(result)) {
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
        if (pendingBleScanResult != null) {
            result.error("scan_busy", "A BLE scan is already in progress.", null)
            return
        }

        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            result.error("scan_unavailable", "BLE scanner is not available.", null)
            return
        }

        val serviceUuid = parseUuidArgument(call, "serviceUuid", BLE_SERVICE_UUID)
        val advertisedNames = parseAdvertisedNamesArgument(call)
        val includeUnmatched = call.argument<Boolean>("includeUnmatched") == true
        pendingBleScanResult = result
        bleScanDevices.clear()
        emitBleStatus("scanning", "Scanning for BLE receiver...")

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                recordBleScanResult(scanResult, serviceUuid, advertisedNames, includeUnmatched)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach { scanResult ->
                    recordBleScanResult(scanResult, serviceUuid, advertisedNames, includeUnmatched)
                }
            }

            override fun onScanFailed(errorCode: Int) {
                finishBleScanWithError("scan_error", "BLE scan failed with code $errorCode.")
            }
        }

        bleScanCallback = callback
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            scanner.startScan(null, settings, callback)
            mainHandler.postDelayed({ finishBleScanSuccessfully() }, BLE_SCAN_WINDOW_MS)
        } catch (exception: Exception) {
            bleScanCallback = null
            pendingBleScanResult = null
            result.error("scan_error", exception.message ?: "BLE scan failed.", null)
            emitBleError("scan_error", exception.message ?: "BLE scan failed.")
        }
    }

    @SuppressLint("MissingPermission")
    private fun connectBle(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureBleAccess(result)) {
            return
        }

        val deviceId = call.argument<String>("deviceId")
        if (deviceId.isNullOrBlank()) {
            result.error("invalid_argument", "BLE deviceId is required.", null)
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
        if (pendingBleConnectResult != null) {
            result.error("connect_busy", "A BLE connection is already in progress.", null)
            return
        }

        val device = try {
            adapter.getRemoteDevice(deviceId)
        } catch (_: IllegalArgumentException) {
            null
        }
        if (device == null) {
            result.error("device_not_found", "BLE device $deviceId could not be resolved.", null)
            return
        }

        expectedBleServiceUuid = parseUuidArgument(call, "serviceUuid", BLE_SERVICE_UUID)
        expectedBleWriteUuid = parseUuidArgument(call, "writeCharacteristicUuid", BLE_WRITE_CHARACTERISTIC_UUID)
        expectedBleNotifyUuid = parseUuidArgument(call, "notifyCharacteristicUuid", BLE_NOTIFY_CHARACTERISTIC_UUID)
        disconnectBleInternal(emitDisconnected = false)
        pendingBleConnectResult = result
        emitBleStatus("connecting", "Connecting to ${device.name ?: device.address}...")
        bleGatt = device.connectGatt(this, false, bleGattCallback)
    }

    @SuppressLint("MissingPermission")
    private fun writeBle(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureBleAccess(result)) {
            return
        }
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null) {
            result.error("invalid_argument", "BLE write bytes are required.", null)
            return
        }
        val gatt = bleGatt
        val characteristic = bleWriteCharacteristic
        if (gatt == null || characteristic == null) {
            result.error("not_connected", "BLE write characteristic is not ready.", null)
            return
        }
        if (pendingBleWriteResult != null) {
            result.error("write_busy", "A BLE write is already in progress.", null)
            return
        }

        pendingBleWriteResult = result
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(
                characteristic,
                bytes,
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
            ) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                characteristic.value = bytes
                gatt.writeCharacteristic(characteristic)
            }
        }
        if (!started) {
            pendingBleWriteResult = null
            result.error("write_error", "BLE write could not start.", null)
            emitBleError("write_error", "BLE write could not start.")
        } else {
            emitBleStatus("write_started", "BLE write started.")
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

    @SuppressLint("MissingPermission")
    private fun finishBleScanSuccessfully() {
        val result = pendingBleScanResult ?: return
        val callback = bleScanCallback
        val scanner = bluetoothAdapter()?.bluetoothLeScanner
        if (callback != null && scanner != null && missingBleRuntimePermissions().isEmpty()) {
            try {
                scanner.stopScan(callback)
            } catch (_: Exception) {
            }
        }
        bleScanCallback = null
        pendingBleScanResult = null
        emitBleStatus("scan_complete", "BLE scan complete.")
        result.success(bleScanDevices.values.toList())
    }

    @SuppressLint("MissingPermission")
    private fun finishBleScanWithError(code: String, message: String) {
        val result = pendingBleScanResult
        val callback = bleScanCallback
        val scanner = bluetoothAdapter()?.bluetoothLeScanner
        if (callback != null && scanner != null && missingBleRuntimePermissions().isEmpty()) {
            try {
                scanner.stopScan(callback)
            } catch (_: Exception) {
            }
        }
        bleScanCallback = null
        pendingBleScanResult = null
        emitBleError(code, message)
        result?.error(code, message, null)
    }

    @SuppressLint("MissingPermission")
    private fun disconnectBleInternal(emitDisconnected: Boolean = true) {
        val callback = bleScanCallback
        val scanner = bluetoothAdapter()?.bluetoothLeScanner
        if (callback != null && scanner != null && missingBleRuntimePermissions().isEmpty()) {
            try {
                scanner.stopScan(callback)
            } catch (_: Exception) {
            }
        }
        bleScanCallback = null
        pendingBleScanResult?.error("disconnected", "BLE disconnected.", null)
        pendingBleScanResult = null
        failPendingBleConnect("disconnected", "BLE disconnected.")
        failPendingBleWrite("disconnected", "BLE disconnected.")

        try {
            bleGatt?.disconnect()
        } catch (_: Exception) {
        }
        cleanupBleGatt(bleGatt)
        if (emitDisconnected) {
            emitBleStatus("disconnected", "BLE disconnected.")
        }
    }

    private fun cleanupBleGatt(gatt: BluetoothGatt?) {
        try {
            gatt?.close()
        } catch (_: Exception) {
        }
        if (bleGatt == gatt) {
            bleGatt = null
        }
        bleWriteCharacteristic = null
        bleNotifyCharacteristic = null
    }

    @SuppressLint("MissingPermission")
    private fun recordBleScanResult(
        result: ScanResult,
        serviceUuid: UUID,
        advertisedNames: List<String>,
        includeUnmatched: Boolean,
    ) {
        val device = result.device ?: return
        val scanRecord = result.scanRecord
        val scanRecordName = scanRecord?.deviceName
        val deviceName = device.name
        val displayName = scanRecordName?.takeIf { it.isNotBlank() }
            ?: deviceName?.takeIf { it.isNotBlank() }
            ?: device.address
        val serviceMatches = scanRecord?.serviceUuids?.any { parcelUuid ->
            parcelUuid.uuid == serviceUuid
        } == true
        val nameMatches = advertisedNames.any { advertisedName ->
            scanRecordName == advertisedName || deviceName == advertisedName
        }
        if (!includeUnmatched && !serviceMatches && !nameMatches) {
            return
        }

        bleScanDevices[device.address] = mapOf(
            "name" to displayName,
            "id" to device.address,
        )
    }

    @SuppressLint("MissingPermission")
    private fun enableBleNotifications(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        if (!gatt.setCharacteristicNotification(characteristic, true)) {
            failPendingBleConnect("notify_setup_error", "BLE notifications could not be enabled.")
            cleanupBleGatt(gatt)
            return
        }

        val descriptor = characteristic.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG_UUID)
        if (descriptor == null) {
            failPendingBleConnect("notify_setup_error", "BLE notify CCCD descriptor was not found.")
            cleanupBleGatt(gatt)
            return
        }

        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(
                descriptor,
                BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
            ) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                gatt.writeDescriptor(descriptor)
            }
        }

        if (!started) {
            failPendingBleConnect("notify_setup_error", "BLE notify descriptor write could not start.")
            cleanupBleGatt(gatt)
        }
    }

    private fun parseUuidArgument(
        call: MethodCall,
        argumentName: String,
        fallback: UUID,
    ): UUID {
        val value = call.argument<String>(argumentName)
        if (value.isNullOrBlank()) {
            return fallback
        }
        return try {
            UUID.fromString(value)
        } catch (_: IllegalArgumentException) {
            fallback
        }
    }

    private fun parseAdvertisedNamesArgument(call: MethodCall): List<String> {
        val advertisedNames = call.argument<List<String>>("advertisedNames")
            ?.filter { advertisedName -> advertisedName.isNotBlank() }
        if (!advertisedNames.isNullOrEmpty()) {
            return advertisedNames
        }

        val advertisedName = call.argument<String>("advertisedName")
        if (!advertisedName.isNullOrBlank()) {
            return listOf(advertisedName)
        }

        return listOf(BLE_ADVERTISED_NAME)
    }

    private fun ensureBleAccess(result: MethodChannel.Result): Boolean {
        val missingPermissions = missingBleRuntimePermissions()
        if (missingPermissions.isNotEmpty()) {
            result.error(
                "permission_denied",
                "BLE permission is required before accessing BLE devices.",
                null,
            )
            return false
        }
        return true
    }

    private fun missingBleRuntimePermissions(): List<String> {
        val requiredPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return requiredPermissions.filter { permission ->
            ActivityCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
        }
    }

    private fun failPendingBleConnect(code: String, message: String) {
        pendingBleConnectResult?.error(code, message, null)
        pendingBleConnectResult = null
        if (code != "disconnected") {
            emitBleError(code, message)
        }
    }

    private fun failPendingBleWrite(code: String, message: String) {
        pendingBleWriteResult?.error(code, message, null)
        pendingBleWriteResult = null
        if (code != "disconnected") {
            emitBleError(code, message)
        }
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

    private fun emitBleStatus(state: String, message: String) {
        emitBleEvent(
            mapOf(
                "type" to "status",
                "state" to state,
                "message" to message,
            ),
        )
    }

    private fun emitBleError(code: String, message: String) {
        emitBleEvent(
            mapOf(
                "type" to "error",
                "code" to code,
                "message" to message,
            ),
        )
    }

    private fun emitBleData(bytes: ByteArray) {
        emitBleEvent(
            mapOf(
                "type" to "data",
                "chunk" to bytes,
            ),
        )
    }

    private fun emitBleEvent(event: Map<String, Any?>) {
        mainHandler.post {
            bleEventSink?.success(event)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { grantResult -> grantResult == PackageManager.PERMISSION_GRANTED }

        when (requestCode) {
            REQUEST_PERMISSIONS_CODE -> {
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
            }
            REQUEST_BLE_PERMISSIONS_CODE -> {
                pendingBlePermissionResult?.success(granted)
                pendingBlePermissionResult = null
            }
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "vo2_flutter/bluetooth_methods"
        private const val EVENT_CHANNEL = "vo2_flutter/bluetooth_stream"
        private const val BLE_METHOD_CHANNEL = "vo2_flutter/ble_methods"
        private const val BLE_EVENT_CHANNEL = "vo2_flutter/ble_stream"
        private const val REQUEST_PERMISSIONS_CODE = 4101
        private const val REQUEST_BLE_PERMISSIONS_CODE = 4102
        private const val BLE_SCAN_WINDOW_MS = 2000L
        private const val RFCOMM_CHANNEL = 1
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private val BLE_SERVICE_UUID: UUID = UUID.fromString("0000ffee-0000-1000-8000-00805f9b34fb")
        private val BLE_WRITE_CHARACTERISTIC_UUID: UUID = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb")
        private val BLE_NOTIFY_CHARACTERISTIC_UUID: UUID = UUID.fromString("0000ffe2-0000-1000-8000-00805f9b34fb")
        private val CLIENT_CHARACTERISTIC_CONFIG_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val BLE_ADVERTISED_NAME = "bt_fucktrae_young"
    }
}
