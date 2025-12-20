import 'package:easy_localization/easy_localization.dart'; // EKLENDİ
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    // Mevcut dili kontrol et (tr veya en)
    String currentLangCode = context.locale.languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text("settings_title").tr(), // .tr() metni çevirir
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          // --- DİL SEÇENEĞİ ---
          ListTile(
            leading: const Icon(Icons.language),
            title: Text("language_option").tr(),
            trailing: DropdownButton<String>(
              value: currentLangCode,
              underline: Container(),
              items: const [
                DropdownMenuItem(
                  value: 'tr',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text("🇹🇷 Türkçe")],
                  ),
                ),
                DropdownMenuItem(
                  value: 'en',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text("🇺🇸 English")],
                  ),
                ),
              ],
              onChanged: (String? newValue) {
                if (newValue != null) {
                  // DİLİ DEĞİŞTİRME KOMUTU
                  if (newValue == 'tr') {
                    context.setLocale(const Locale('tr', 'TR'));
                  } else {
                    context.setLocale(const Locale('en', 'US'));
                  }
                  // UI yenilenmesi için setState gerekmez, easy_localization halleder.
                  // Ancak Dropdown anlık görünsün diye boş bir setState bırakabiliriz.
                  setState(() {});
                }
              },
            ),
          ),

          const Divider(),

          // --- YARDIM BUTONU ---
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text("help").tr(),
            subtitle: Text("help_subtitle").tr(),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("help_message").tr()),
              );
            },
          ),
        ],
      ),
    );
  }
}