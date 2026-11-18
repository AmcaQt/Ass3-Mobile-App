// Checks seed_full.json against the models that have to read it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_safety_monitor/models/alert_event.dart';
import 'package:lab_safety_monitor/models/sensor_data.dart';
import 'package:lab_safety_monitor/theme/app_theme.dart';

void main() {
  final lab = (jsonDecode(File('seed_full.json').readAsStringSync())
      as Map<String, Object?>)['lab'] as Map<String, Object?>;

  test('live parses, with a usable distance and the device flags', () {
    final live = SensorData.fromMap(lab['live'] as Map<Object?, Object?>);
    expect(live.temp, 32.1);
    expect(live.status, LabStatus.warning);
    expect(live.hasDistance, isTrue);
    expect(live.distance, 110);
    expect(live.gasReady, isTrue);
  });

  test('every history row carries a distance', () {
    final rows = (lab['history'] as Map<Object?, Object?>)
        .values
        .map((row) => SensorData.fromMap(row as Map<Object?, Object?>))
        .toList();
    expect(rows, hasLength(40));
    expect(rows.every((row) => row.hasDistance), isTrue);
  });

  test('alerts keep their text and severity', () {
    final alerts = (lab['alerts'] as Map<Object?, Object?>)
        .entries
        .map((e) =>
            AlertEvent.fromMap(e.key as String, e.value as Map<Object?, Object?>))
        .toList();
    expect(alerts, hasLength(5));
    expect(alerts.every((a) => a.message.isNotEmpty), isTrue);
    expect(alerts.any((a) => a.severity == LabStatus.warning), isTrue);
  });

  test('outputs cover the four the Control tab asks for', () {
    final outputs =
        (lab['live'] as Map<String, Object?>)['outputs'] as Map<String, Object?>;
    expect(outputs.keys, containsAll(['green', 'yellow', 'white', 'buzzer']));
    // status is warning, so the yellow lamp is the one lit
    expect(outputs['yellow'], isTrue);
  });

  test('actuators and thresholds match what the app writes', () {
    final actuators = lab['actuators'] as Map<String, Object?>;
    expect(actuators.keys,
        containsAll(['green', 'yellow', 'white', 'buzzer', 'mode']));
    expect(actuators.containsKey('fan'), isFalse);

    final thresholds = lab['thresholds'] as Map<String, Object?>;
    expect(thresholds.keys,
        containsAll(['tempWarn', 'tempDanger', 'gasWarn', 'gasDanger']));
  });
}
