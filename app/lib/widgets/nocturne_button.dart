import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

enum NocturneButtonVariant { primary, secondary, ghost, icon }

/// An action. The primary is an accent outline on transparent, never a fill.
class NocturneButton extends StatefulWidget {
  const NocturneButton({
    super.key,
    required this.child,
    this.onPressed,
    this.variant = NocturneButtonVariant.secondary,
    this.block = false,
    this.focusNode,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final NocturneButtonVariant variant;

  /// `.btn-block`: full width with a space-2 lead-in. Orthogonal to the
  /// variant in the CSS, so it stays a flag here too.
  final bool block;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<NocturneButton> createState() => _NocturneButtonState();
}

class _NocturneButtonState extends State<NocturneButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final variant = widget.variant;
    final accented =
        variant == NocturneButtonVariant.primary ||
        variant == NocturneButtonVariant.ghost ||
        variant == NocturneButtonVariant.icon;

    final tint = switch (variant) {
      NocturneButtonVariant.primary => _pressed ? 0.22 : 0.12,
      NocturneButtonVariant.ghost || NocturneButtonVariant.icon =>
        _pressed ? 0.18 : 0.10,
      NocturneButtonVariant.secondary => _pressed ? 0.14 : 0.07,
    };
    final tintSource = accented ? n.accent : n.text;
    final fill = _enabled && (_hovered || _pressed)
        ? tintSource.withValues(alpha: tint)
        : Colors.transparent;

    final border = switch (variant) {
      NocturneButtonVariant.primary => n.accent,
      NocturneButtonVariant.secondary => n.divider,
      _ => Colors.transparent,
    };

    final horizontal = switch (variant) {
      NocturneButtonVariant.ghost => n.space('1'),
      NocturneButtonVariant.icon => 0.0,
      _ => n.space('3') * 1.2,
    };
    final isIcon = variant == NocturneButtonVariant.icon;

    Widget button = Container(
      width: isIcon ? 36 : null,
      height: isIcon ? 36 : null,
      padding: isIcon
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(vertical: n.space('2'), horizontal: horizontal),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(n.radius('md')),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: Nocturne.headingFamily,
          fontVariations: Nocturne.headingVariations,
          fontSize: 14,
          height: 1.2,
          color: accented ? n.accent : n.text,
        ),
        child: IconTheme.merge(
          data: IconThemeData(
            size: 18,
            color: accented ? n.accent : n.text,
          ),
          child: Center(widthFactor: 1, heightFactor: 1, child: widget.child),
        ),
      ),
    );

    if (_focused) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: n.accent, width: 2),
                  borderRadius: BorderRadius.circular(n.radius('md') + 4),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!_enabled) button = Opacity(opacity: 0.45, child: button);
    if (widget.block) {
      button = Padding(
        padding: EdgeInsets.only(top: n.space('2')),
        child: SizedBox(width: double.infinity, child: button),
      );
    }

    return FocusableActionDetector(
      enabled: _enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: _enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPressed?.call(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: Semantics(button: true, enabled: _enabled, child: button),
      ),
    );
  }
}
