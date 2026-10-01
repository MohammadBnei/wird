import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

/// A segmented choice: one option selected, the rest plain.
class NocturneSegmented extends StatefulWidget {
  const NocturneSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  State<NocturneSegmented> createState() => _NocturneSegmentedState();
}

class _NocturneSegmentedState extends State<NocturneSegmented> {
  int? _hovered;
  int? _focused;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: n.divider),
        borderRadius: BorderRadius.circular(n.radius('md')),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, option) in widget.options.indexed) ...[
            if (i > 0)
              Container(width: 1, height: 30, color: n.divider),
            FocusableActionDetector(
              mouseCursor: SystemMouseCursors.click,
              onShowHoverHighlight: (v) =>
                  setState(() => _hovered = v ? i : null),
              onShowFocusHighlight: (v) =>
                  setState(() => _focused = v ? i : null),
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) => widget.onChanged(i),
                ),
              },
              child: GestureDetector(
                onTap: () => widget.onChanged(i),
                child: Semantics(
                  selected: i == widget.selected,
                  button: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: i != widget.selected && _hovered == i
                          ? n.text.withValues(alpha: 0.07)
                          : null,
                      // Selection and focus are drawn inside the control, as
                      // the CSS does with an inset ring and a -2px outline.
                      border: Border.all(
                        color: _focused == i
                            ? n.accent
                            : i == widget.selected
                            ? n.accent
                            : Colors.transparent,
                        width: _focused == i ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: i == widget.selected ? n.accent : n.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
