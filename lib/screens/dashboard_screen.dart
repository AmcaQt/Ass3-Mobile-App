import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sensor_data.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';

// no Scaffold: AppShell provides it
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.db});

  /// Injectable for tests; defaults to a service on FirebaseDatabase.instance.
  final DbService? db;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DbService _db = widget.db ?? DbService();

  // Held in fields so a rebuild does not resubscribe the RTDB listeners.
  late final Stream<SensorData?> _live = _db.watchLive();
  late final Stream<bool> _online = _db.watchDeviceOnline();

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
        return _Dashboard(data: data, online: _online);
      },
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.data, required this.online});

  final SensorData data;
  final Stream<bool> online;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusBanner(status: data.status),
        _Flags(data: data),
        const SizedBox(height: 12),
        _DeviceRow(online: online, timestamp: data.timestamp),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: [
            // gas is a raw ADC count, so it carries no unit
            _MetricCard(label: 'Temperature', value: data.temp.toStringAsFixed(1), unit: '°C'),
            _MetricCard(label: 'Humidity', value: data.humidity.toStringAsFixed(0), unit: '%'),
            _MetricCard(label: 'Gas', value: '${data.gas}'),
            _MetricCard(
              label: 'Distance',
              value: data.hasDistance ? data.distance.toStringAsFixed(0) : '—',
              unit: data.hasDistance ? 'cm' : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// The two things the readings alone do not say: whether someone is at the
/// bench, and whether the gas number can be trusted yet.
class _Flags extends StatelessWidget {
  const _Flags({required this.data});

  final SensorData data;

  @override
  Widget build(BuildContext context) {
    final flags = [
      if (data.personPresent) 'Person at the bench',
      if (!data.gasReady) 'Gas sensor warming up',
    ];
    if (flags.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final flag in flags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(flag, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final LabStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: status.color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: status.onColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.online, required this.timestamp});

  final Stream<bool> online;
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: muted);

    return Row(
      children: [
        StreamBuilder<bool>(
          stream: online,
          builder: (context, snapshot) {
            final isOnline = snapshot.data ?? false;
            return Row(
              children: [
                Icon(
                  isOnline ? Icons.circle : Icons.circle_outlined,
                  size: 10,
                  color: isOnline ? AppColors.safe : muted,
                ),
                const SizedBox(width: 6),
                Text(isOnline ? 'Device online' : 'Device offline', style: style),
              ],
            );
          },
        ),
        const Spacer(),
        Text('Updated ${DateFormat.Hms().format(timestamp)}', style: style),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
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
