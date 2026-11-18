import '../theme/app_theme.dart';

/// One entry under /lab/alerts, keyed by its push id.
class AlertEvent {
  final String id;
  final String message;
  final LabStatus severity;
  final DateTime timestamp;
  final bool acknowledged;

  const AlertEvent({
    required this.id,
    required this.message,
    required this.severity,
    required this.timestamp,
    this.acknowledged = false,
  });

  factory AlertEvent.fromMap(String id, Map<Object?, Object?> map) {
    return AlertEvent(
      id: id,
      // the firmware writes reason/status; the seeded rows use message/severity
      message: _toText(map['message']) ?? _toText(map['reason']) ?? '',
      severity: _toStatus(map['severity'] ?? map['status']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(_toInt(map['timestamp'])),
      acknowledged: map['acknowledged'] == true,
    );
  }

  Map<String, Object?> toMap() => {
    'message': message,
    'severity': severity.name,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'acknowledged': acknowledged,
  };

  @override
  String toString() =>
      'AlertEvent(id: $id, severity: ${severity.name}, '
      'timestamp: $timestamp, acknowledged: $acknowledged)';
}

int _toInt(Object? value) => (value as num?)?.toInt() ?? 0;

String? _toText(Object? value) => value is String && value.isNotEmpty ? value : null;

LabStatus _toStatus(Object? value) => switch (value) {
  'warning' => LabStatus.warning,
  'danger' => LabStatus.danger,
  _ => LabStatus.safe,
};
