import 'dart:math';
import 'dart:ui' as ui; // TextDirection çakışmasını önlemek için eklendi

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

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

class CircularSelectorState extends State<CircularSelector> {
  Future<void> showEditDialog(int sectionIndex) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final section = widget.sections[sectionIndex];
    final nameController = TextEditingController(text: section['name']);
    TimeOfDay? pickedTime = section['time'];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.edit_calendar_rounded, color: colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "edit_medicine_title".tr(),
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F5191), // Derin Deniz Mavisi
                          fontSize: 20
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: "medicine_name_label".tr(),
                      hintText: "medicine_name_hint".tr(),
                      labelStyle: TextStyle(color: Colors.blueGrey.shade600),
                      prefixIcon: Icon(Icons.medication_outlined, color: colorScheme.primary),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colorScheme.primary, width: 2),
                      ),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 16),

                  InkWell(
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: pickedTime ?? TimeOfDay.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              timePickerTheme: TimePickerThemeData(
                                dialHandColor: colorScheme.primary,
                                dialBackgroundColor: colorScheme.surface,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (time != null) {
                        setStateInDialog(() {
                          pickedTime = time;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time_filled_rounded, color: colorScheme.primary, size: 26),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "reminder_time_label".tr(),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blueGrey.shade600,
                                    fontWeight: FontWeight.w600
                                ),
                              ),
                              Text(
                                pickedTime?.format(context) ?? '--:--',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.primary,
                                    letterSpacing: 0.5
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Icon(Icons.edit, size: 18, color: colorScheme.primary.withOpacity(0.6)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.end,
              actionsPadding: const EdgeInsets.fromLTRB(16, 16, 24, 24),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("cancel".tr(), style: TextStyle(color: Colors.blueGrey.shade400, fontWeight: FontWeight.w600)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (pickedTime != null) {
                      Navigator.of(context).pop({
                        'name': nameController.text.isNotEmpty ? nameController.text : section['name'],
                        'time': pickedTime,
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text("save".tr()),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      widget.onUpdate(sectionIndex, {
        'name': result['name'],
        'time': result['time'],
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) {
        _handleTap(details.localPosition);
      },
      child: CustomPaint(
        painter: _CircularSelectorPainter(widget.sections, context),
        child: Container(),
      ),
    );
  }

  void _handleTap(Offset tapPosition) {
    if (widget.sections.isEmpty) return;

    final size = context.size!;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) * 0.75;
    final strokeWidth = 50.0;

    final dx = tapPosition.dx - center.dx;
    final dy = tapPosition.dy - center.dy;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance > radius - strokeWidth / 2 - 25 && distance < radius + strokeWidth / 2 + 25) {
      final sectionAngle = 2 * pi / widget.sections.length;
      final tapAngle = atan2(dy, dx);
      final adjustedAngle = tapAngle + (pi / 2) + (sectionAngle / 2);
      final normalizedAngle = (adjustedAngle + 2 * pi) % (2 * pi);
      final tappedSectionIndex = (normalizedAngle / sectionAngle).floor();

      if (tappedSectionIndex >= 0 && tappedSectionIndex < widget.sections.length) {
        showEditDialog(tappedSectionIndex);
      }
    }
  }
}

class _CircularSelectorPainter extends CustomPainter {
  final List<Map<String, dynamic>> sections;
  final BuildContext context;

  // MedTrack Renk Paleti
  final List<Color> _colors = [
    const Color(0xFF1D8AD6), // Gök Mavisi
    const Color(0xFF36C0A6), // Turkuaz
    const Color(0xFF0F5191), // Derin Deniz Mavisi
  ];

  _CircularSelectorPainter(this.sections, this.context);

  @override
  void paint(Canvas canvas, Size size) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) * 0.82;
    const strokeWidth = 65.0;

    // 1. GÖLGE (MANUEL ÇİZİM - HATA DÜZELTİLDİ)
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8); // Gölge efekti buradan geliyor

    canvas.drawCircle(center, radius, shadowPaint);

    // 2. ARKA PLAN HALKASI
    final basePaint = Paint()
      ..color = Colors.grey.shade100
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, basePaint);

    if (sections.isEmpty) return;

    final sectionAngle = 2 * pi / sections.length;

    for (int i = 0; i < sections.length; i++) {
      final startAngle = i * sectionAngle - (pi / 2) - (sectionAngle / 2);
      final sweepAngle = sectionAngle;

      final gap = 0.06;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = _colors[i % _colors.length];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gap,
        sweepAngle - (gap * 2),
        false,
        paint,
      );

      final textAngle = startAngle + sweepAngle / 2;
      final timeOfDay = sections[i]['time'] as TimeOfDay?;
      final name = sections[i]['name'] as String;
      final timeText = timeOfDay?.format(context) ?? '';

      final textRadius = radius;

      final textSpan = TextSpan(
        children: [
          TextSpan(
            text: '$name\n',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          TextSpan(
            text: timeText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );

      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr, // DÜZELTİLDİ: ui.TextDirection kullanıldı
      )..layout(minWidth: 0, maxWidth: 80);

      final textX = center.dx + textRadius * cos(textAngle) - textPainter.width / 2;
      final textY = center.dy + textRadius * sin(textAngle) - textPainter.height / 2;

      textPainter.paint(canvas, Offset(textX, textY));
    }

    // 3. MERKEZ İKON ALANI (MANUEL GÖLGE - HATA DÜZELTİLDİ)

    // A) Önce Gölgeyi Çiz (Bulanık Daire)
    final centerShadowPaint = Paint()
      ..color = colorScheme.primary.withOpacity(0.2) // Gölge rengi
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10); // Bulanıklık

    canvas.drawCircle(center, radius * 0.4, centerShadowPaint);

    // B) Sonra Beyaz Daireyi Çiz
    final centerCirclePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.4, centerCirclePaint);

    // C) En Son İkonu Çiz
    final centerIcon = Icons.medical_services_rounded;
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(centerIcon.codePoint),
        style: TextStyle(
          fontSize: 42,
          fontFamily: centerIcon.fontFamily,
          color: colorScheme.primary,
        ),
      ),
      textDirection: ui.TextDirection.ltr, // DÜZELTİLDİ
    )..layout();

    iconPainter.paint(canvas, Offset(center.dx - iconPainter.width / 2, center.dy - iconPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CircularSelectorPainter oldDelegate) {
    return oldDelegate.sections != sections || oldDelegate.context != context;
  }
}