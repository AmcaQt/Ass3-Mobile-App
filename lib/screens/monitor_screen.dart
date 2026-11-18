import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import '../models/sensor_data.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';

// no Scaffold: AppShell provides it
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key, this.db});

  /// Injectable for tests; defaults to a service on FirebaseDatabase.instance.
  final DbService? db;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  late final DbService _db = widget.db ?? DbService();

  // Held in fields so a rebuild does not resubscribe the RTDB listeners.
  late final Stream<SensorData?> _live = _db.watchLive();
  late final Stream<Map<String, num>> _thresholds = _db.watchThresholds();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SensorData?>(
      stream: _live,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message('Could not read sensors.\n${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (data == null) {
          return const _Message('No sensor data yet.');
        }
        // Thresholds only recolour the dials, so missing ones are not an error.
        return StreamBuilder<Map<String, num>>(
          stream: _thresholds,
          builder: (context, thresholds) =>
              _Gauges(data: data, thresholds: thresholds.data ?? const {}),
        );
      },
    );
  }
}

class _Gauges extends StatelessWidget {
  const _Gauges({required this.data, required this.thresholds});

  final SensorData data;
  final Map<String, num> thresholds;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _GaugeCard(
          label: 'Temperature',
          value: data.temp,
          unit: '°C',
          max: 50,
          interval: 10,
          decimals: 1,
          warn: thresholds['tempWarn'],
          danger: thresholds['tempDanger'],
        ),
        const SizedBox(height: 12),
        _GaugeCard(
          label: 'Humidity',
          value: data.humidity,
          unit: '%',
          max: 100,
          interval: 20,
        ),
        const SizedBox(height: 12),
        // gas is a raw ADC count, so it carries no unit
        _GaugeCard(
          label: data.gasReady ? 'Gas' : 'Gas · warming up',
          value: data.gas.toDouble(),
          max: 4095,
          interval: 1000,
          warn: thresholds['gasWarn'],
          danger: thresholds['gasDanger'],
        ),
        const SizedBox(height: 12),
        // no bands: for distance a low reading is the notable one, which is the
        // opposite of how _ranges shades a dial
        _GaugeCard(
          label: _distanceLabel,
          value: data.hasDistance ? data.distance : 0,
          unit: 'cm',
          max: 200,
          interval: 50,
        ),
      ],
    );
  }

  String get _distanceLabel {
    if (!data.hasDistance) return 'Distance · no echo';
    return data.personPresent ? 'Distance · person present' : 'Distance';
  }
}

class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.label,
    required this.value,
    required this.max,
    required this.interval,
    this.unit,
    this.decimals = 0,
    this.warn,
    this.danger,
  });

  final String label;
  final double value;
  final double max;
  final double interval;
  final String? unit;
  final int decimals;
  final num? warn;
  final num? danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: muted, letterSpacing: 1),
            ),
            SizedBox(
              height: 190,
              child: SfRadialGauge(
                axes: [
                  RadialAxis(
                    minimum: 0,
                    maximum: max,
                    interval: interval,
                    startAngle: 150,
                    endAngle: 30,
                    minorTicksPerInterval: 0,
                    axisLineStyle: AxisLineStyle(
                      thickness: 0.1,
                      thicknessUnit: GaugeSizeUnit.factor,
                      color: theme.colorScheme.outline,
                    ),
                    majorTickStyle: MajorTickStyle(
                      length: 0.06,
                      lengthUnit: GaugeSizeUnit.factor,
                      thickness: 1.5,
                      color: muted,
                    ),
                    axisLabelStyle: GaugeTextStyle(fontSize: 10, color: muted),
                    ranges: _ranges(theme),
                    pointers: [
                      NeedlePointer(
                        // a reading past the dial would point off the scale
                        value: value.clamp(0, max),
                        needleLength: 0.68,
                        lengthUnit: GaugeSizeUnit.factor,
                        needleColor: theme.colorScheme.onSurface,
                        needleStartWidth: 1,
                        needleEndWidth: 4,
                        knobStyle: KnobStyle(
                          knobRadius: 0.05,
                          sizeUnit: GaugeSizeUnit.factor,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                    annotations: [
                      GaugeAnnotation(
                        angle: 90,
                        positionFactor: 0.9,
                        widget: _Reading(
                          text: value.toStringAsFixed(decimals),
                          unit: unit,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Green up to [warn], amber up to [danger], red beyond. Dials with no
  /// thresholds in the database get one neutral band instead.
  List<GaugeRange> _ranges(ThemeData theme) {
    final warnAt = warn?.toDouble();
    final dangerAt = danger?.toDouble();
    if (warnAt == null || dangerAt == null) {
      return [_range(0, max, theme.colorScheme.outline)];
    }
    return [
      _range(0, warnAt.clamp(0, max), AppColors.safe),
      if (warnAt < max)
        _range(warnAt, dangerAt.clamp(warnAt, max), AppColors.warning),
      if (dangerAt < max) _range(dangerAt, max, AppColors.danger),
    ];
  }

  GaugeRange _range(double start, double end, Color color) => GaugeRange(
    startValue: start,
    endValue: end,
    color: color,
    startWidth: 0.1,
    endWidth: 0.1,
    sizeUnit: GaugeSizeUnit.factor,
  );
}

class _Reading extends StatelessWidget {
  const _Reading({required this.text, this.unit});

  final String text;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(text, style: theme.textTheme.headlineMedium),
        if (unit != null) ...[
          const SizedBox(width: 4),
          Text(
            unit!,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
