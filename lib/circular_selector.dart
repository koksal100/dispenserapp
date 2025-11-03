import 'dart:math';

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
  // State sınıfı adını CircularSelectorState olarak değiştirdik (public erişim için)
  State<CircularSelector> createState() => CircularSelectorState();
}

// State sınıfı adını CircularSelectorState olarak değiştirdik
class CircularSelectorState extends State<CircularSelector> {

  // Metot adını public erişim için showEditDialog olarak değiştirdik
  Future<void> showEditDialog(int sectionIndex) async {
    final section = widget.sections[sectionIndex];
    final nameController = TextEditingController(text: section['name']);
    TimeOfDay? pickedTime = section['time'];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.edit_note, color: Colors.teal),
                  SizedBox(width: 10),
                  Text('İlaç Bilgilerini Düzenle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'İlaç Adı',
                      hintText: 'Örn: Sabah Tableti',
                      prefixIcon: const Icon(Icons.medication_outlined, color: Colors.teal),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.teal),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.teal, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.access_time_filled, color: Colors.teal),
                      title: const Text(
                        'Hatırlatma Saati',
                        style: TextStyle(fontWeight: FontWeight.w500, color: Colors.teal),
                      ),
                      trailing: Text(
                        pickedTime?.format(context) ?? 'Saat Seç',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.teal,
                        ),
                      ),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: pickedTime ?? TimeOfDay.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: Colors.teal,
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black,
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
                    ),
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.spaceAround,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  onPressed: () {
                    if (pickedTime != null) {
                      Navigator.of(context).pop({
                        'name': nameController.text.isNotEmpty ? nameController.text : section['name'],
                        'time': pickedTime,
                      });
                    }
                  },
                  label: const Text('Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
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
        showEditDialog(tappedSectionIndex); // Public metodu kullandık
      }
    }
  }
}

// --- Dairesel Çizim (Painter) ---
class _CircularSelectorPainter extends CustomPainter {
  final List<Map<String, dynamic>> sections;
  final BuildContext context;

  final List<Color> _colors = [
    Colors.teal.shade400,
    Colors.deepOrange.shade400,
    Colors.lightBlue.shade400,
    Colors.purple.shade400,
    Colors.green.shade400,
    Colors.pink.shade400,
    Colors.amber.shade400,
    Colors.indigo.shade400,
  ];

  _CircularSelectorPainter(this.sections, this.context);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) * 0.75;
    final strokeWidth = 50.0;

    // Temel halka (Arka plan)
    final basePaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt; // DÜZ UÇLAR

    canvas.drawCircle(center, radius, basePaint);

    if (sections.isEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'İlaç Ekle',
          style: TextStyle(color: Colors.teal.shade400, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.5);

      final icon = Icons.add_circle_outline;
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 40,
            fontFamily: icon.fontFamily,
            color: Colors.grey.shade400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      iconPainter.paint(canvas, Offset(center.dx - iconPainter.width / 2, center.dy - iconPainter.height - 5));
      textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy + 5));
      return;
    }

    final sectionAngle = 2 * pi / sections.length;

    for (int i = 0; i < sections.length; i++) {
      final startAngle = i * sectionAngle - (pi / 2) - (sectionAngle / 2);
      final sweepAngle = sectionAngle;

      // Gölge efekti
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0)
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle - 0.05,
        false,
        shadowPaint,
      );

      // Ana Çizgi
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt // DÜZ UÇLAR
        ..color = (_colors[i % _colors.length]);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle - 0.05,
        false,
        paint,
      );

      // --- İlaç İsimleri Okunabilirlik İyileştirmesi (SİYAH METİN) ---
      final textAngle = startAngle + sweepAngle / 2;
      final timeOfDay = sections[i]['time'] as TimeOfDay?;
      final name = sections[i]['name'] as String;
      final timeText = timeOfDay?.format(context) ?? '';

      final textRadius = radius - strokeWidth / 2 - 15;

      final textSpan = TextSpan(
        children: [
          TextSpan(
              text: '$timeText\n',
              style: TextStyle(
                color: Colors.black, // Saat: Siyah
                fontSize: 14,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.white.withOpacity(0.5), blurRadius: 2)],
              )
          ),
          TextSpan(
              text: name,
              style: TextStyle(
                color: Colors.grey.shade800, // İsim: Koyu Gri
                fontSize: 10,
                fontWeight: FontWeight.normal,
                shadows: [Shadow(color: Colors.white.withOpacity(0.5), blurRadius: 2)],
              )
          ),
        ],
      );

      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: 60);

      final textX = center.dx + textRadius * cos(textAngle) - textPainter.width / 2;
      final textY = center.dy + textRadius * sin(textAngle) - textPainter.height / 2;

      textPainter.paint(canvas, Offset(textX, textY));
    }

    // Merkez İkonu
    final centerIcon = Icons.access_time_filled;
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(centerIcon.codePoint),
        style: TextStyle(
          fontSize: 60,
          fontFamily: centerIcon.fontFamily,
          color: Colors.teal.shade300,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    iconPainter.paint(canvas, Offset(center.dx - iconPainter.width / 2, center.dy - iconPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CircularSelectorPainter oldDelegate) {
    return oldDelegate.sections != sections || oldDelegate.context != context;
  }
}