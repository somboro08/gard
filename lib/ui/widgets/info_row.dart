import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Carte arrondie regroupant des lignes d'information séparées par un filet.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(Divider(height: 1, color: p.divider));
      items.add(children[i]);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22)),
      child: Column(children: items),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 24, color: p.textSoft),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.tt.bodySmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: context.tt.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? p.text,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Bandeau d'alerte / d'information.
class Banner2 extends StatelessWidget {
  const Banner2({
    super.key,
    required this.icon,
    required this.text,
    required this.fg,
    required this.bg,
  });

  final IconData icon;
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: context.tt.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
