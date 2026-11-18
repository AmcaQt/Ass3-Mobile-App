import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';

/// The five threshold keys under /lab/thresholds, with their bounds.
const _fields = [
  _Field('tempWarn', 'Temperature warning', '°C', 0, 100),
  _Field('tempDanger', 'Temperature danger', '°C', 0, 100),
  _Field('gasWarn', 'Gas warning', '', 0, 4095),
  _Field('gasDanger', 'Gas danger', '', 0, 4095),
  // unpaired: anything closer than this counts as a person at the bench
  _Field('presenceCm', 'Presence distance', 'cm', 0, 400),
];

class _Field {
  const _Field(this.key, this.label, this.unit, this.min, this.max);

  final String key;
  final String label;
  final String unit;
  final num min;
  final num max;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.db, this.auth});

  /// Injectable for tests; both default to services on the Firebase singletons.
  final DbService? db;
  final AuthService? auth;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final DbService _db = widget.db ?? DbService();
  late final AuthService _auth = widget.auth ?? AuthService();

  // Held in fields so a rebuild does not resubscribe the RTDB listeners.
  late final Stream<Map<String, num>> _thresholds = _db.watchThresholds();
  late final Stream<bool> _online = _db.watchDeviceOnline();

  final _formKey = GlobalKey<FormState>();
  final _controllers = {
    for (final field in _fields) field.key: TextEditingController(),
  };

  /// What the database last confirmed, so saving can skip untouched keys.
  Map<String, num> _saved = const {};
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Fills the boxes from the first emission only. Seeding on every emission
  /// would rewrite the field under the cursor each time RTDB echoes a value.
  void _seed(Map<String, num> values) {
    _saved = values;
    if (_seeded) return;
    _seeded = true;
    for (final field in _fields) {
      final value = values[field.key];
      if (value != null) _controllers[field.key]!.text = _format(value);
    }
  }

  num? _parsed(String key) => num.tryParse(_controllers[key]!.text.trim());

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final changes = {
      for (final field in _fields)
        if (_parsed(field.key) case final value?)
          if (value != _saved[field.key]) field.key: value,
    };
    if (changes.isEmpty) {
      _toast('No changes to save.');
      return;
    }

    setState(() => _saving = true);
    try {
      // one write per key: /lab/thresholds has no other children to clobber
      for (final change in changes.entries) {
        await _db.setThreshold(change.key, change.value);
      }
      _toast('Saved ${changes.length} threshold${changes.length == 1 ? '' : 's'}.');
    } catch (error) {
      _toast('Could not save.\n$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      // this screen sits on top of the shell, so it has to leave with it
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _toast('Could not sign out.\n$error');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('Thresholds'),
          _ThresholdsCard(
            stream: _thresholds,
            formKey: _formKey,
            controllers: _controllers,
            saving: _saving,
            onSeed: _seed,
            onSave: _save,
            otherValue: _parsed,
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Device'),
          _DeviceCard(online: _online),
          const SizedBox(height: 24),
          const _SectionHeader('Account'),
          _AccountCard(auth: _auth, onSignOut: _signOut),
          const SizedBox(height: 24),
          const _SectionHeader('About'),
          const _AboutCard(),
        ],
      ),
    );
  }
}

class _ThresholdsCard extends StatelessWidget {
  const _ThresholdsCard({
    required this.stream,
    required this.formKey,
    required this.controllers,
    required this.saving,
    required this.onSeed,
    required this.onSave,
    required this.otherValue,
  });

  final Stream<Map<String, num>> stream;
  final GlobalKey<FormState> formKey;
  final Map<String, TextEditingController> controllers;
  final bool saving;
  final ValueChanged<Map<String, num>> onSeed;
  final VoidCallback onSave;
  final num? Function(String key) otherValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<Map<String, num>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _CardText('Could not read the thresholds.\n${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        onSeed(snapshot.data ?? const {});

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'The device compares every reading against these, so a '
                    'warning level must sit below its danger level. Presence '
                    'distance is how close the ultrasonic sensor counts as '
                    'someone at the bench.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final field in _fields) ...[
                    TextFormField(
                      controller: controllers[field.key],
                      enabled: !saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: field.label,
                        border: const OutlineInputBorder(),
                        suffixText: field.unit.isEmpty ? null : field.unit,
                      ),
                      validator: (value) => _validate(field, value),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 4),
                  FilledButton(
                    onPressed: saving ? null : onSave,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save changes'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _validate(_Field field, String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 'Enter a value.';
    final value = num.tryParse(text);
    if (value == null) return 'Numbers only.';
    if (value < field.min || value > field.max) {
      return 'Between ${_format(field.min)} and ${_format(field.max)}.';
    }
    // a warn/danger pair has to stay ordered, or the gauge bands invert.
    // keys without a partner, like presenceCm, skip the check entirely.
    if (field.key.endsWith('Warn')) {
      final danger = otherValue(field.key.replaceAll('Warn', 'Danger'));
      if (danger != null && value >= danger) {
        return 'Must be below the danger level.';
      }
    } else if (field.key.endsWith('Danger')) {
      final warn = otherValue(field.key.replaceAll('Danger', 'Warn'));
      if (warn != null && value <= warn) {
        return 'Must be above the warning level.';
      }
    }
    return null;
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.online});

  final Stream<bool> online;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      child: StreamBuilder<bool>(
        stream: online,
        builder: (context, snapshot) {
          final isOnline = snapshot.data ?? false;
          return ListTile(
            leading: Icon(
              isOnline ? Icons.sensors : Icons.sensors_off,
              color: isOnline ? AppColors.safe : muted,
            ),
            title: Text(isOnline ? 'Device online' : 'Device offline'),
            subtitle: Text(
              isOnline
                  ? 'Reporting to /lab/live.'
                  : 'No heartbeat at /lab/device/online.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          );
        },
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.auth, required this.onSignOut});

  final AuthService auth;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = auth.currentUser;
    final isGuest = user?.isAnonymous ?? false;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(isGuest ? Icons.person_outline : Icons.badge_outlined),
            title: Text(isGuest ? 'Guest' : user?.email ?? 'Signed in'),
            subtitle: Text(
              isGuest
                  ? 'Anonymous session; the rules still see a token.'
                  : 'Signed in with email and password.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout_outlined),
            title: const Text('Sign out'),
            onTap: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    // straight from DbService, so this list cannot drift from the real paths
    const paths = [
      DbService.livePath,
      DbService.actuatorsPath,
      DbService.thresholdsPath,
      DbService.devicePath,
      DbService.historyPath,
      DbService.alertsPath,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lab Safety Monitor', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'DFI20443 Smart Lab Safety Monitor · version 1.0.0',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            Text(
              'DATABASE PATHS',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: muted, letterSpacing: 1),
            ),
            const SizedBox(height: 6),
            for (final path in paths)
              Text(
                '/$path',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _CardText extends StatelessWidget {
  const _CardText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Whole numbers lose their trailing zero, so 32 shows as "32", not "32.0".
String _format(num value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toString();
