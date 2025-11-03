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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: colorScheme.primary, size: 28),
                  const SizedBox(width: 10),
                  Text('İlaç Bilgilerini Düzenle', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                      prefixIcon: Icon(Icons.medication_outlined, color: colorScheme.primary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colorScheme.primary, width: 2),
                      ),
                    ),
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: Icon(Icons.access_time_filled_rounded, color: colorScheme.primary, size: 28),
                      title: Text(
                        'Hatırlatma Saati',
                        style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                      ),
                      trailing: Text(
                        pickedTime?.format(context) ?? 'Saat Seç',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: pickedTime ?? TimeOfDay.now(),
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
              actionsAlignment: MainAxisAlignment.end,
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('İptal', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt_rounded, size: 20),
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
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
        showEditDialog(tappedSectionIndex);
      }
    }
  }
}

class _CircularSelectorPainter extends CustomPainter {
  final List<Map<String, dynamic>> sections;
  final BuildContext context;

  final List<Color> _colors = [
    const Color(0xFF56ABE8), // Türk Mavisi (Derin, Canlı Mavi)
    const Color(0xFFE60000),     // Koyu Kırmızı (Vişne Kırmızısı)
    const Color(0xFFFFCC00), // Fenerbahçe Sarısı (Parlak Sarı)
    Colors.green.shade600,   // Yeşil (Standart, Canlı)
    const Color(0xFFC55CCD),  // Mor (Canlı Orta Ton)
    const Color(0xFFFF6B6B),    // Pembe (Orta Canlı Pembe)
  ];

  _CircularSelectorPainter(this.sections, this.context);

  @override
  void paint(Canvas canvas, Size size) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) * 0.8;
    const strokeWidth = 70.0; // Increased stroke width

    // Arka plan halkası
    final basePaint = Paint()
      ..color = Colors.grey.shade200 // Lighter background for the ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, basePaint);

    if (sections.isEmpty) return;

    final sectionAngle = 2 * pi / sections.length;

    for (int i = 0; i < sections.length; i++) {
      final startAngle = i * sectionAngle - (pi / 2) - (sectionAngle / 2);
      final sweepAngle = sectionAngle;

      // Renkli bölümler
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = _colors[i % _colors.length];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + 0.025,
        sweepAngle - 0.05,
        false,
        paint,
      );

      // Yazılar
      final textAngle = startAngle + sweepAngle / 2;
      final timeOfDay = sections[i]['time'] as TimeOfDay?;
      final name = sections[i]['name'] as String;
      final timeText = timeOfDay?.format(context) ?? '';

      final textRadius = radius; 

      final textSpan = TextSpan(
        children: [
          TextSpan(
            text: '$timeText\n',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 4, offset: const Offset(1, 2))],
            ),
          ),
          TextSpan(
            text: name,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black.withOpacity(0.7), blurRadius: 4, offset: const Offset(1, 2))],
            ),
          ),
        ],
      );

      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: 90);

      final textX = center.dx + textRadius * cos(textAngle) - textPainter.width / 2;
      final textY = center.dy + textRadius * sin(textAngle) - textPainter.height / 2;

      textPainter.paint(canvas, Offset(textX, textY));
    }

    // Merkez ikon
    final centerIcon = Icons.medication_liquid_rounded;
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(centerIcon.codePoint),
        style: TextStyle(
          fontSize: 64,
          fontFamily: centerIcon.fontFamily,
          color: colorScheme.primary,
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
