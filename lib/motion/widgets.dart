import 'package:flutter/material.dart';
import 'models.dart';

// ═══════════════════════════════════════════════════════════
// OVAL PAINTER
// ═══════════════════════════════════════════════════════════

class OvalPainter extends CustomPainter {
  final Color color;
  final double scale;

  OvalPainter({required this.color, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final oval = OvalUtils.ovalRect(size);

    // Background overlay
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(backgroundPath, Paint()..color = Colors.black.withOpacity(0.7));

    // Glowing Border
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);

    // Apply the pulse scale only to the border
    final center = oval.center;
    final scaledOval = Rect.fromCenter(center: center, width: oval.width * scale, height: oval.height * scale);

    canvas.drawOval(scaledOval, paint);
  }

  @override
  bool shouldRepaint(OvalPainter oldDelegate) => oldDelegate.color != color || oldDelegate.scale != scale;
}

// ═══════════════════════════════════════════════════════════
// STEP PROGRESS INDICATOR
// ═══════════════════════════════════════════════════════════

class StepProgressIndicator extends StatelessWidget {
  final int currentStep;
  final List<StepConfig> steps;

  const StepProgressIndicator({super.key, required this.currentStep, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        steps.length,
        (i) => Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i < currentStep
                  ? Colors.green
                  : i == currentStep
                  ? steps[currentStep].color
                  : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// BLINK INDICATOR
// ═══════════════════════════════════════════════════════════

class BlinkIndicator extends StatelessWidget {
  final int blinkCount;

  const BlinkIndicator({super.key, required this.blinkCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(2, (i) {
        final done = i < blinkCount;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? Colors.green : Colors.white10,
            border: Border.all(color: done ? Colors.green : Colors.white38, width: 2),
          ),
          child: Icon(
            done ? Icons.check : Icons.remove_red_eye_outlined,
            color: done ? Colors.white : Colors.white38,
            size: 20,
          ),
        );
      }),
    );
  }
}
