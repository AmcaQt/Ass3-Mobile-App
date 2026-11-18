import 'package:flutter/material.dart';

import '../services/db_service.dart';
import '../theme/app_theme.dart';

// no Scaffold: AppShell provides it
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key, this.db});

  /// Injectable for tests; defaults to a service on FirebaseDatabase.instance.
  final DbService? db;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late final DbService _db = widget.db ?? DbService();

  // Held in fields so a rebuild does not resubscribe the RTDB listeners.
  late final Stream<Map<String, bool>> _outputs = _db.watchOutputs();
  late final Stream<String> _mode = _db.watchMode();
  late final Stream<bool> _online = _db.watchDeviceOnline();

  /// Switch positions we have asked for but have not seen confirmed yet, so
  /// the toggle moves under the thumb instead of waiting for the next push.
  final Map<String, bool> _pending = {};

  Future<void> _guard(Future<void> Function() write, String label) async {
    try {
      await write();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change $label.\n$error')),
      );
    }
  }

  /// Flipping any switch takes the outputs over, so there is no mode to pick
  /// first: the firmware only honours this node while it is in manual, and
  /// writing the mode alongside the value saves the user that step.
  Future<void> _setOutput(_Output output, bool on) async {
    setState(() => _pending[output.name] = on);
    try {
      await _db.setMode('manual');
      await _db.setOutput(output.name, on);
    } catch (error) {
      if (!mounted) return;
      // the write never landed, so stop claiming that it did
      setState(() => _pending.remove(output.name));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not change ${output.label.toLowerCase()}.\n$error',
          ),
        ),
      );
    }
  }

  /// Gives the safety logic its outputs back.
  Future<void> _handBack() {
    setState(_pending.clear);
    return _guard(() => _db.setMode('auto'), 'the mode');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _mode,
      builder: (context, modeSnapshot) {
        return StreamBuilder<Map<String, bool>>(
          stream: _outputs,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _Message(
                'Could not read the controls.\n${snapshot.error}',
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final outputs = snapshot.data ?? const <String, bool>{};
            final isManual = modeSnapshot.data == 'manual';

            // Forget any request the device has now confirmed. Safe to do in
            // build: it only drops entries that already agree with [outputs],
            // so it cannot change what this frame renders.
            _pending.removeWhere((name, want) => outputs[name] == want);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _OfflineNotice(online: _online),
                _OverrideCard(
                  isManual: isManual,
                  onHandBack: isManual ? _handBack : null,
                ),
                const SizedBox(height: 12),
                for (final output in _boardOutputs) ...[
                  _SwitchCard(
                    label: output.label,
                    icon: output.icon,
                    color: output.color,
                    value:
                        _pending[output.name] ?? outputs[output.name] ?? false,
                    subtitle: isManual ? _heldText : output.auto,
                    onChanged: (on) => _setOutput(output, on),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

const _heldText = 'You are driving this output';

/// The four outputs on the board, in the order they sit on the rail.
const _boardOutputs = [
  _Output('green', 'Green LED', Icons.circle, AppColors.safe,
      'Lit by the device while the lab is safe'),
  _Output('yellow', 'Yellow LED', Icons.circle, AppColors.warning,
      'Lit by the device on a warning'),
  _Output('white', 'White LED', Icons.circle, Color(0xFFBFC7CE),
      'Strobed by the device in danger'),
  _Output('buzzer', 'Buzzer', Icons.volume_up_outlined, AppColors.danger,
      'Sounded by the device in danger, through the relay'),
];

class _Output {
  const _Output(this.name, this.label, this.icon, this.color, this.auto);

  final String name;
  final String label;
  final IconData icon;
  final Color color;

  /// What drives this output while the device still owns it.
  final String auto;
}

/// Says who is driving the outputs and hands them back. There is no mode to
/// choose: flipping a switch takes over on its own.
class _OverrideCard extends StatelessWidget {
  const _OverrideCard({required this.isManual, required this.onHandBack});

  final bool isManual;
  final VoidCallback? onHandBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isManual ? Icons.pan_tool_outlined : Icons.memory_outlined,
                  size: 18,
                  color: isManual ? AppColors.warning : muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isManual
                        ? 'You are driving the outputs'
                        : 'The device is driving the outputs',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isManual
                  ? 'The safety logic will not touch the LEDs or the buzzer, '
                        'not even on a danger, until you hand them back.'
                  : 'Flip any switch below to take over. The board picks up '
                        'changes within a couple of seconds.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            if (onHandBack != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onHandBack,
                  icon: const Icon(Icons.undo_outlined, size: 18),
                  label: const Text('Hand back to the device'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.subtitle,
    required this.onChanged,
    this.color,
  });

  final String label;
  final IconData icon;
  final bool value;
  final String subtitle;
  final ValueChanged<bool>? onChanged;

  /// Tints the icon while the output is on, so the card matches the board.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon, color: value ? color : null),
        title: Text(label, style: theme.textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.online});

  final Stream<bool> online;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: online,
      builder: (context, snapshot) {
        // nothing to say while the state is unknown, or when the device is up
        if (snapshot.data ?? true) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Device offline. Changes are stored and applied when it '
                  'reconnects.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
