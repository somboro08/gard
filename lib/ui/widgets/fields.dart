import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Champ de saisie arrondi, grand et lisible (style WhatsApp).
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.hint,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.suffix,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.obscureText = false,
    this.big = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;
  final bool obscureText;

  /// Grande police (plaque, code).
  final bool big;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
        );

    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      maxLines: maxLines,
      autofocus: autofocus,
      obscureText: obscureText,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      cursorColor: p.gold,
      style: TextStyle(
        fontSize: big ? 25 : 18.5,
        fontWeight: big ? FontWeight.w700 : FontWeight.w500,
        letterSpacing: big ? 1.5 : 0,
        color: p.text,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        labelStyle: TextStyle(fontSize: 17, color: p.textSoft),
        floatingLabelStyle: TextStyle(fontSize: 16, color: p.goldText, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(
          fontSize: big ? 22 : 17,
          color: p.textSoft.withOpacity(0.6),
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
        prefixIcon: icon == null ? null : Icon(icon, color: p.textSoft, size: 24),
        suffixIcon: suffix,
        filled: true,
        fillColor: p.field,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: border(p.field, 0),
        enabledBorder: border(p.field, 0),
        focusedBorder: border(p.gold, 2),
        errorBorder: border(p.danger, 1.5),
        focusedErrorBorder: border(p.danger, 2),
        errorStyle: TextStyle(fontSize: 14, color: p.danger),
      ),
    );
  }
}

/// Force les majuscules pendant la frappe (plaques).
final TextInputFormatter upperCaseFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
);
