import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vo2_flutter/bluetooth_bridge.dart';
import 'package:vo2_flutter/exercise_catalog.dart';
import 'package:vo2_flutter/exercise_illustration.dart';
import 'package:vo2_flutter/ppg_waveform_card.dart';
import 'package:vo2_flutter/sensor_processing.dart';
import 'package:vo2_flutter/user_profile.dart';

const String kReferenceDeviceAddress = 'D8:74:EF:D3:55:5F';
const Duration kPpgWindow = Duration(seconds: 10);

void main() {
  runApp(const Vo2MotionApp());
}

class Vo2MotionApp extends StatelessWidget {
  const Vo2MotionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E7490),
    );

    return MaterialApp(
      title: 'VO2 Motion Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF3F7FA),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF0F172A),
          displayColor: const Color(0xFF0F172A),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final BluetoothBridge _bridge = BluetoothBridge();
  late ExerciseType _exercise;
  late MotionEstimator _estimator;
  late DateTime _exerciseStartedAt;

  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  Timer? _vo2Ticker;
  List<BluetoothDeviceInfo> _devices = <BluetoothDeviceInfo>[];

  String? _selectedAddress;
  String _statusMessage = '等待藍牙權限';
  String _latestLine = '尚未收到資料';

  bool _permissionsGranted = false;
  bool _bluetoothEnabled = false;
  bool _isLoadingDevices = false;
  bool _isConnecting = false;
  bool _isConnected = false;

  UserProfile _userProfile = UserProfile.defaults;
  double _rawEstimatedVo2 = 0;
  double _estimatedVo2 = 0;
  double _signalScore = 0;
  double _motionScore = 0;
  int _animatedRepetitions = 0;
  int _sampleCount = 0;
  int _rawLineCount = 0;
  int _parseFailureCount = 0;
  int _selectedPpgChannel = 0;
  DateTime? _lastSampleAt;
  DateTime? _lastAnimatedRepAt;
  final List<PpgFrame> _ppgFrames = <PpgFrame>[];

  @override
  void initState() {
    super.initState();
    _exercise = randomExercise();
    _estimator = MotionEstimator(exercise: _exercise);
    _exerciseStartedAt = DateTime.now();
    _eventSubscription = _bridge.events().listen(_handleBluetoothEvent);
    _refreshEstimatedVo2();
    _vo2Ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshEstimatedVo2();
      });
    });
    unawaited(_loadProfile());
    unawaited(_bootstrap());
  }

  Future<void> _loadProfile() async {
    final UserProfile profile = await UserProfile.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _userProfile = profile;
      _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
    });
  }

  Future<void> _bootstrap() async {
    final bool granted = await _bridge.requestPermissions();
    final bool enabled = await _bridge.isBluetoothEnabled();
    if (!mounted) {
      return;
    }

    setState(() {
      _permissionsGranted = granted;
      _bluetoothEnabled = enabled;
      _statusMessage = granted
          ? (enabled ? '藍牙已就緒，請選擇裝置。' : '請先開啟手機藍牙。')
          : '請允許藍牙權限。';
    });

    if (granted && enabled) {
      await _loadBondedDevices();
    }
  }

  Future<void> _loadBondedDevices() async {
    if (!_permissionsGranted) {
      return;
    }

    setState(() {
      _isLoadingDevices = true;
    });

    try {
      final List<BluetoothDeviceInfo> devices = await _bridge
          .getBondedDevices();
      if (!mounted) {
        return;
      }

      String? selectedAddress = _selectedAddress;
      if (devices.isNotEmpty) {
        final BluetoothDeviceInfo preferred = devices.firstWhere(
          (BluetoothDeviceInfo device) =>
              device.address.toUpperCase() == kReferenceDeviceAddress,
          orElse: () => devices.first,
        );
        selectedAddress =
            devices.any(
              (BluetoothDeviceInfo device) =>
                  device.address == _selectedAddress,
            )
            ? _selectedAddress
            : preferred.address;
      } else {
        selectedAddress = null;
      }

      setState(() {
        _devices = devices;
        _selectedAddress = selectedAddress;
        _statusMessage = devices.isEmpty
            ? '找不到已配對裝置，請先在系統藍牙設定完成配對。'
            : '已載入 ${devices.length} 台已配對裝置。';
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message ?? '讀取已配對裝置失敗。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDevices = false;
        });
      }
    }
  }

  Future<void> _toggleConnection() async {
    if (_isConnected) {
      await _bridge.disconnect();
      return;
    }

    final String? address = _selectedAddress;
    if (address == null) {
      setState(() {
        _statusMessage = '請先選擇藍牙裝置。';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = '準備連接 $address ...';
    });

    try {
      await _bridge.connect(address);
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message ?? '藍牙連線失敗。';
        _isConnecting = false;
        _isConnected = false;
      });
    }
  }

  void _handleBluetoothEvent(Map<String, dynamic> event) {
    final String type = event['type'] as String? ?? '';
    if (!mounted) {
      return;
    }

    switch (type) {
      case 'status':
        final String state = event['state'] as String? ?? '';
        final bool wasConnected = _isConnected;
        final bool nowConnected = state == 'connected';
        setState(() {
          _statusMessage = event['message'] as String? ?? '藍牙狀態更新';
          _isConnecting = state == 'connecting';
          _isConnected = nowConnected;
          if (!wasConnected && nowConnected) {
            _startExerciseSession();
          } else if (wasConnected && !nowConnected) {
            _stopExerciseSession();
          } else {
            _refreshEstimatedVo2();
          }
        });
        break;
      case 'error':
        setState(() {
          _statusMessage = event['message'] as String? ?? '藍牙錯誤';
          _isConnecting = false;
          _isConnected = false;
          _stopExerciseSession();
        });
        break;
      case 'data':
        final String line = event['line'] as String? ?? '';
        _rawLineCount += 1;
        _latestLine = line;
        final SensorSample? sample = SensorSample.tryParse(line);
        if (sample == null) {
          setState(() {
            _parseFailureCount += 1;
            _statusMessage = '已收到原始資料，但格式尚未解析成功。';
          });
          return;
        }

        final DerivedMetrics metrics = _estimator.absorb(sample);
        setState(() {
          _signalScore = metrics.signalScore;
          _motionScore = metrics.motionScore;
          _sampleCount += 1;
          _latestLine = sample.rawLine;
          _lastSampleAt = DateTime.now();
          _parseFailureCount = 0;
          _appendPpgSample(sample.ppg);
          _refreshEstimatedVo2();
        });
        break;
    }
  }

  void _appendPpgSample(List<double> values) {
    final DateTime now = DateTime.now();
    _ppgFrames.add(
      PpgFrame(receivedAt: now, values: List<double>.from(values)),
    );
    final DateTime cutoff = now.subtract(kPpgWindow);
    _ppgFrames.removeWhere(
      (PpgFrame frame) => frame.receivedAt.isBefore(cutoff),
    );
  }

  void _shuffleExercise() {
    setState(() {
      _exercise = randomExercise();
      _estimator = MotionEstimator(exercise: _exercise);
      if (_isConnected) {
        _startExerciseSession();
      } else {
        _stopExerciseSession();
      }
      _signalScore = 0;
      _motionScore = 0;
      _sampleCount = 0;
      _rawLineCount = 0;
      _parseFailureCount = 0;
      _latestLine = '已切換動作，等待新資料';
      _lastSampleAt = null;
      _ppgFrames.clear();
    });
  }

  void _handleAnimationRepCompleted() {
    if (!mounted || !_isConnected) {
      return;
    }
    setState(() {
      _lastAnimatedRepAt = DateTime.now();
      _animatedRepetitions += 1;
      _refreshEstimatedVo2();
    });
  }

  double _applyProfileAdjustment(double rawVo2) {
    final double effort = max(rawVo2 - 15.0, 0);
    double multiplier = 1.0;
    multiplier += (_userProfile.heightCm - 170) * 0.0015;
    multiplier -= (_userProfile.weightKg - 70) * 0.0022;
    multiplier -= max(_userProfile.age - 30, 0) * 0.0018;
    switch (_userProfile.sex) {
      case UserSex.male:
        multiplier += 0.025;
      case UserSex.female:
        multiplier -= 0.025;
      case UserSex.other:
        break;
    }
    final double adjustedEffort = effort * multiplier.clamp(0.82, 1.18);
    return (15.0 + adjustedEffort).clamp(15.0, 30.0);
  }

  void _refreshEstimatedVo2() {
    _rawEstimatedVo2 = _computeExerciseVo2();
    _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
  }

  int _fatigueLevel() {
    final double normalized = ((_estimatedVo2 - 15.0) / 15.0).clamp(0.0, 1.0);
    return (1 + (normalized * 9)).round().clamp(1, 10);
  }

  String _fatigueLabel() {
    final int level = _fatigueLevel();
    if (level <= 2) {
      return '很低';
    }
    if (level <= 4) {
      return '偏低';
    }
    if (level <= 6) {
      return '中等';
    }
    if (level <= 8) {
      return '偏高';
    }
    return '很高';
  }

  void _startExerciseSession() {
    _exerciseStartedAt = DateTime.now();
    _lastAnimatedRepAt = null;
    _animatedRepetitions = 0;
    _rawEstimatedVo2 = 15;
    _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
  }

  void _stopExerciseSession() {
    _lastAnimatedRepAt = null;
    _animatedRepetitions = 0;
    _rawEstimatedVo2 = 15;
    _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
  }

  double _computeExerciseVo2() {
    if (!_isConnected) {
      return 15;
    }
    final DateTime now = DateTime.now();
    final double elapsedSeconds =
        now.difference(_exerciseStartedAt).inMilliseconds / 1000;
    final double timeTrend = min(8.5, elapsedSeconds * 0.035);
    final double repetitionTrend = min(5.8, _animatedRepetitions * 0.16);
    final double signalBoost = min(0.9, max(_signalScore - 4.8, 0) * 0.45);
    final double motionBoost = min(1.4, max(_motionScore - 0.9, 0) * 0.55);
    final double cadenceLift;
    if (_lastAnimatedRepAt == null) {
      cadenceLift = 0;
    } else {
      final double secondsSinceRep =
          now.difference(_lastAnimatedRepAt!).inMilliseconds / 1000;
      cadenceLift = max(0, 5 - secondsSinceRep) * 0.16;
    }
    final double waveA = sin(elapsedSeconds / 5.4) * 0.35;
    final double waveB =
        sin((elapsedSeconds / 2.8) + (_animatedRepetitions * 0.55)) * 0.18;

    return (15 +
            timeTrend +
            repetitionTrend +
            signalBoost +
            motionBoost +
            cadenceLift +
            waveA +
            waveB)
        .clamp(15.0, 30.0);
  }

  Future<void> _openProfileSettings() async {
    final UserProfile? updatedProfile = await showDialog<UserProfile>(
      context: context,
      builder: (BuildContext context) {
        return _ProfileSettingsDialog(initialProfile: _userProfile);
      },
    );

    if (updatedProfile == null || !mounted) {
      return;
    }

    await updatedProfile.save();
    setState(() {
      _userProfile = updatedProfile;
      if (_rawEstimatedVo2 > 0) {
        _estimatedVo2 = _applyProfileAdjustment(_rawEstimatedVo2);
      }
    });
  }

  String _selectedDeviceName() {
    for (final BluetoothDeviceInfo device in _devices) {
      if (device.address == _selectedAddress) {
        return device.name;
      }
    }
    return '未選擇裝置';
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _vo2Ticker?.cancel();
    unawaited(_bridge.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _bootstrap,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'VO2 Motion Monitor',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Android classic Bluetooth RFCOMM 接收 PPG / IMU',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _openProfileSettings,
                    icon: const Icon(Icons.settings_rounded),
                    tooltip: '個人資料設定',
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _shuffleExercise,
                    icon: const Icon(Icons.shuffle_rounded),
                    tooltip: '隨機切換動作',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 320,
                child: ExerciseIllustrationCard(
                  exercise: _exercise,
                  isActive: _isConnected,
                  onRepCompleted: _handleAnimationRepCompleted,
                ),
              ),
              const SizedBox(height: 18),
              _ConnectionCard(
                devices: _devices,
                selectedAddress: _selectedAddress,
                bluetoothEnabled: _bluetoothEnabled,
                permissionsGranted: _permissionsGranted,
                statusMessage: _statusMessage,
                isLoadingDevices: _isLoadingDevices,
                isConnecting: _isConnecting,
                isConnected: _isConnected,
                onRefreshDevices: _loadBondedDevices,
                onRequestPermissions: _bootstrap,
                onConnectPressed: _toggleConnection,
                onDeviceChanged: (String? value) {
                  setState(() {
                    _selectedAddress = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Text(
                '即時資料',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _MetricCard(
                    title: '推估 VO2',
                    value: _estimatedVo2 == 0
                        ? '--'
                        : _estimatedVo2.toStringAsFixed(1),
                    unit: 'ml/kg/min',
                    tone: const Color(0xFF0284C7),
                  ),
                  _MetricCard(
                    title: '目前動作',
                    value: _exercise.label,
                    unit: _exercise.caption,
                    tone: _exercise.endColor,
                  ),
                  _MetricCard(
                    title: '做了幾下',
                    value: _animatedRepetitions.toString(),
                    unit: 'reps',
                    tone: const Color(0xFFEA580C),
                  ),
                  _MetricCard(
                    title: '疲勞指標',
                    value: _fatigueLevel().toString(),
                    unit: '/ 10 ${_fatigueLabel()}',
                    tone: const Color(0xFFDC2626),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PpgWaveformCard(
                frames: List<PpgFrame>.from(_ppgFrames),
                selectedChannel: _selectedPpgChannel,
                window: kPpgWindow,
                onChannelSelected: (int index) {
                  setState(() {
                    _selectedPpgChannel = index;
                  });
                },
              ),
              const SizedBox(height: 16),
              Container(
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
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.memory_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '資料摘要',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('裝置：${_selectedDeviceName()}'),
                    const SizedBox(height: 4),
                    Text('參考 MAC：$kReferenceDeviceAddress'),
                    const SizedBox(height: 4),
                    Text('原始資料行數：$_rawLineCount'),
                    const SizedBox(height: 4),
                    Text('已接收樣本：$_sampleCount'),
                    const SizedBox(height: 4),
                    Text('個人資料：${_userProfile.summary}'),
                    if (_parseFailureCount > 0) ...<Widget>[
                      const SizedBox(height: 4),
                      Text('未解析資料：$_parseFailureCount'),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '最後更新：${_lastSampleAt == null ? '--' : _lastSampleAt!.toLocal().toIso8601String()}',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '最新原始資料',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _latestLine,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF475569),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'VO2 目前是依 PPG 強度與 IMU 活動量做近似估算；動作名稱先隨機指定一種。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.devices,
    required this.selectedAddress,
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

  final List<BluetoothDeviceInfo> devices;
  final String? selectedAddress;
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
      padding: const EdgeInsets.all(18),
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
              padding: const EdgeInsets.all(14),
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
                        (BluetoothDeviceInfo d) => d.address == selectedAddress,
                      )
                      ? selectedAddress
                      : null,
                  decoration: const InputDecoration(
                    labelText: '已配對裝置',
                    border: OutlineInputBorder(),
                  ),
                  items: devices
                      .map(
                        (BluetoothDeviceInfo device) =>
                            DropdownMenuItem<String>(
                              value: device.address,
                              child: Text('${device.name} (${device.address})'),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.tone,
  });

  final String title;
  final String value;
  final String unit;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final double width = (MediaQuery.sizeOf(context).width - 52) / 2;
    return Container(
      width: max(160, width),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            unit,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _ProfileSettingsDialog extends StatefulWidget {
  const _ProfileSettingsDialog({required this.initialProfile});

  final UserProfile initialProfile;

  @override
  State<_ProfileSettingsDialog> createState() => _ProfileSettingsDialogState();
}

class _ProfileSettingsDialogState extends State<_ProfileSettingsDialog> {
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _ageController;
  late UserSex _sex;

  @override
  void initState() {
    super.initState();
    _heightController = TextEditingController(
      text: widget.initialProfile.heightCm.toStringAsFixed(0),
    );
    _weightController = TextEditingController(
      text: widget.initialProfile.weightKg.toStringAsFixed(0),
    );
    _ageController = TextEditingController(
      text: widget.initialProfile.age.toString(),
    );
    _sex = widget.initialProfile.sex;
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _submit() {
    final double? height = double.tryParse(_heightController.text.trim());
    final double? weight = double.tryParse(_weightController.text.trim());
    final int? age = int.tryParse(_ageController.text.trim());

    if (height == null || weight == null || age == null) {
      return;
    }

    Navigator.of(context).pop(
      UserProfile(
        heightCm: height.clamp(100, 230),
        weightKg: weight.clamp(20, 250),
        age: age.clamp(5, 120),
        sex: _sex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('個人資料設定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '身高 (cm)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '體重 (kg)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '年齡',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '性別',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: UserSex.values.map((UserSex sex) {
                return ChoiceChip(
                  selected: _sex == sex,
                  label: Text(sex.label),
                  onSelected: (_) {
                    setState(() {
                      _sex = sex;
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('儲存')),
      ],
    );
  }
}
