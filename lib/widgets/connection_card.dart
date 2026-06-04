import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vo2_flutter/receiver/receiver_transport.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.devices,
    required this.selectedDeviceId,
    required this.permissionsGranted,
    required this.bluetoothEnabled,
    required this.statusMessage,
    required this.isLoadingDevices,
    required this.isConnecting,
    required this.isConnected,
    required this.onRequestPermissions,
    required this.onRefreshDevices,
    required this.onConnectPressed,
    required this.onDeviceChanged,
    this.showBleDiagnostics = false,
    this.lastTransportState,
    this.lastErrorCode,
    this.lastProtocolMessageType,
    this.lastUnsupportedMessageType,
    this.healthStatusLabel,
    this.appStatusLabel,
  });

  final List<ReceiverDeviceInfo> devices;
  final String? selectedDeviceId;
  final bool permissionsGranted;
  final bool bluetoothEnabled;
  final String statusMessage;
  final bool isLoadingDevices;
  final bool isConnecting;
  final bool isConnected;
  final Future<void> Function() onRequestPermissions;
  final Future<void> Function() onRefreshDevices;
  final Future<void> Function() onConnectPressed;
  final ValueChanged<String?> onDeviceChanged;
  final bool showBleDiagnostics;
  final String? lastTransportState;
  final String? lastErrorCode;
  final int? lastProtocolMessageType;
  final int? lastUnsupportedMessageType;
  final String? healthStatusLabel;
  final String? appStatusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '藍牙連線',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: isLoadingDevices
                    ? null
                    : () {
                        unawaited(onRefreshDevices());
                      },
                icon: isLoadingDevices
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('重新整理'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Icon(
                    isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_searching,
                    color: isConnected
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF0284C7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusMessage,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showBleDiagnostics) ...<Widget>[
            const SizedBox(height: 12),
            _BleDiagnosticsPanel(
              permissionsGranted: permissionsGranted,
              bluetoothEnabled: bluetoothEnabled,
              deviceCount: devices.length,
              selectedDeviceId: selectedDeviceId,
              lastTransportState: lastTransportState,
              lastErrorCode: lastErrorCode,
              lastProtocolMessageType: lastProtocolMessageType,
              lastUnsupportedMessageType: lastUnsupportedMessageType,
              healthStatusLabel: healthStatusLabel,
              appStatusLabel: appStatusLabel,
            ),
          ],
          const SizedBox(height: 14),
          if (!permissionsGranted || !bluetoothEnabled)
            FilledButton.icon(
              onPressed: () {
                unawaited(onRequestPermissions());
              },
              icon: const Icon(Icons.settings_bluetooth_rounded),
              label: Text(!permissionsGranted ? '允許藍牙權限' : '重新檢查藍牙狀態'),
            )
          else if (devices.isEmpty)
            Text(
              '沒有已配對裝置，請先在 Android 系統藍牙頁面完成配對。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue:
                      devices.any(
                        (ReceiverDeviceInfo d) => d.id == selectedDeviceId,
                      )
                      ? selectedDeviceId
                      : null,
                  decoration: const InputDecoration(
                    labelText: '已配對裝置',
                    border: OutlineInputBorder(),
                  ),
                  items: devices
                      .map(
                        (ReceiverDeviceInfo device) =>
                            DropdownMenuItem<String>(
                              value: device.id,
                              child: Text('${device.name} (${device.id})'),
                            ),
                      )
                      .toList(),
                  onChanged: onDeviceChanged,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: isConnecting
                      ? null
                      : () {
                          unawaited(onConnectPressed());
                        },
                  icon: Icon(
                    isConnected
                        ? Icons.link_off_rounded
                        : Icons.bluetooth_connected_rounded,
                  ),
                  label: Text(
                    isConnected
                        ? '中斷連線'
                        : isConnecting
                        ? '連線中...'
                        : '開始接收資料',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BleDiagnosticsPanel extends StatelessWidget {
  const _BleDiagnosticsPanel({
    required this.permissionsGranted,
    required this.bluetoothEnabled,
    required this.deviceCount,
    required this.selectedDeviceId,
    required this.lastTransportState,
    required this.lastErrorCode,
    required this.lastProtocolMessageType,
    required this.lastUnsupportedMessageType,
    required this.healthStatusLabel,
    required this.appStatusLabel,
  });

  final bool permissionsGranted;
  final bool bluetoothEnabled;
  final int deviceCount;
  final String? selectedDeviceId;
  final String? lastTransportState;
  final String? lastErrorCode;
  final int? lastProtocolMessageType;
  final int? lastUnsupportedMessageType;
  final String? healthStatusLabel;
  final String? appStatusLabel;

  static String _hexMessageType(int value) {
    return '0x${value.toRadixString(16).padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'BLE 驗證資訊',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF075985),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _DiagnosticChip(label: '模式：BLE'),
                _DiagnosticChip(label: permissionsGranted ? '權限：已允許' : '權限：未允許'),
                _DiagnosticChip(label: bluetoothEnabled ? '藍牙：已開啟' : '藍牙：未開啟'),
                _DiagnosticChip(label: '裝置數：$deviceCount'),
                _DiagnosticChip(label: '選擇：${selectedDeviceId ?? '無'}'),
                _DiagnosticChip(label: '狀態：${lastTransportState ?? '尚無'}'),
                _DiagnosticChip(label: '錯誤：${lastErrorCode ?? '無'}'),
                if (lastProtocolMessageType != null)
                  _DiagnosticChip(
                    label: '協定：${_hexMessageType(lastProtocolMessageType!)}',
                  ),
                if (lastUnsupportedMessageType != null)
                  _DiagnosticChip(
                    label:
                        '未支援：${_hexMessageType(lastUnsupportedMessageType!)}',
                  ),
                if (healthStatusLabel != null)
                  _DiagnosticChip(label: '健康：$healthStatusLabel'),
                if (appStatusLabel != null)
                  _DiagnosticChip(label: 'App：$appStatusLabel'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticChip extends StatelessWidget {
  const _DiagnosticChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFE0F2FE)),
    );
  }
}
