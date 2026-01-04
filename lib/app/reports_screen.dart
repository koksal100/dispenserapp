import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/main.dart'; // AppColors

class ReportsScreen extends StatefulWidget {
  final String macAddress;
  final String? targetUserId; // YENİ: Başkasının raporunu görmek için
  final String? titlePrefix;  // YENİ: Başlıkta isim göstermek için (örn: "Ahmet")

  const ReportsScreen({
    super.key,
    required this.macAddress,
    this.targetUserId,
    this.titlePrefix
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final DatabaseService _db = DatabaseService();
  final AuthService _authService = AuthService();

  Map<String, dynamic> _stats = {};
  Map<int, String> _pillNames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // 1. Hedef Kullanıcıyı Belirle
    String uidToUse;
    if (widget.targetUserId != null) {
      uidToUse = widget.targetUserId!;
    } else {
      // Eğer parametre gelmediyse kendi ID'mizi kullan
      final user = await _authService.getOrCreateUser();
      uidToUse = user!.uid;
    }

    // 2. İstatistikleri Çek (Hedef UID ile)
    final statsData = await _db.getDispenseStats(widget.macAddress, uidToUse);

    // 3. İlaç İsimlerini Çek (Cihaz configinden)
    Map<int, String> pillMap = {};
    try {
      var doc = await FirebaseFirestore.instance.collection('dispenser').doc(widget.macAddress).get();
      if(doc.exists && doc.data()!.containsKey('section_config')) {
        List<dynamic> sections = doc.data()!['section_config'];
        for(int i=0; i<sections.length; i++) {
          pillMap[i] = sections[i]['name'] ?? "unknown_pill".tr();
        }
      }
    } catch(e) {
      debugPrint("İlaç isimleri çekilemedi: $e");
    }

    if(mounted) {
      setState(() {
        _stats = statsData;
        _pillNames = pillMap;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    int total = _stats['total'] ?? 0;
    int success = _stats['success'] ?? 0;
    int failed = _stats['failed'] ?? 0;

    Map<String, Map<String, int>> sectionStatsRaw = {};
    if(_stats['sectionStats'] != null) {
      _stats['sectionStats'].forEach((key, value) {
        if(value is Map<String, int>) {
          sectionStatsRaw[key] = value;
        }
      });
    }

    var sortedEntries = sectionStatsRaw.entries.toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));

    // Başlık Mantığı: Eğer birine bakıyorsak "Ahmet - Haftalık Rapor", kendimize bakıyorsak "Haftalık Rapor"
    String pageTitle = widget.titlePrefix != null
        ? "${widget.titlePrefix} - ${"weekly_report".tr()}"
        : "weekly_report".tr();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          title: Text(pageTitle, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepSea, fontSize: 16)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.deepSea)
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : total == 0
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 20),
            Text("no_data_yet".tr(), style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatCard("total_label".tr(), total.toString(), Colors.blue),
                const SizedBox(width: 10),
                _buildStatCard("success_label".tr(), success.toString(), Colors.green),
                const SizedBox(width: 10),
                _buildStatCard("issues_label".tr(), failed.toString(), Colors.redAccent),
              ],
            ),
            const SizedBox(height: 30),

            Text("weekly_activity".tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepSea)),
            const SizedBox(height: 20),

            Container(
              height: 280,
              padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _yAxisLabel("20+"),
                      _yAxisLabel("15"),
                      _yAxisLabel("10"),
                      _yAxisLabel("5"),
                      _yAxisLabel(""),
                    ],
                  ),
                  const SizedBox(width: 10),

                  Expanded(
                    child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children:List.generate(5, (index) => _buildGridLine()),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: _buildBars(constraints.maxHeight),
                              ),
                            ],
                          );
                        }
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),
            Text("section_details_title".tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepSea)),
            const SizedBox(height: 10),
            _buildSectionDetails(sortedEntries),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _yAxisLabel(String text) {
    return SizedBox(
      height: 20,
      child: Center(
          child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold))
      ),
    );
  }

  Widget _buildGridLine() {
    return Container(
      height: 20,
      child: Center(
        child: Container(
          height: 1,
          color: Colors.grey.shade200,
        ),
      ),
    );
  }

  Widget _buildSectionDetails(List<MapEntry<String, Map<String, int>>> sortedEntries) {
    if (sortedEntries.isEmpty) return const SizedBox();

    return Column(
      children: sortedEntries.map((entry) {
        int sectionIndex = int.parse(entry.key);
        String sectionName = "section_prefix".tr(args: [(sectionIndex + 1).toString()]);
        String pillName = _pillNames[sectionIndex] ?? "unknown_pill".tr();

        int s = entry.value['success'] ?? 0;
        int f = entry.value['failed'] ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))]
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.skyBlue.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.medication, color: AppColors.skyBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sectionName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepSea, fontSize: 15)),
                        Text("($pillName)", style: TextStyle(color: Colors.grey.shade600, fontSize: 13, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ]),
              ),
              Row(children: [
                _statusBadge(Icons.check_circle_rounded, Colors.green, s),
                const SizedBox(width: 12),
                _statusBadge(Icons.cancel_rounded, Colors.redAccent, f),
              ])
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _statusBadge(IconData icon, Color color, int count) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(count.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
      ],
    );
  }

  List<Widget> _buildBars(double maxHeight) {
    Map<dynamic, dynamic> rawData = _stats['weeklyData'] ?? {};
    Map<int, int> data = {};
    rawData.forEach((key, value) {
      if(key is int && value is int) data[key] = value;
    });

    int maxScale = 20;
    List<String> days = [
      'day_m'.tr(), 'day_t'.tr(), 'day_w'.tr(), 'day_th'.tr(), 'day_f'.tr(), 'day_sa'.tr(), 'day_su'.tr()
    ];

    return List.generate(7, (index) {
      int dayIndex = index + 1;
      int value = data[dayIndex] ?? 0;

      double chartAreaHeight = maxHeight - 30;
      double barHeight = (value / maxScale) * chartAreaHeight;
      if(barHeight > chartAreaHeight) barHeight = chartAreaHeight;

      return Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Tooltip(
            message: "$value",
            child: Container(
              width: 14,
              height: barHeight < 4 ? 4 : barHeight,
              decoration: BoxDecoration(
                color: value > 0 ? AppColors.skyBlue : Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                gradient: value > 0 ? const LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [AppColors.skyBlue, Color(0xFF4FC3F7)]
                ) : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(days[index], style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      );
    });
  }

  Widget _buildStatCard(String title, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
        ),
        child: Column(
          children: [
            Text(val, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 5),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}