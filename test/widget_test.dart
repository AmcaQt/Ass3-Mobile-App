// Smoke test for the app shell, driven by a fake database.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:lab_safety_monitor/models/alert_event.dart';
import 'package:lab_safety_monitor/models/sensor_data.dart';
import 'package:lab_safety_monitor/screens/app_shell.dart';
import 'package:lab_safety_monitor/services/db_service.dart';
import 'package:lab_safety_monitor/theme/app_theme.dart';

/// implements, not extends: extending would run the real constructor, which
/// reaches for FirebaseDatabase.instance and throws in a widget test.
class _FakeDb extends Fake implements DbService {
  @override
  Stream<SensorData?> watchLive() => Stream.value(SensorData(
    temp: 31.4,
    humidity: 68,
    gas: 820,
    distance: 64,
    personPresent: true,
    status: LabStatus.safe,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1761530400000),
  ));

  @override
  Stream<bool> watchDeviceOnline({
    Duration staleAfter = const Duration(seconds: 15),
  }) =>
      Stream.value(true);

  @override
  Stream<Map<String, num>> watchThresholds() => Stream.value(const {
    'tempWarn': 32,
    'tempDanger': 40,
    'gasWarn': 1500,
    'gasDanger': 2500,
  });

  @override
  Stream<Map<String, bool>> watchOutputs() => Stream.value(const {
    'green': true,
    'yellow': false,
    'white': false,
    'buzzer': false,
  });

  @override
  Stream<String> watchMode() => Stream.value('auto');

  @override
  Stream<List<SensorData>> watchHistory({int limit = 50}) =>
      Stream.value(const <SensorData>[]);

  @override
  Stream<List<AlertEvent>> watchAlerts({int limit = 50}) =>
      Stream.value(const <AlertEvent>[]);
}

void main() {
  setUpAll(() {
    // no network in tests: use the bundled fallback font, quietly
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: AppShell(db: _FakeDb()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('app shell starts on Dashboard and can switch tabs',
          (WidgetTester tester) async {
        await pumpShell(tester);

        // app bar title + nav label; the body now shows readings, not the word
        expect(find.text('Dashboard'), findsNWidgets(2));
        expect(find.text('SAFE'), findsOneWidget);
        // the ultrasonic reading, and the flag the number alone does not carry
        expect(find.text('64'), findsOneWidget);
        expect(find.text('Person at the bench'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.history_outlined));
        await tester.pumpAndSettle();

        expect(find.text('History'), findsNWidgets(2));
      });

  testWidgets('Control lists the four board outputs, every one of them live',
          (WidgetTester tester) async {
        await pumpShell(tester);

        await tester.tap(find.byIcon(Icons.tune_outlined));
        await tester.pumpAndSettle();

        for (final label in ['Green LED', 'Yellow LED', 'White LED', 'Buzzer']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('The device is driving the outputs'), findsOneWidget);
        // nothing to hand back while the device still owns them
        expect(find.text('Hand back to the device'), findsNothing);

        // green is the only output the device reports as on
        final switches = tester.widgetList<SwitchListTile>(
          find.byType(SwitchListTile),
        );
        expect(switches.map((tile) => tile.value), [true, false, false, false]);

        // no mode to pick first: a switch is tappable whatever the device says
        expect(switches.every((tile) => tile.onChanged != null), isTrue);
      });
}
