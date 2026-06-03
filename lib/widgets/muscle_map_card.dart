import 'package:flutter/material.dart';
import 'package:vo2_flutter/exercise_catalog.dart';

class MuscleMapCard extends StatelessWidget {
  const MuscleMapCard({super.key, required this.highlighted, this.selected});

  final Set<MuscleGroup> highlighted;
  final MuscleGroup? selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 248,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        painter: _MuscleMapPainter(
          highlighted: highlighted,
          selected: selected,
        ),
      ),
    );
  }
}

class _MuscleMapPainter extends CustomPainter {
  const _MuscleMapPainter({required this.highlighted, this.selected});

  final Set<MuscleGroup> highlighted;
  final MuscleGroup? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect frontRect = Rect.fromLTWH(
      0,
      0,
      size.width / 2 - 10,
      size.height,
    );
    final Rect backRect = Rect.fromLTWH(
      size.width / 2 + 10,
      0,
      size.width / 2 - 10,
      size.height,
    );

    _drawFigure(
      canvas,
      frontRect,
      label: 'Front',
      regionColor: (MuscleGroup group) => _frontRegionColor(group),
    );
    _drawFigure(
      canvas,
      backRect,
      label: 'Back',
      regionColor: (MuscleGroup group) => _backRegionColor(group),
    );
  }

  Color _frontRegionColor(MuscleGroup group) {
    if (selected != null && group != selected) {
      return const Color(0xFFCBD5E1).withValues(alpha: 0.18);
    }
    if (!highlighted.contains(group)) {
      return Colors.transparent;
    }
    return const Color(0xFFFB7185).withValues(alpha: 0.82);
  }

  Color _backRegionColor(MuscleGroup group) {
    if (selected != null && group != selected) {
      return const Color(0xFFCBD5E1).withValues(alpha: 0.18);
    }
    if (!highlighted.contains(group)) {
      return Colors.transparent;
    }
    return const Color(0xFF2DD4BF).withValues(alpha: 0.82);
  }

  void _drawFigure(
    Canvas canvas,
    Rect rect, {
    required String label,
    required Color Function(MuscleGroup group) regionColor,
  }) {
    final Paint base = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final double centerX = rect.left + rect.width / 2;
    final double top = rect.top + 18;

    canvas.drawCircle(Offset(centerX, top + 16), 14, base);
    canvas.drawCircle(Offset(centerX, top + 16), 14, stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, rect.top + rect.height * 0.40),
          width: rect.width * 0.26,
          height: rect.height * 0.28,
        ),
        const Radius.circular(20),
      ),
      base,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, rect.top + rect.height * 0.40),
          width: rect.width * 0.26,
          height: rect.height * 0.28,
        ),
        const Radius.circular(20),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            centerX - rect.width * 0.17,
            rect.top + rect.height * 0.40,
          ),
          width: rect.width * 0.10,
          height: rect.height * 0.26,
        ),
        const Radius.circular(18),
      ),
      base,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            centerX + rect.width * 0.17,
            rect.top + rect.height * 0.40,
          ),
          width: rect.width * 0.10,
          height: rect.height * 0.26,
        ),
        const Radius.circular(18),
      ),
      base,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            centerX - rect.width * 0.08,
            rect.top + rect.height * 0.73,
          ),
          width: rect.width * 0.11,
          height: rect.height * 0.30,
        ),
        const Radius.circular(18),
      ),
      base,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            centerX + rect.width * 0.08,
            rect.top + rect.height * 0.73,
          ),
          width: rect.width * 0.11,
          height: rect.height * 0.30,
        ),
        const Radius.circular(18),
      ),
      base,
    );

    void fillRegion(Rect region, MuscleGroup group) {
      final Color color = regionColor(group);
      if (color == Colors.transparent) {
        return;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(region, const Radius.circular(14)),
        Paint()..color = color,
      );
    }

    fillRegion(
      Rect.fromCenter(
        center: Offset(centerX, rect.top + rect.height * 0.34),
        width: rect.width * 0.18,
        height: rect.height * 0.10,
      ),
      MuscleGroup.chest,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(centerX, rect.top + rect.height * 0.34),
        width: rect.width * 0.18,
        height: rect.height * 0.18,
      ),
      MuscleGroup.back,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX - rect.width * 0.12,
          rect.top + rect.height * 0.29,
        ),
        width: rect.width * 0.08,
        height: rect.height * 0.08,
      ),
      MuscleGroup.shoulders,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX + rect.width * 0.12,
          rect.top + rect.height * 0.29,
        ),
        width: rect.width * 0.08,
        height: rect.height * 0.08,
      ),
      MuscleGroup.shoulders,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX - rect.width * 0.17,
          rect.top + rect.height * 0.40,
        ),
        width: rect.width * 0.07,
        height: rect.height * 0.10,
      ),
      MuscleGroup.biceps,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX + rect.width * 0.17,
          rect.top + rect.height * 0.40,
        ),
        width: rect.width * 0.07,
        height: rect.height * 0.10,
      ),
      MuscleGroup.biceps,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX - rect.width * 0.17,
          rect.top + rect.height * 0.47,
        ),
        width: rect.width * 0.07,
        height: rect.height * 0.10,
      ),
      MuscleGroup.triceps,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX + rect.width * 0.17,
          rect.top + rect.height * 0.47,
        ),
        width: rect.width * 0.07,
        height: rect.height * 0.10,
      ),
      MuscleGroup.triceps,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(centerX, rect.top + rect.height * 0.50),
        width: rect.width * 0.12,
        height: rect.height * 0.12,
      ),
      MuscleGroup.core,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX - rect.width * 0.08,
          rect.top + rect.height * 0.68,
        ),
        width: rect.width * 0.10,
        height: rect.height * 0.16,
      ),
      MuscleGroup.quads,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX + rect.width * 0.08,
          rect.top + rect.height * 0.68,
        ),
        width: rect.width * 0.10,
        height: rect.height * 0.16,
      ),
      MuscleGroup.quads,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(centerX, rect.top + rect.height * 0.57),
        width: rect.width * 0.16,
        height: rect.height * 0.10,
      ),
      MuscleGroup.glutes,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX - rect.width * 0.08,
          rect.top + rect.height * 0.69,
        ),
        width: rect.width * 0.10,
        height: rect.height * 0.12,
      ),
      MuscleGroup.hamstrings,
    );
    fillRegion(
      Rect.fromCenter(
        center: Offset(
          centerX + rect.width * 0.08,
          rect.top + rect.height * 0.69,
        ),
        width: rect.width * 0.10,
        height: rect.height * 0.12,
      ),
      MuscleGroup.hamstrings,
    );

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(centerX - painter.width / 2, rect.bottom - painter.height),
    );
  }

  @override
  bool shouldRepaint(covariant _MuscleMapPainter oldDelegate) {
    return oldDelegate.highlighted != highlighted ||
        oldDelegate.selected != selected;
  }
}
