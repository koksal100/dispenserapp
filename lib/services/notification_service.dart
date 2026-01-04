import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String _alarmsEnabledKey = 'alarms_enabled';
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _notificationOffsetKey = 'notification_offset';
  // V2 yaparak eski hatalı bildirim kayıtlarını geçersiz kıldık.
  // Bu sayede uygulama açılır açılmaz stok kontrolünü taze bir şekilde yapacak.
  static const String _lastStockNotifKey = 'last_stock_notif_v2_';

  // --- BAŞLATMA ---
  static Future<void> initializeNotifications() async {
    await Alarm.init();
    await AwesomeNotifications().initialize(
      'resource://drawable/notification_bar_icon',
      [
        NotificationChannel(
          channelKey: 'reminder_channel',
          channelName: 'Medicine Reminders',
          channelDescription: 'Pre-notifications for medicine',
          defaultColor: const Color(0xFF1D8AD6),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
        ),
        NotificationChannel(
          channelKey: 'stock_warning_channel',
          channelName: 'Stock Warnings',
          channelDescription: 'Low medicine stock alerts',
          defaultColor: Colors.redAccent,
          ledColor: Colors.red,
          importance: NotificationImportance.High,
          playSound: true,
          enableVibration: true,
        )
      ],
      debug: false,
    );
  }

  static Future<void> requestPermission() async {
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }

    if (Platform.isAndroid) {
      await Permission.scheduleExactAlarm.request();

      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
  }


  Future<void> saveNotificationSettings({required bool alarmsEnabled, required bool notificationsEnabled, required int offset}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alarmsEnabledKey, alarmsEnabled);
    await prefs.setBool(_notificationsEnabledKey, notificationsEnabled);
    await prefs.setInt(_notificationOffsetKey, offset);
  }

  Future<Map<String, dynamic>> getNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'alarms_enabled': prefs.getBool(_alarmsEnabledKey) ?? true,
      'notifications_enabled': prefs.getBool(_notificationsEnabledKey) ?? true,
      'offset': prefs.getInt(_notificationOffsetKey) ?? 10,
    };
  }

  // --- Metadata Kaydı (Çoklu İlaç Destekli) ---
  Future<void> _saveAlarmMetadata(int alarmId, String macAddress, List<int> sectionIndices, List<String> medicineNames) async {
    final prefs = await SharedPreferences.getInstance();
    String indicesStr = sectionIndices.join(',');
    String namesStr = medicineNames.join(',');
    await prefs.setString('alarm_meta_$alarmId', '$macAddress|$indicesStr|$namesStr');
  }

  // --- Stok Kontrolü ve Bildirimi (MANUEL REPLACE İLE DÜZELTİLDİ) ---
  Future<void> checkStockAndNotify(List<Map<String, dynamic>> sections, String macAddress) async {
    final prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < sections.length; i++) {
      var section = sections[i];
      if (section['isActive'] != true) continue;

      final int count = section['pillCount'] ?? 0;
      final List times = section['times'] ?? [];
      final int dailyDose = times.length;
      final String medName = (section['name'] != null && section['name'].toString().isNotEmpty)
          ? section['name']
          : "medicine".tr();

      String uniqueKey = "$_lastStockNotifKey${macAddress}_$i";
      int lastNotifiedCount = prefs.getInt(uniqueKey) ?? -1;

      // Eğer bu sayı için zaten bildirim attıysak tekrar atma
      if (lastNotifiedCount == count) continue;

      int notifId = (macAddress.hashCode + i).abs();

      // 1. Son İlaç Kaldıysa
      if (count == 1) {
        // DÜZELTME: Kütüphane yerine manuel replace yapıyoruz. %100 çalışır.
        String bodyText = "last_pill_warning_body".tr()
            .replaceAll("{0}", medName)
            .replaceAll("{}", medName); // Ne olur ne olmaz boş parantezi de kapsar

        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: notifId,
            channelKey: 'stock_warning_channel',
            title: "last_pill_warning_title".tr(),
            body: bodyText,
            notificationLayout: NotificationLayout.Default,
            category: NotificationCategory.Reminder,
            icon: 'resource://drawable/notification_bar_icon',
          ),
        );
        await prefs.setInt(uniqueKey, count);
      }
      // 2. Stok Düşükse (ve 1 değilse)
      else if (count < dailyDose && count > 1) {
        // DÜZELTME: Manuel replace
        String bodyText = "low_stock_body".tr()
            .replaceAll("{0}", medName)
            .replaceAll("{}", medName);

        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: notifId,
            channelKey: 'stock_warning_channel',
            title: "low_stock_title".tr(),
            body: bodyText,
            notificationLayout: NotificationLayout.Default,
            category: NotificationCategory.Recommendation,
          ),
        );
        await prefs.setInt(uniqueKey, count);
      }
    }
  }

  // --- Planlama Motoru ---
  Future<void> scheduleMedicationNotifications(BuildContext context, List<Map<String, dynamic>> sections, String macAddress) async {
    final settings = await getNotificationSettings();
    final bool alarmsOn = settings['alarms_enabled'];
    final bool notesOn = settings['notifications_enabled'];
    final int offsetMinutes = settings['offset'];

    await Alarm.stopAll();
    await AwesomeNotifications().cancelAllSchedules();
    await checkStockAndNotify(sections, macAddress);

    if (!alarmsOn && !notesOn) return;

    String currentLang = context.locale.languageCode;
    String soundPath = (currentLang == 'tr') ? 'assets/alarms/alarm_tr.mp3' : 'assets/alarms/alarm_en.mp3';

    int idCounter = 1000;

    // --- 1. ADIM: İlaçları Zamana Göre Grupla ---
    Map<String, List<Map<String, dynamic>>> groupedAlarms = {};

    for (int i = 0; i < sections.length; i++) {
      var section = sections[i];
      if (section['isActive'] != true) continue;

      final String medName = section['name'] ?? "medicine".tr();
      final List<TimeOfDay> times = List<TimeOfDay>.from(section['times'] ?? []);

      for (var t in times) {
        String timeKey = "${t.hour}:${t.minute}";
        if (!groupedAlarms.containsKey(timeKey)) {
          groupedAlarms[timeKey] = [];
        }
        groupedAlarms[timeKey]!.add({
          'sectionIndex': i,
          'name': medName,
          'time': t,
        });
      }
    }

    // --- 2. ADIM: Gruplanmış Alarmları Kur ---
    for (var entry in groupedAlarms.entries) {
      List<Map<String, dynamic>> items = entry.value;

      TimeOfDay t = items.first['time'] as TimeOfDay;
      final now = DateTime.now();
      DateTime baseTime = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      if (baseTime.isBefore(now)) {
        baseTime = baseTime.add(const Duration(days: 1));
      }

      List<String> allMedNames = items.map((e) => e['name'] as String).toList();
      List<int> allIndices = items.map((e) => e['sectionIndex'] as int).toList();

      String bodyText = allMedNames.join(", ");

      // --- ANA ALARM ---
      if (alarmsOn) {
        int alarmId = idCounter++;

        await _saveAlarmMetadata(alarmId, macAddress, allIndices, allMedNames);

        // DÜZELTME: Manuel replace
        String alarmBody = "medicine_time_body".tr()
            .replaceAll("{0}", bodyText)
            .replaceAll("{}", bodyText);

        final alarmSettings = AlarmSettings(
          id: alarmId,
          dateTime: baseTime,
          assetAudioPath: soundPath,
          loopAudio: true,
          vibrate: true,
          volume: 1.0,
          fadeDuration: 3.0,
          androidFullScreenIntent: true,
          notificationSettings: NotificationSettings(
            title: "medicine_time_title".tr(),
            body: alarmBody,
            stopButton: "stop_alarm".tr(),
            icon: 'notification_bar_icon',
          ),
        );
        await Alarm.set(alarmSettings: alarmSettings);
      }

      // --- ÖN BİLDİRİM ---
      if (notesOn && offsetMinutes > 0) {
        final DateTime noteTime = baseTime.subtract(Duration(minutes: offsetMinutes));
        if (noteTime.isAfter(DateTime.now())) {

          // DÜZELTME: Manuel replace ile argümanları yerleştirme
          String notifBody = "minutes_before_desc".tr()
              .replaceAll("{0}", offsetMinutes.toString())
              .replaceAll("{1}", bodyText)
              .replaceAll("{}", offsetMinutes.toString()); // Yedek

          await AwesomeNotifications().createNotification(
            content: NotificationContent(
              id: idCounter++,
              channelKey: 'reminder_channel',
              title: "pre_notification_title".tr(),
              body: notifBody,
              notificationLayout: NotificationLayout.Default,
              category: NotificationCategory.Reminder,
              wakeUpScreen: true,
            ),
            schedule: NotificationCalendar.fromDate(date: noteTime),
          );
        }
      }
    }
    debugPrint("Planlama Tamamlandı. Oluşturulan alarm grubu sayısı: ${groupedAlarms.length}");
  }
}