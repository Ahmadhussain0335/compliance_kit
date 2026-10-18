import 'package:flutter/material.dart';

import '../consent/consent_manager.dart';
import '../consent/consent_state.dart';
import 'consent_strings.dart';

/// A screen listing every purpose with a switch.
///
/// Toggling a switch grants or withdraws consent immediately: withdrawing
/// is one action, just like granting. Required purposes are shown as always
/// active without a switch.
///
/// While consent is still needed (first launch or policy change), a
/// "Confirm choices" button stores the current switch positions, so
/// purposes the user left off are recorded as denied.
///
/// If storing a change fails, a snack bar with `ConsentStrings.saveFailed`
/// is shown and [onError] is called.
class PrivacySettingsScreen extends StatefulWidget {
  /// Creates the screen.
  const PrivacySettingsScreen({
    required this.manager,
    this.strings = const ConsentStrings(),
    this.onError,
    super.key,
  });

  /// The consent manager. Must be initialized.
  final ConsentManager manager;

  /// User-facing strings.
  final ConsentStrings strings;

  /// Called when storing a change failed.
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e, st) {
      widget.onError?.call(e, st);
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(widget.strings.saveFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final manager = widget.manager;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: StreamBuilder<ConsentState>(
        stream: manager.changes,
        initialData: manager.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? manager.state;
          final required = [
            for (final p in manager.policy.purposes)
              if (p.required) p,
          ];
          final optional = manager.policy.optionalPurposes;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(strings.settingsIntro),
              ),
              if (state.policyChangedNotice)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    strings.policyChangedNotice,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
              if (optional.isNotEmpty)
                _SectionHeader(strings.optionalSectionTitle),
              for (final purpose in optional)
                SwitchListTile(
                  key: ValueKey('consent_switch_${purpose.id}'),
                  title: Text(purpose.title),
                  subtitle: Text(purpose.description),
                  value: state.isGranted(purpose.id),
                  onChanged: _busy
                      ? null
                      : (value) => _run(
                          () => value
                              ? manager.grant(purpose.id)
                              : manager.withdraw(purpose.id),
                        ),
                ),
              if (required.isNotEmpty)
                _SectionHeader(strings.requiredSectionTitle),
              for (final purpose in required)
                ListTile(
                  key: ValueKey('consent_required_${purpose.id}'),
                  title: Text(purpose.title),
                  subtitle: Text(purpose.description),
                  trailing: Text(
                    strings.alwaysActive,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              if (state.needsConsent)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    key: const ValueKey('consent_confirm_choices'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await manager.update({
                              for (final p in optional)
                                p.id: state.isGranted(p.id),
                            });
                            if (context.mounted) {
                              await Navigator.of(context).maybePop();
                            }
                          }),
                    child: Text(strings.confirmChoices),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}
