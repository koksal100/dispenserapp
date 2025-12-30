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

  // --- BAŞLATMA ---
  static Future<void> initializeNotifications() async {
    // 1. Alarm Paketini Başlat
    await Alarm.init();

    // 2. Awesome Notifications Başlat (Ön Bildirimler İçin)
    await AwesomeNotifications().initialize(
      'resource://drawable/notification_bar_icon', // drawable klasöründeki ikon
      [
        NotificationChannel(
          channelKey: 'reminder_channel',
          channelName: 'Medicine Reminders',
          channelDescription: 'Pre-notifications for medicine',
          defaultColor: const Color(0xFF1D8AD6),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          // playSound: true, // Varsayılan bildirim sesi
          // criticalAlerts: false, // Bu sadece bir hatırlatıcı, alarm değil
        )
      ],
      debug: true,
    );
  }

  // --- İZİN İSTEME (PermissionsScreen tarafından çağrılır) ---
  static Future<void> requestPermission() async {
    // Awesome Notifications İzni
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }

    if (Platform.isAndroid) {
      // Alarm ve Kilit Ekranı İzinleri
      await Permission.scheduleExactAlarm.request();
      await Permission.systemAlertWindow.request(); // Alarmın kilit ekranını açması için şart

      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  // --- AYARLARI KAYDET ---
  Future<void> saveNotificationSettings({required bool alarmsEnabled, required bool notificationsEnabled, required int offset}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alarmsEnabledKey, alarmsEnabled);
    await prefs.setBool(_notificationsEnabledKey, notificationsEnabled);
    await prefs.setInt(_notificationOffsetKey, offset);
  }

  // --- AYARLARI GETİR ---
  Future<Map<String, dynamic>> getNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'alarms_enabled': prefs.getBool(_alarmsEnabledKey) ?? true,
      'notifications_enabled': prefs.getBool(_notificationsEnabledKey) ?? true,
      'offset': prefs.getInt(_notificationOffsetKey) ?? 10,
    };
  }

  // --- PLANLAMA MOTORU ---
  Future<void> scheduleMedicationNotifications(BuildContext context, List<Map<String, dynamic>> sections) async {
    final settings = await getNotificationSettings();
    final bool alarmsOn = settings['alarms_enabled'];
    final bool notesOn = settings['notifications_enabled'];
    final int offsetMinutes = settings['offset'];

    // Temizlik: Çakışmaları önlemek için eskileri sil
    await Alarm.stopAll();
    await AwesomeNotifications().cancelAllSchedules();

    if (!alarmsOn && !notesOn) return;

    // Dil Ayarı
    String currentLang = context.locale.languageCode;
    String soundPath = (currentLang == 'tr') ? 'assets/alarms/alarm_tr.mp3' : 'assets/alarms/alarm_en.mp3';

    int idCounter = 1000;

    for (var section in sections) {
      if (section['isActive'] != true) continue;
      final String medName = section['name'] ?? "medicine".tr();
      final List<TimeOfDay> times = List<TimeOfDay>.from(section['times'] ?? []);

      for (var t in times) {
        final now = DateTime.now();
        DateTime baseTime = DateTime(now.year, now.month, now.day, t.hour, t.minute);

        // Eğer saat geçtiyse yarına kur
        if (baseTime.isBefore(now)) {
          baseTime = baseTime.add(const Duration(days: 1));
        }

        // --- A. ANA ALARM (Ekranı Açar, Sürekli Çalar) ---
        if (alarmsOn) {
          final alarmSettings = AlarmSettings(
            id: idCounter++,
            dateTime: baseTime,
            assetAudioPath: soundPath,
            loopAudio: true, // Sürekli çalar
            vibrate: true,
            volume: 1.0,
            fadeDuration: 3.0,
            androidFullScreenIntent: true, // EKRANI BU AÇAR
            notificationSettings: NotificationSettings(
              title: "medicine_time_title".tr(),
              body: "medicine_time_body".tr(args: [medName]),
              stopButton: "stop_alarm".tr(),
              icon: 'notification_bar_icon',
            ),
          );
          await Alarm.set(alarmSettings: alarmSettings);
        }

        // --- B. ÖN BİLDİRİM (Sadece Bildirim, Ekranı Açmaz, Susar) ---
        if (notesOn && offsetMinutes > 0) {
          final DateTime noteTime = baseTime.subtract(Duration(minutes: offsetMinutes));

          if (noteTime.isAfter(DateTime.now())) {
            await AwesomeNotifications().createNotification(
              content: NotificationContent(
                id: idCounter++,
                channelKey: 'reminder_channel',
                title: "pre_notification_title".tr(),
                body: "minutes_before_desc".tr(args: [offsetMinutes.toString(), medName]),
                notificationLayout: NotificationLayout.Default,
                category: NotificationCategory.Reminder, // Alarm DEĞİL, Hatırlatıcı
                wakeUpScreen: true, // Ekranı uyandırır ama kilit açmaz
              ),
              schedule: NotificationCalendar.fromDate(date: noteTime),
            );
          }
        }
      }
    }
    debugPrint("Planlama Tamamlandı. Alarm sayısı: ${idCounter - 1000}");
  }
}