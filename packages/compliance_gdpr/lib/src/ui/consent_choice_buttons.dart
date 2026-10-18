import 'package:flutter/material.dart';

/// "Accept all" and "Reject all" buttons with equal visual weight.
///
/// Both buttons always use the same widget type, the same [style] and the
/// same width, so neither choice is visually favoured. They sit side by side
/// when there is room and stack vertically on narrow screens or with large
/// text.
class ConsentChoiceButtons extends StatelessWidget {
  /// Creates the buttons.
  const ConsentChoiceButtons({
    required this.acceptLabel,
    required this.rejectLabel,
    required this.onAccept,
    required this.onReject,
    this.style,
    super.key,
  });

  /// Label of the accept button.
  final String acceptLabel;

  /// Label of the reject button.
  final String rejectLabel;

  /// Called when accept is pressed. `null` disables both buttons.
  final VoidCallback? onAccept;

  /// Called when reject is pressed. `null` disables both buttons.
  final VoidCallback? onReject;

  /// Style applied to both buttons.
  final ButtonStyle? style;

  /// Minimum width per button before the layout switches to a column.
  static const double minButtonWidth = 140;

  @override
  Widget build(BuildContext context) {
    final enabled = onAccept != null && onReject != null;
    Widget button(String label, VoidCallback? onPressed, Key key) =>
        FilledButton.tonal(
          key: key,
          style: style,
          onPressed: enabled ? onPressed : null,
          child: Text(label, textAlign: TextAlign.center),
        );
    final reject = button(
      rejectLabel,
      onReject,
      const ValueKey('consent_reject_all'),
    );
    final accept = button(
      acceptLabel,
      onAccept,
      const ValueKey('consent_accept_all'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth < minButtonWidth * 2 * scale + 12;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [reject, const SizedBox(height: 8), accept],
          );
        }
        return Row(
          children: [
            Expanded(child: reject),
            const SizedBox(width: 12),
            Expanded(child: accept),
          ],
        );
      },
    );
  }
}
