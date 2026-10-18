import 'package:flutter/material.dart';

import '../consent/consent_manager.dart';
import '../consent/consent_state.dart';
import 'consent_choice_buttons.dart';
import 'consent_strings.dart';
import 'privacy_settings_screen.dart';

/// The content of the consent prompt: title, explanation, the list of
/// optional purposes, equal-weight accept and reject buttons, and a button
/// to choose per purpose.
///
/// Usually shown with [showConsentDialog] or [showConsentBottomSheet].
/// [onDone] is called after the user made a choice.
class ConsentPrompt extends StatefulWidget {
  /// Creates the prompt.
  const ConsentPrompt({
    required this.manager,
    this.strings = const ConsentStrings(),
    this.buttonStyle,
    this.onDone,
    super.key,
  });

  /// The consent manager. Must be initialized.
  final ConsentManager manager;

  /// User-facing strings.
  final ConsentStrings strings;

  /// Style applied equally to the accept and reject buttons.
  final ButtonStyle? buttonStyle;

  /// Called after the user accepted, rejected or confirmed choices.
  final VoidCallback? onDone;

  @override
  State<ConsentPrompt> createState() => _ConsentPromptState();
}

class _ConsentPromptState extends State<ConsentPrompt> {
  bool _busy = false;

  Future<void> _decide(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onDone?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _customize() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivacySettingsScreen(
          manager: widget.manager,
          strings: widget.strings,
        ),
      ),
    );
    if (mounted && !widget.manager.state.needsConsent) {
      widget.onDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.strings;
    final manager = widget.manager;
    final policyChanged = manager.state.status == ConsentStatus.policyChanged;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(strings.promptTitle, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          if (policyChanged) ...[
            Text(
              strings.policyChangedNotice,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(strings.promptBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          for (final purpose in manager.policy.optionalPurposes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(purpose.title, style: theme.textTheme.titleSmall),
                    Text(purpose.description, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          ConsentChoiceButtons(
            acceptLabel: strings.acceptAll,
            rejectLabel: strings.rejectAll,
            style: widget.buttonStyle,
            onAccept: _busy ? null : () => _decide(manager.acceptAll),
            onReject: _busy ? null : () => _decide(manager.rejectAll),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('consent_customize'),
            onPressed: _busy ? null : _customize,
            child: Text(strings.customize, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

/// Shows the [ConsentPrompt] in a dialog and returns the state after the
/// user decided.
///
/// The dialog cannot be dismissed by tapping outside, because closing it
/// without a choice would leave consent undecided. Rejecting is one tap,
/// exactly like accepting.
Future<ConsentState> showConsentDialog(
  BuildContext context, {
  required ConsentManager manager,
  ConsentStrings strings = const ConsentStrings(),
  ButtonStyle? buttonStyle,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ConsentPrompt(
          manager: manager,
          strings: strings,
          buttonStyle: buttonStyle,
          onDone: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
  return manager.state;
}

/// Shows the [ConsentPrompt] in a modal bottom sheet and returns the state
/// after the user decided. See [showConsentDialog].
Future<ConsentState> showConsentBottomSheet(
  BuildContext context, {
  required ConsentManager manager,
  ConsentStrings strings = const ConsentStrings(),
  ButtonStyle? buttonStyle,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => ConsentPrompt(
      manager: manager,
      strings: strings,
      buttonStyle: buttonStyle,
      onDone: () => Navigator.of(sheetContext).pop(),
    ),
  );
  return manager.state;
}
