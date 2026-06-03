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
