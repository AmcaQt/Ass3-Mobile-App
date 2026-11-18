import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert_event.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';

enum _Filter { all, unread }

// no Scaffold: AppShell provides it
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, this.db});

  /// Injectable for tests; defaults to a service on FirebaseDatabase.instance.
  final DbService? db;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final DbService _db = widget.db ?? DbService();

  // Held in a field so a rebuild does not resubscribe the RTDB listener.
  late final Stream<List<AlertEvent>> _alerts = _db.watchAlerts();

  _Filter _filter = _Filter.all;

  Future<void> _acknowledge(AlertEvent alert) async {
    try {
      await _db.acknowledgeAlert(alert.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not acknowledge the alert.\n$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AlertEvent>>(
      stream: _alerts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message('Could not read the alerts.\n${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final alerts = snapshot.data ?? const <AlertEvent>[];
        if (alerts.isEmpty) {
          return const _Message(
            'No alerts yet.\nNothing has written to /lab/alerts.',
          );
        }

        final unread = alerts.where((alert) => !alert.acknowledged).length;
        final shown = _filter == _Filter.unread
            ? [for (final alert in alerts) if (!alert.acknowledged) alert]
            : alerts;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Filter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Filter.all, label: Text('All')),
                  ButtonSegment(value: _Filter.unread, label: Text('Unread')),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) =>
                    setState(() => _filter = selection.first),
              ),
            ),
            const SizedBox(height: 12),
            _Summary(total: alerts.length, unread: unread),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const _Message('Everything has been acknowledged.')
            else
              for (final alert in shown) ...[
                _AlertCard(alert: alert, onAcknowledge: () => _acknowledge(alert)),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.unread});

  final int total;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '$total alert${total == 1 ? '' : 's'} · '
      '${unread == 0 ? 'all acknowledged' : '$unread unacknowledged'}',
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onAcknowledge});

  final AlertEvent alert;
  final VoidCallback onAcknowledge;

  IconData get _icon => switch (alert.severity) {
    LabStatus.safe => Icons.info_outline,
    LabStatus.warning => Icons.warning_amber_rounded,
    LabStatus.danger => Icons.dangerous_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: alert.severity.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        alert.severity.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: alert.severity.color,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('MMM d · HH:mm').format(alert.timestamp),
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    alert.message.isEmpty ? 'Unnamed alert' : alert.message,
                    // an acknowledged alert stays readable but steps back
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: alert.acknowledged ? muted : null),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: alert.acknowledged
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 14, color: muted),
                              const SizedBox(width: 4),
                              Text(
                                'Acknowledged',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: muted),
                              ),
                            ],
                          )
                        : TextButton(
                            onPressed: onAcknowledge,
                            child: const Text('Acknowledge'),
                          ),
                  ),
                ],
              ),
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
