import 'package:flutter/material.dart';
import 'package:vo2_flutter/app.dart';
import 'package:vo2_flutter/dev_ble_e2e_runner.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--ble-e2e')) {
    runApp(const DevBleE2eRunnerApp());
    return;
  }

  runApp(const Vo2MotionApp());
}
