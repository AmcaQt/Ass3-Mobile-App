import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../models/alert_event.dart';
import '../models/sensor_data.dart';

/// Reads and writes the /lab subtree of the Realtime Database.
class DbService {
  DbService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  // Every path the app touches, in one place.
  static const livePath = 'lab/live';
  static const actuatorsPath = 'lab/actuators';
  static const thresholdsPath = 'lab/thresholds';
  static const devicePath = 'lab/device';
  static const historyPath = 'lab/history';
  static const alertsPath = 'lab/alerts';

  /// The four outputs on the board, as the firmware names them.
  static const outputNames = ['green', 'yellow', 'white', 'buzzer'];

  // --- live reading -------------------------------------------------------

  Stream<SensorData?> watchLive() => _db.ref(livePath).onValue.map((event) {
    final value = event.snapshot.value;
    return value is Map ? SensorData.fromMap(value) : null;
  });

  // --- actuators ----------------------------------------------------------

  /// What the app is asking the device to do: { green, yellow, white, buzzer,
  /// mode }. The firmware polls this node, so it is a request, not a report.
  Stream<Map<String, Object?>> watchActuators() =>
      _db.ref(actuatorsPath).onValue.map((e) => _asStringMap(e.snapshot.value));

  /// [name] is one of [outputNames].
  Future<void> setOutput(String name, bool on) =>
      _db.ref('$actuatorsPath/$name').set(on);

  Future<void> setMode(String mode) => _db.ref('$actuatorsPath/mode').set(mode);

  // --- what the device is actually doing ----------------------------------

  /// The firmware publishes its real output state under live/outputs, so the
  /// switches can show what the board is doing rather than echoing our write.
  Stream<Map<String, bool>> watchOutputs() =>
      _db.ref('$livePath/outputs').onValue.map((event) {
        final raw = _asStringMap(event.snapshot.value);
        return {for (final name in outputNames) name: raw[name] == true};
      });

  /// 'auto' or 'manual', as reported by the device.
  Stream<String> watchMode() => _db
      .ref('$livePath/mode')
      .onValue
      .map((e) => e.snapshot.value == 'manual' ? 'manual' : 'auto');

  // --- thresholds ---------------------------------------------------------

  /// { tempWarn, tempDanger, gasWarn, gasDanger }
  Stream<Map<String, num>> watchThresholds() =>
      _db.ref(thresholdsPath).onValue.map((event) {
        final raw = _asStringMap(event.snapshot.value);
        return {
          for (final entry in raw.entries)
            if (entry.value is num) entry.key: entry.value as num,
        };
      });

  Future<void> setThreshold(String key, num value) =>
      _db.ref('$thresholdsPath/$key').set(value);

  // --- device -------------------------------------------------------------

  /// The firmware talks to RTDB over REST, so it has no onDisconnect handler
  /// and never writes device/online. "Online" therefore means lastSeen is
  /// recent, re-checked on a timer because a device that stops writing
  /// produces no event to react to.
  Stream<bool> watchDeviceOnline({
    Duration staleAfter = const Duration(seconds: 15),
  }) {
    final controller = StreamController<bool>.broadcast();
    DateTime? lastSeen;
    StreamSubscription<DatabaseEvent>? subscription;
    Timer? timer;

    void emit() {
      final seen = lastSeen;
      controller.add(
        seen != null && DateTime.now().difference(seen) < staleAfter,
      );
    }

    controller.onListen = () {
      subscription = _db.ref('$devicePath/lastSeen').onValue.listen(
        (event) {
          final value = event.snapshot.value;
          lastSeen = value is num
              ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
              : null;
          emit();
        },
        onError: controller.addError,
      );
      timer = Timer.periodic(const Duration(seconds: 1), (_) => emit());
    };
    controller.onCancel = () async {
      timer?.cancel();
      await subscription?.cancel();
    };

    // distinct: the timer ticks every second, the answer rarely changes
    return controller.stream.distinct();
  }

  // --- history and alerts -------------------------------------------------
  // The firmware POSTs to both nodes, so entries arrive under push ids.

  /// Oldest first, so the result can be plotted straight onto a chart.
  Stream<List<SensorData>> watchHistory({int limit = 50}) => _db
      .ref(historyPath)
      .orderByChild('timestamp')
      .limitToLast(limit)
      .onValue
      .map(
        (event) => [
          for (final child in event.snapshot.children)
            if (child.value is Map) SensorData.fromMap(child.value as Map),
        ],
      );

  /// Newest first, for the alerts list.
  Stream<List<AlertEvent>> watchAlerts({int limit = 50}) => _db
      .ref(alertsPath)
      .orderByChild('timestamp')
      .limitToLast(limit)
      .onValue
      .map(
        (event) => [
          for (final child in event.snapshot.children)
            if (child.value is Map)
              AlertEvent.fromMap(child.key!, child.value as Map),
        ].reversed.toList(),
      );

  Future<void> acknowledgeAlert(String id) =>
      _db.ref('$alertsPath/$id/acknowledged').set(true);
}

Map<String, Object?> _asStringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, v) => MapEntry(key.toString(), v));
}
