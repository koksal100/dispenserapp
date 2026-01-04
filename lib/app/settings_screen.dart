import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dispenserapp/main.dart'; // AppColors
import 'package:dispenserapp/app/reports_screen.dart'; // Rapor ekranı

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();

  // Sadece feedback özelliği açık olan cihazları tutacak liste
  List<Map<String, String>> _activeFeedbackDevices = [];
  bool _isLoadingDevices = true;

  @override
  void initState() {
    super.initState();
    _fetchAndFilterDevices();
  }

  // Cihazları çek ve sadece feedback açık olanları filtrele
  Future<void> _fetchAndFilterDevices() async {
    final user = await _authService.getOrCreateUser();
    if (user != null && user.email != null) {
      // 1. Tüm cihazları getir
      final allDevices = await _dbService.getAllUserDevices(user.uid, user.email!);

      List<Map<String, String>> filteredList = [];

      // 2. Her cihaz için feedback ayarını kontrol et
      for (var device in allDevices) {
        bool isEnabled = await _dbService.getDeviceFeedbackPreference(user.uid, device['mac']!);
        if (isEnabled) {
          filteredList.add(device);
        }
      }

      if (mounted) {
        setState(() {
          _activeFeedbackDevices = filteredList;
          _isLoadingDevices = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingDevices = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          title: Text("settings_title".tr(),
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepSea)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.deepSea)
      ),
      body: _isLoadingDevices
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Dil Seçimi
          ListTile(
            leading: const Icon(Icons.language, color: AppColors.deepSea),
            title: Text("language_option".tr()),
            trailing: DropdownButton<String>(
                value: context.locale.languageCode,
                underline: Container(),
                items: const [
                  DropdownMenuItem(value: 'tr', child: Text("🇹🇷 Türkçe")),
                  DropdownMenuItem(value: 'en', child: Text("🇺🇸 English"))
                ],
                onChanged: (v) {
                  if (v != null) {
                    context.setLocale(Locale(v == 'tr' ? 'tr' : 'en', v == 'tr' ? 'TR' : 'US'));
                  }
                }
            ),
          ),

          const Divider(),

          // 2. Dispenser Raporları (Sadece Aktif Olanlar)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.bar_chart_rounded, color: AppColors.deepSea),
              title: Text("dispense_reports_title".tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text("view_reports_for".tr()),
              children: [
                if(_activeFeedbackDevices.isEmpty)
                // AKTİF CİHAZ YOKSA GRİ PLACEHOLDER
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20.0),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300)
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.speaker_notes_off, color: Colors.grey.shade400, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          "responsive_feedback_inactive".tr(), // "Geri bildirim kapalı"
                          style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "enable_feedback_hint".tr(), // DÜZELTİLDİ: "Cihazınızın alarm ayarlarından..."
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                // AKTİF CİHAZLAR VARSA LİSTELE
                  ..._activeFeedbackDevices.map((device) {
                    return ListTile(
                      contentPadding: const EdgeInsets.only(left: 72, right: 16),
                      title: Text(
                          device['name'] ?? "unknown_device".tr(),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepSea)
                      ),
                      subtitle: Text(
                          device['mac'] ?? "",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () {
                        // Kendi raporumuzu açıyoruz (targetUserId null gider)
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ReportsScreen(macAddress: device['mac']!)));
                      },
                    );
                  })
              ],
            ),
          ),
        ],
      ),
    );
  }
}