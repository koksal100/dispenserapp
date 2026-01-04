import 'dart:math';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SelectorColors {
  static const Color skyBlue = Color(0xFF1D8AD6);
  static const Color turquoise = Color(0xFF36C0A6);
  static const Color deepSea = Color(0xFF0F5191);
  static const Color background = Color(0xFFF5F7FA);
}

class CircularSelector extends StatefulWidget {
  final List<Map<String, dynamic>> sections;
  final Function(int, Map<String, dynamic>) onUpdate;

  const CircularSelector({
    super.key,
    required this.sections,
    required this.onUpdate,
  });

  @override
  State<CircularSelector> createState() => CircularSelectorState();
}

class CircularSelectorState extends State<CircularSelector> with SingleTickerProviderStateMixin {
  late AnimationController _mainController;
  late Animation<double> _globalCurve;
  late List<Animation<double>> _segmentAnimations;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _globalCurve = CurvedAnimation(parent: _mainController, curve: Curves.easeInOutCubic);

    _segmentAnimations = List.generate(3, (index) {
      final double start = index / 3.0;
      final double end = (index + 1) / 3.0;

      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _globalCurve,
          curve: Interval(start, end, curve: Curves.linear),
        ),
      );
    });

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _mainController.forward();
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  Future<void> showEditDialog(int sectionIndex) async {
    final theme = Theme.of(context);
    final section = widget.sections[sectionIndex];

    final nameController = TextEditingController(text: section['name']);
    final countController = TextEditingController(text: (section['pillCount'] ?? 0).toString());

    List<TimeOfDay> currentTimes = List<TimeOfDay>.from(section['times'] ?? []);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            currentTimes.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SelectorColors.skyBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_calendar_rounded, color: SelectorColors.skyBlue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "edit_medicine_title".tr(),
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700, color: SelectorColors.deepSea, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: "medicine_name_label".tr(),
                          prefixIcon: const Icon(Icons.medication_outlined, color: SelectorColors.skyBlue),
                          filled: true,
                          fillColor: SelectorColors.background,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: countController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: "total_pills_label".tr(),
                          prefixIcon: const Icon(Icons.numbers_rounded, color: SelectorColors.skyBlue),
                          suffixText: "pills".tr(),
                          filled: true,
                          fillColor: SelectorColors.background,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("reminder_times_header".tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: SelectorColors.turquoise),
                            onPressed: () async {
                              final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                              if (t != null && !currentTimes.contains(t)) setStateInDialog(() => currentTimes.add(t));
                            },
                          )
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: currentTimes.map((t) => Chip(
                          label: Text(t.format(context)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () => setStateInDialog(() => currentTimes.remove(t)),
                          backgroundColor: SelectorColors.background,
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("cancel".tr())),
                ElevatedButton(
                  onPressed: () {
                    int cnt = int.tryParse(countController.text) ?? 0;
                    Navigator.of(context).pop({'name': nameController.text, 'times': currentTimes, 'pillCount': cnt});
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: SelectorColors.skyBlue),
                  child: Text("save".tr(), style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      widget.onUpdate(sectionIndex, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size.square(min(constraints.maxWidth, constraints.maxHeight));

        return Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _mainController,
              builder: (context, child) {
                return GestureDetector(
                  onTapUp: (details) => _handleTap(details.localPosition, size),
                  child: CustomPaint(
                    size: size,
                    painter: _CircularSelectorPainter(
                      sections: widget.sections,
                      context: context,
                      segmentAnimations: _segmentAnimations,
                      textOpacity: _opacityAnimation.value,
                    ),
                  ),
                );
              },
            ),

            IgnorePointer(
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: SizedBox(
                  width: size.width * 0.25,
                  height: size.width * 0.25,
                  child: Image.asset(
                    'assets/icon.png',
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => Icon(
                      Icons.medical_services_rounded,
                      size: size.width * 0.2,
                      color: SelectorColors.deepSea.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleTap(Offset tapPosition, Size size) {
    if (_mainController.isAnimating || widget.sections.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.22;
    final radius = (size.width / 2) - (strokeWidth / 2);

    final dx = tapPosition.dx - center.dx;
    final dy = tapPosition.dy - center.dy;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance >= radius - (strokeWidth / 2) && distance <= radius + (strokeWidth / 2)) {
      final sectionAngle = 2 * pi / widget.sections.length;
      final tapAngle = atan2(dy, dx);
      double normalizedAngle = tapAngle + (pi / 2) + (sectionAngle / 2);

      if (normalizedAngle < 0) normalizedAngle += 2 * pi;
      if (normalizedAngle >= 2 * pi) normalizedAngle -= 2 * pi;

      final index = (normalizedAngle / sectionAngle).floor() % widget.sections.length;
      if (index >= 0 && index < widget.sections.length) {
        showEditDialog(index);
      }
    }
  }
}

class _CircularSelectorPainter extends CustomPainter {
  final List<Map<String, dynamic>> sections;
  final BuildContext context;
  final List<Animation<double>> segmentAnimations;
  final double textOpacity;

  final List<Color> _colors = [
    SelectorColors.skyBlue,
    SelectorColors.turquoise,
    SelectorColors.deepSea,
  ];

  _CircularSelectorPainter({
    required this.sections,
    required this.context,
    required this.segmentAnimations,
    required this.textOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.22;
    final radius = (size.width / 2) - (strokeWidth / 2);

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = SelectorColors.background;
    canvas.drawCircle(center, radius, bgPaint);

    if (sections.isNotEmpty) {
      final sectionAngle = 2 * pi / sections.length;

      for (int i = 0; i < sections.length; i++) {
        final progress = segmentAnimations[i].value;
        if (progress <= 0.01) continue;

        final startAngle = (i * sectionAngle) - (pi / 2) - (sectionAngle / 2);
        const gap = 0.008;
        final sweepAngle = (sectionAngle - gap) * progress;

        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt
          ..color = _colors[i % _colors.length];

        canvas.drawArc(
            Rect.fromCircle(center: center, radius: radius),
            startAngle + (gap / 2),
            sweepAngle,
            false,
            paint
        );
      }

      for (int i = 0; i < sections.length; i++) {
        final progress = segmentAnimations[i].value;
        if (progress <= 0.05) continue;

        final startAngle = i * sectionAngle - (pi / 2) - (sectionAngle / 2);
        const gap = 0.008;

        final startPoint = Offset(
          center.dx + radius * cos(startAngle + (gap / 2)),
          center.dy + radius * sin(startAngle + (gap / 2)),
        );
        final holePaint = Paint()..style = PaintingStyle.fill..color = SelectorColors.background;
        canvas.drawCircle(startPoint, strokeWidth / 2, holePaint);
      }

      for (int i = 0; i < sections.length; i++) {
        final progress = segmentAnimations[i].value;
        if (progress <= 0.05) continue;

        final startAngle = i * sectionAngle - (pi / 2) - (sectionAngle / 2);
        const gap = 0.008;
        final currentSweepAngle = (sectionAngle - gap) * progress;
        final endAngle = startAngle + (gap / 2) + currentSweepAngle;

        final endPoint = Offset(
          center.dx + radius * cos(endAngle),
          center.dy + radius * sin(endAngle),
        );
        final capPaint = Paint()..style = PaintingStyle.fill..color = _colors[i % _colors.length];
        canvas.drawCircle(endPoint, strokeWidth / 2, capPaint);

        if (textOpacity > 0.1 && progress > 0.95) {
          final midAngle = startAngle + (sectionAngle / 2);
          _drawText(canvas, center, radius, midAngle, sections[i]);
        }
      }
    }
  }

  void _drawText(Canvas canvas, Offset center, double radius, double angle, Map<String, dynamic> section) {
    final name = section['name'] as String;
    final int count = section['pillCount'] ?? 0;
    final List<TimeOfDay> times = List<TimeOfDay>.from(section['times'] ?? []);

    String doseInfo;
    if (times.isEmpty) {
      doseInfo = "--:--";
    } else if (times.length == 1) {
      doseInfo = times.first.format(context);
    } else {
      doseInfo = "${times.length}x";
    }

    // --- DÜZELTME BURADA YAPILDI ---
    // 1. Yazı fontunu küçülttük (İsim uzunsa daha da küçülür)
    // 2. MaxWidth'i daralttık (Taşmayı önlemek için)

    double nameFontSize = radius * 0.13;
    if (name.length > 8) nameFontSize = radius * 0.11; // Uzun isimler için fontu küçült
    if (name.length > 12) nameFontSize = radius * 0.09;

    final textSpan = TextSpan(
      children: [
        TextSpan(
          text: name,
          style: TextStyle(
              color: Colors.white.withOpacity(textOpacity),
              fontSize: nameFontSize,
              fontWeight: FontWeight.w900,
              height: 1.1,
              shadows: [const Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))]
          ),
        ),
        const TextSpan(text: "\n"),
        TextSpan(
          text: "$doseInfo\n",
          style: TextStyle(
              color: Colors.white.withOpacity(textOpacity * 0.95),
              fontSize: radius * 0.09,
              fontWeight: FontWeight.w700,
              height: 1.3,
              shadows: [const Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))]
          ),
        ),
        TextSpan(
          text: "$count ${'left_abbr'.tr()}",
          style: TextStyle(
              color: Colors.white.withOpacity(textOpacity * 0.9),
              fontSize: radius * 0.08,
              fontWeight: FontWeight.w500,
              shadows: [const Shadow(color: Colors.black26, blurRadius: 1, offset: Offset(0, 1))]
          ),
        ),
      ],
    );

    final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
        maxLines: 3, // Maksimum 3 satıra izin ver
        ellipsis: '..'
    );

    // Genişlik Kısıtlaması: Yarıçapın %75'i kadar (Taşmayı engeller)
    textPainter.layout(minWidth: 0, maxWidth: radius * 0.75);

    // Konumlandırma: Tam yayın üzerine
    final textX = center.dx + radius * cos(angle) - (textPainter.width / 2);
    final textY = center.dy + radius * sin(angle) - (textPainter.height / 2);

    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(covariant _CircularSelectorPainter oldDelegate) {
    return true;
  }
}