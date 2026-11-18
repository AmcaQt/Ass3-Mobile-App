import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sensor_data.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';

/// The four series that can be plotted, in nav order.
enum _Metric { temp, humidity, gas, distance }

extension _MetricX on _Metric {
  String get short => switch (this) {
    _Metric.temp => 'Temp',
    _Metric.humidity => 'Hum',
    _Metric.gas => 'Gas',
    _Metric.distance => 'Dist',
  };

  String get label => switch (this) {
    _Metric.temp => 'Temperature',
    _Metric.humidity => 'Humidity',
    _Metric.gas => 'Gas',
    _Metric.distance => 'Distance',
  };

  // gas is a raw ADC count, so it carries no unit
  String get unit => switch (this) {
    _Metric.temp => '°C',
    _Metric.humidity => '%',
    _Metric.gas => '',
    _Metric.distance => 'cm',
  };

  int get decimals => this == _Metric.temp ? 1 : 0;

  Color get color => switch (this) {
    _Metric.temp => AppColors.danger,
    _Metric.humidity => AppColors.safe,
    _Metric.gas => AppColors.warning,
    _Metric.distance => const Color(0xFF4A7FA5),
  };

  double of(SensorData data) => switch (this) {
    _Metric.temp => data.temp,
    _Metric.humidity => data.humidity,
    _Metric.gas => data.gas.toDouble(),
    _Metric.distance => data.distance,
  };
}

// no Scaffold: AppShell provides it
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.db});

  /// Injectable for tests; defaults to a service on FirebaseDatabase.instance.
  final DbService? db;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final DbService _db = widget.db ?? DbService();

  // Held in a field so a rebuild does not resubscribe the RTDB listener.
  late final Stream<List<SensorData>> _history = _db.watchHistory();

  _Metric _metric = _Metric.temp;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SensorData>>(
      stream: _history,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message('Could not read the history.\n${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final readings = snapshot.data ?? const <SensorData>[];
        if (readings.isEmpty) {
          return const _Message(
            'No history yet.\nThe device has not written to /lab/history.',
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Metric>(
                showSelectedIcon: false,
                segments: [
                  for (final metric in _Metric.values)
                    ButtonSegment(value: metric, label: Text(metric.short)),
                ],
                selected: {_metric},
                onSelectionChanged: (selection) =>
                    setState(() => _metric = selection.first),
              ),
            ),
            const SizedBox(height: 16),
            _ChartCard(readings: readings, metric: _metric),
            const SizedBox(height: 12),
            _Stats(readings: readings, metric: _metric),
            const SizedBox(height: 12),
            _Footer(readings: readings),
          ],
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.readings, required this.metric});

  final List<SensorData> readings;
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final values = [for (final reading in readings) metric.of(reading)];

    // Pad the y-axis by a tenth of the spread so the line is not on the edge;
    // a flat series has no spread, so fall back to a fixed margin.
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final pad = high == low ? (high.abs() * 0.1).clamp(1, 100) : (high - low) * 0.1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                metric.label.toUpperCase(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: muted, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: low - pad,
                  maxY: high + pad,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: theme.colorScheme.outline, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            value.toStringAsFixed(metric.decimals),
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(color: muted),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        // x is the index in the list, so one label per step
                        interval: _labelInterval(readings.length),
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= readings.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat.Hm().format(readings[index].timestamp),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: muted),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => theme.colorScheme.onSurface,
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            '${spot.y.toStringAsFixed(metric.decimals)}'
                            '${metric.unit.isEmpty ? '' : ' ${metric.unit}'}',
                            TextStyle(
                              color: theme.colorScheme.surface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < values.length; i++)
                          FlSpot(i.toDouble(), values[i]),
                      ],
                      isCurved: true,
                      curveSmoothness: 0.2,
                      barWidth: 2,
                      color: metric.color,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: metric.color.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Four or five labels across the axis, whatever the sample count.
  static double _labelInterval(int count) =>
      count <= 5 ? 1 : (count / 4).ceilToDouble();
}

class _Stats extends StatelessWidget {
  const _Stats({required this.readings, required this.metric});

  final List<SensorData> readings;
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final values = [for (final reading in readings) metric.of(reading)];
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final mean = values.reduce((a, b) => a + b) / values.length;

    String format(double value) =>
        value.toStringAsFixed(metric.decimals) +
        (metric.unit.isEmpty ? '' : metric.unit);

    return Row(
      children: [
        Expanded(child: _Stat(label: 'Min', value: format(low))),
        const SizedBox(width: 12),
        Expanded(child: _Stat(label: 'Avg', value: format(mean))),
        const SizedBox(width: 12),
        Expanded(child: _Stat(label: 'Max', value: format(high))),
        const SizedBox(width: 12),
        Expanded(child: _Stat(label: 'Last', value: format(values.last))),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.readings});

  final List<SensorData> readings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat.Hm();
    final span = readings.length == 1
        ? format.format(readings.first.timestamp)
        : '${format.format(readings.first.timestamp)} – '
            '${format.format(readings.last.timestamp)}';

    return Text(
      '${readings.length} reading${readings.length == 1 ? '' : 's'} · $span',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
