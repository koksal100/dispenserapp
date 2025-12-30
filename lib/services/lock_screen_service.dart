import 'package:flutter/services.dart';

class LockScreenService {
  static const platform = MethodChannel('com.example.dispenserapp/lock_control');

  // Alarm Çalarken Çağıracağız
  static Future<void> showOnLockScreen() async {
    try {
      await platform.invokeMethod('showOnLockScreen');
    } catch (e) {
      print("Lock Screen Error: $e");
    }
  }

  // Alarm Durunca veya Uygulama Başlarken Çağıracağız
  static Future<void> hideFromLockScreen() async {
    try {
      await platform.invokeMethod('hideFromLockScreen');
    } catch (e) {
      print("Lock Screen Error: $e");
    }
  }
}