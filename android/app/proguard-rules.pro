# ==============================================================================
# 1. 解决 Google Play 动态分发组件缺失导致的 R8 报错 (核心修复 ⚠️)
# ==============================================================================
# 告诉编译系统：忽略 Flutter 底层对谷歌应用商店（Google Play Core）的缺失警告
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.gms.common.annotation.NoNullnessRewrite


# ==============================================================================
# 2. Flutter 引擎与核心类保留
# ==============================================================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }


# ==============================================================================
# 3. 第三方依赖库混淆保留 (OkHttp 与 Kotlin)
# ==============================================================================
# OkHttp 3 / 4 混淆规则
-keepattributes Signature
-keepattributes *Annotation*
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**

# 保持 Kotlin 标准库不被混淆
-keep class kotlin.** { *; }
-dontwarn kotlin.**