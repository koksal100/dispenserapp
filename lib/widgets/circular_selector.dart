import 'dart:math';
import 'dart:ui' as ui;

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

    // ARTIK LİSTE OLARAK ALIYORUZ
    List<TimeOfDay> currentTimes = List<TimeOfDay>.from(section['times'] ?? []);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {

            // Saatleri Sırala (Erkenden geçe)
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
                      color: const Color(0xFFF0F9FF), // Açık Gök Mavisi
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_calendar_rounded, color: Color(0xFF1D8AD6), size: 24),
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
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // İlaç Adı Input
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: "medicine_name_label".tr(),
                        hintText: "medicine_name_hint".tr(),
                        labelStyle: TextStyle(color: Colors.blueGrey.shade600),
                        prefixIcon: const Icon(Icons.medication_outlined, color: Color(0xFF1D8AD6)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF1D8AD6), width: 2)),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 20),

                    // Saatler Başlığı ve Ekle Butonu
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "reminder_times_header".tr(), // "Hatırlatma Saatleri" (YENİ KEY)
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.blueGrey.shade700),
                        ),

                        // SAAT EKLEME BUTONU
                        InkWell(
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    timePickerTheme: const TimePickerThemeData(
                                      dialHandColor: Color(0xFF1D8AD6),
                                      dialBackgroundColor: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (time != null) {
                              setStateInDialog(() {
                                // Aynı saatten varsa ekleme
                                if (!currentTimes.any((t) => t.hour == time.hour && t.minute == time.minute)) {
                                  currentTimes.add(time);
                                }
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF36C0A6).withOpacity(0.1), // Turkuaz Vurgu
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.add_alarm_rounded, size: 16, color: Color(0xFF36C0A6)),
                                const SizedBox(width: 4),
                                Text(
                                  "add_time".tr(), // "Saat Ekle" (YENİ KEY)
                                  style: const TextStyle(color: Color(0xFF36C0A6), fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // SAAT LİSTESİ (Wrap ile çoklu satır)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150), // Çok uzarsa scroll olsun
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: currentTimes.isEmpty
                              ? [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: Text("no_times_added".tr(), style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                            )
                          ]
                              : currentTimes.map((time) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F9FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE0F2FE)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF1D8AD6)),
                                  const SizedBox(width: 6),
                                  Text(
                                    time.format(context),
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F5191), fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      setStateInDialog(() {
                                        currentTimes.remove(time);
                                      });
                                    },
                                    child: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                                  )
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
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
                    Navigator.of(context).pop({
                      'name': nameController.text.isNotEmpty ? nameController.text : section['name'],
                      'times': currentTimes, // LİSTE DÖNDÜRÜYORUZ
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D8AD6),
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
        'times': result['times'], // HomeScreen bu listeyi işleyecek
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) => _handleTap(details.localPosition),
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

    // Gölgeler ve Arka Plan (Aynı Kalıyor)
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius, shadowPaint);

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

      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle + gap, sweepAngle - (gap * 2), false, paint);

      // METİN ÇİZİMİ (Çoklu Saat Mantığı)
      final textAngle = startAngle + sweepAngle / 2;
      final name = sections[i]['name'] as String;

      // ÇOKLU SAAT KONTROLÜ
      final List<TimeOfDay> times = List<TimeOfDay>.from(sections[i]['times'] ?? []);
      String infoText = "";

      if (times.isEmpty) {
        infoText = "--:--";
      } else if (times.length == 1) {
        infoText = times.first.format(context);
      } else {
        // Eğer birden fazla saat varsa "3 Doz" veya "3x" yaz
        infoText = "${times.length}x ${"dose_suffix".tr()}"; // "3x Doz" (YENİ KEY)
      }

      final textRadius = radius;

      final textSpan = TextSpan(
        children: [
          TextSpan(
            text: '$name\n',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.2),
          ),
          TextSpan(
            text: infoText,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w500),
          ),
        ],
      );

      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: 80);

      final textX = center.dx + textRadius * cos(textAngle) - textPainter.width / 2;
      final textY = center.dy + textRadius * sin(textAngle) - textPainter.height / 2;

      textPainter.paint(canvas, Offset(textX, textY));
    }

    // Merkez İkon Çizimi (Aynı Kalıyor)
    final centerShadowPaint = Paint()..color = colorScheme.primary.withOpacity(0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center, radius * 0.4, centerShadowPaint);
    final centerCirclePaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.4, centerCirclePaint);
    final centerIcon = Icons.medical_services_rounded;
    final iconPainter = TextPainter(
      text: TextSpan(text: String.fromCharCode(centerIcon.codePoint), style: TextStyle(fontSize: 42, fontFamily: centerIcon.fontFamily, color: colorScheme.primary)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    iconPainter.paint(canvas, Offset(center.dx - iconPainter.width / 2, center.dy - iconPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CircularSelectorPainter oldDelegate) => oldDelegate.sections != sections || oldDelegate.context != context;
}