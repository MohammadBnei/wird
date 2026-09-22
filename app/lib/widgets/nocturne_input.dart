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
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool multiline;

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
                cursorColor: n.accent,
                style: TextStyle(fontSize: 14, height: 1.2, color: n.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: TextStyle(fontSize: 14, color: n.textAt(0.45)),
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
