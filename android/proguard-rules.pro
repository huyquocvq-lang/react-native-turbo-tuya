# Keep rules cho Tuya Smart Life App SDK (consumer proguard - merge vào app).
# Theo docs/research/tuya-m1-sdk-foundation.md.
-keep class com.thingclips.**{*;}
-dontwarn com.thingclips.**

# FastJSON
-keep class com.alibaba.fastjson.**{*;}
-dontwarn com.alibaba.fastjson.**

# MQTT
-keep class org.eclipse.paho.**{*;}
-dontwarn org.eclipse.paho.**

# OkHttp / Okio
-keep class okhttp3.**{*;}
-keep class okio.**{*;}
-dontwarn okhttp3.**
-dontwarn okio.**

# Không obfuscate Matter SDK & Mini SDK (theo doc Tuya)
-keep class com.thingclips.matter.**{*;}
-keep class com.thingclips.smart.mini.**{*;}
