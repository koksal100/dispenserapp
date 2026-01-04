# Flutter Core
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugins.** { *; }

# Alarm Plugin - KRİTİK
-keep class com.gdelataillade.alarm.** { *; }
-keepclassmembers class com.gdelataillade.alarm.** { *; }
-dontwarn com.gdelataillade.alarm.**

# Awesome Notifications
-keep class me.carda.awesome_notifications.** { *; }
-dontwarn me.carda.awesome_notifications.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Kotlin Coroutines
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# WorkManager
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# Serialization
-keepattributes Signature
-keepattributes *Annotation*