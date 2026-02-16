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
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black.withOpacity(0.55));

    final oval = OvalUtils.ovalRect(size, scale: scale);
    canvas.drawOval(oval, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawOval(
      oval,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    // Tick marks
    final tickPaint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const tickLen = 12.0;

    canvas.drawLine(Offset(oval.center.dx, oval.top), Offset(oval.center.dx, oval.top + tickLen), tickPaint);
    canvas.drawLine(Offset(oval.center.dx, oval.bottom), Offset(oval.center.dx, oval.bottom - tickLen), tickPaint);
    canvas.drawLine(Offset(oval.left, oval.center.dy), Offset(oval.left + tickLen, oval.center.dy), tickPaint);
    canvas.drawLine(Offset(oval.right, oval.center.dy), Offset(oval.right - tickLen, oval.center.dy), tickPaint);
  }

  @override
  bool shouldRepaint(OvalPainter old) => old.color != color || old.scale != scale;
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
