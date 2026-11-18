import '../theme/app_theme.dart';

/// One reading from /lab/live (or an entry under /lab/history).
class SensorData {
  final double temp;
  final double humidity;

  /// Raw MQ-2 ADC count, 0-4095.
  final int gas;

  /// Centimetres from the ultrasonic sensor, or -1 when no echo came back.
  final double distance;

  /// True while something sits closer than the presence threshold.
  final bool personPresent;

  /// False during the MQ-2's warm-up, when [gas] does not mean anything yet.
  final bool gasReady;

  final LabStatus status;
  final DateTime timestamp;

  const SensorData({
    required this.temp,
    required this.humidity,
    required this.gas,
    required this.distance,
    required this.status,
    required this.timestamp,
    this.personPresent = false,
    this.gasReady = true,
  });

  /// A missed echo arrives as -1, which is not a distance worth showing.
  bool get hasDistance => distance >= 0;

  factory SensorData.fromMap(Map<Object?, Object?> map) {
    return SensorData(
      temp: _toDouble(map['temp']),
      humidity: _toDouble(map['humidity']),
      gas: _toInt(map['gas']),
      distance: _toDouble(map['distance'], fallback: -1),
      personPresent: map['personPresent'] == true,
      // absent from history entries and from the seeded rows: assume ready
      gasReady: map['gasReady'] != false,
      status: _toStatus(map['status']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(_toInt(map['timestamp'])),
    );
  }

  Map<String, Object?> toMap() => {
    'temp': temp,
    'humidity': humidity,
    'gas': gas,
    'distance': distance,
    'personPresent': personPresent,
    'gasReady': gasReady,
    'status': status.name,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  @override
  String toString() =>
      'SensorData(temp: $temp, humidity: $humidity, gas: $gas, '
      'distance: $distance, person: $personPresent, '
      'status: ${status.name}, timestamp: $timestamp)';
}

// RTDB hands back int for whole numbers and double otherwise, so widen via num.
double _toDouble(Object? value, {double fallback = 0}) =>
    (value as num?)?.toDouble() ?? fallback;

int _toInt(Object? value) => (value as num?)?.toInt() ?? 0;

LabStatus _toStatus(Object? value) => switch (value) {
  'warning' => LabStatus.warning,
  'danger' => LabStatus.danger,
  _ => LabStatus.safe,
};
