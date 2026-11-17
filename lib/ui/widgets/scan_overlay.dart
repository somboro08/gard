import 'package:flutter/material.dart';

/// Cadre de visée : zone assombrie autour d'une fenêtre arrondie + 4 coins colorés.
class ScanOverlay extends StatelessWidget {
  const ScanOverlay({
    super.key,
    required this.aspect,
    required this.color,
    this.widthFactor = 0.78,
    this.centerY = 0.42,
  });

  /// largeur / hauteur de la fenêtre (1 = carré, 3 = plaque).
  final double aspect;
  final Color color;
  final double widthFactor;

  /// Position verticale du centre (0 → haut, 1 → bas).
  final double centerY;

  /// Rectangle de visée pour une taille donnée (utile pour placer des textes).
  Rect windowFor(Size size) {
    final w = size.width * widthFactor;
    final h = w / aspect;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * centerY),
      width: w,
      height: h,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return IgnorePointer(
          child: CustomPaint(
            size: size,
            painter: _OverlayPainter(rect: windowFor(size), color: color),
          ),
        );
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(26);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(dim, Paint()..color = Colors.black.withOpacity(0.58));

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const len = 36.0;
    const r = 26.0;

    // Haut-gauche
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + len)
        ..lineTo(rect.left, rect.top + r)
        ..arcToPoint(Offset(rect.left + r, rect.top), radius: radius)
        ..lineTo(rect.left + len, rect.top),
      stroke,
    );
    // Haut-droite
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.top)
        ..lineTo(rect.right - r, rect.top)
        ..arcToPoint(Offset(rect.right, rect.top + r), radius: radius)
        ..lineTo(rect.right, rect.top + len),
      stroke,
    );
    // Bas-droite
    canvas.drawPath(
      Path()
        ..moveTo(rect.right, rect.bottom - len)
        ..lineTo(rect.right, rect.bottom - r)
        ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: radius)
        ..lineTo(rect.right - len, rect.bottom),
      stroke,
    );
    // Bas-gauche
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + len, rect.bottom)
        ..lineTo(rect.left + r, rect.bottom)
        ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: radius)
        ..lineTo(rect.left, rect.bottom - len),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.rect != rect || old.color != color;
}
