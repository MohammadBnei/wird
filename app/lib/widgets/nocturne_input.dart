import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

/// A text field on the Nocturne surface, with the optional `.field` label.
class NocturneInput extends StatefulWidget {
  const NocturneInput({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.focusNode,
    this.multiline = false,
    this.maxLength,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool multiline;

  /// The most that can be typed. Set it wherever something downstream refuses
  /// a longer one, so the limit is met while the reader is still writing
  /// rather than in an answer nobody reads.
  ///
  /// Material's counter under the field is turned off: it prints "0/4,000"
  /// over an empty box, which is a number in a design that shows the reader
  /// no numbers. What the limit is, and when to say it, is the screen's.
  final int? maxLength;

  @override
  State<NocturneInput> createState() => _NocturneInputState();
}

class _NocturneInputState extends State<NocturneInput> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final border = _focused
        ? n.accent
        : _hovered
        ? n.textAt(0.45)
        : n.divider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(fontSize: 12, height: 1.2, color: n.textAt(0.7)),
          ),
          const SizedBox(height: 5),
        ],
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            constraints: BoxConstraints(minHeight: widget.multiline ? 90 : 36),
            decoration: BoxDecoration(
              color: n.surface,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(n.radius('md')),
            ),
            child: Focus(
              onFocusChange: (v) => setState(() => _focused = v),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                onChanged: widget.onChanged,
                maxLines: widget.multiline ? null : 1,
                maxLength: widget.maxLength,
                cursorColor: n.accent,
                style: TextStyle(fontSize: 14, height: 1.2, color: n.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: TextStyle(fontSize: 14, color: n.textAt(0.45)),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
