import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// Unified text input (SEDS §2.1): optional label, leading glyph, focus ring,
/// inline error, and a password reveal toggle.
class SeTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final bool enabled;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final String? errorText;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;

  const SeTextField({
    super.key,
    this.controller,
    this.label,
    this.hint = '',
    this.icon,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.errorText,
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.autofocus = false,
  });

  @override
  State<SeTextField> createState() => _SeTextFieldState();
}

class _SeTextFieldState extends State<SeTextField> {
  late bool _hidden = widget.obscure;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = widget.errorText != null;
    final focused = _focus.hasFocus;
    final borderColor = hasError
        ? SeColors.danger
        : focused
            ? SeColors.red500
            : SeColors.ink200;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: SeType.label.copyWith(color: SeColors.ink700)),
          const SizedBox(height: 7),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: widget.enabled ? scheme.surface : SeColors.surface50,
            borderRadius: SeRadius.inputRadius,
            border: Border.all(
              color: borderColor,
              width: focused || hasError ? 2 : 1.5,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: SeColors.red500.withValues(alpha: 0.10),
                      blurRadius: 0,
                      spreadRadius: 3,
                    )
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: widget.maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (widget.icon != null)
                Padding(
                  padding: EdgeInsets.only(
                      left: 14, right: 10, top: widget.maxLines > 1 ? 14 : 0),
                  child: Icon(widget.icon,
                      size: 20,
                      color: focused ? SeColors.red500 : SeColors.ink400),
                ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  obscureText: _hidden,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  minLines: widget.minLines,
                  maxLines: widget.obscure ? 1 : widget.maxLines,
                  autofocus: widget.autofocus,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  inputFormatters: widget.inputFormatters,
                  style: SeType.body.copyWith(color: SeColors.ink900),
                  cursorColor: SeColors.red500,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.only(
                      left: widget.icon == null ? 14 : 0,
                      right: 14,
                      top: 14,
                      bottom: 14,
                    ),
                    hintText: widget.hint,
                    hintStyle: SeType.body.copyWith(color: SeColors.ink400),
                  ),
                ),
              ),
              if (widget.obscure)
                GestureDetector(
                  onTap: () => setState(() => _hidden = !_hidden),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, left: 4),
                    child: Icon(_hidden ? SeIcons.eye : SeIcons.eyeSlash,
                        size: 20, color: SeColors.ink400),
                  ),
                ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(SeIcons.warningCircle, size: 14, color: SeColors.danger),
              const SizedBox(width: 5),
              Expanded(
                child: Text(widget.errorText!,
                    style: SeType.bodyS.copyWith(color: SeColors.danger)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
