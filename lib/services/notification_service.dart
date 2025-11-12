import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _notificationOffsetKey = 'notification_offset';

  static Future<void> initializeNotifications() async {
    await AwesomeNotifications().initialize(
      null, // Varsayılan uygulama ikonunu kullan
      [
        NotificationChannel(
          channelGroupKey: 'scheduled_channel_group',
          channelKey: 'scheduled_channel',
          channelName: 'Scheduled Notifications',
          channelDescription: 'Notification channel for scheduled reminders.',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
        ),
      ],
      channelGroups: [
        NotificationChannelGroup(
          channelGroupKey: 'scheduled_channel_group',
          channelGroupName: 'Scheduled Group',
        )
      ],
      debug: true, // Enable debug prints
    );
  }

  static Future<void> requestPermission() async {
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }
  }

  Future<void> scheduleMedicationNotifications(
    List<Map<String, dynamic>> sections,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final bool notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? false;
    final int offsetMinutes = prefs.getInt(_notificationOffsetKey) ?? 0;

    await AwesomeNotifications().cancelAllSchedules();

    if (!notificationsEnabled) {
      return;
    }

    for (int i = 0; i < sections.length; i++) {
      final section = sections[i];
      final bool isActive = section['isActive'] ?? false;

      if (isActive) {
        final TimeOfDay time = section['time'];
        final String name = section['name'];
        final DateTime now = DateTime.now();

        // Calculate the notification time with the offset
        DateTime notificationTime = DateTime(now.year, now.month, now.day, time.hour, time.minute)
            .subtract(Duration(minutes: offsetMinutes));

        // If the calculated time is in the past for today, schedule it for tomorrow
        if (notificationTime.isBefore(now)) {
          notificationTime = notificationTime.add(const Duration(days: 1));
        }

        await AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: i, // Unique ID for each notification
            channelKey: 'scheduled_channel',
            title: 'İlaç Zamanı Yaklaşıyor!',
            body: '$name ilacınızı alma zamanı geldi.',
            notificationLayout: NotificationLayout.Default,
          ),
          schedule: NotificationCalendar(
            year: notificationTime.year,
            month: notificationTime.month,
            day: notificationTime.day,
            hour: notificationTime.hour,
            minute: notificationTime.minute,
            second: 0,
            millisecond: 0,
            repeats: true, // Repeat the notification daily
          ),
        );
      }
    }
  }

  Future<void> cancelAllNotifications() async {
    await AwesomeNotifications().cancelAllSchedules();
  }


  Future<void> saveNotificationSettings({required bool enabled, required int offset}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
    await prefs.setInt(_notificationOffsetKey, offset);
  }

  Future<Map<String, dynamic>> getNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool(_notificationsEnabledKey) ?? false,
      'offset': prefs.getInt(_notificationOffsetKey) ?? 0,
    };
  }
}
