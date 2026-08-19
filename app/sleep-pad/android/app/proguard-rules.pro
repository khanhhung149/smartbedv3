# Flutter-specific ProGuard rules

# Keep Flutter's core classes to prevent them from being removed or obfuscated
#-keep class io.flutter.app.** { *; }
#-keep class io.flutter.embedding.** { *; }
#-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# Keep custom plugins if any, replace `yourapp` with your package name
#-keep class com.plugilo.plugilo.** { *; }

# Androidx libraries (general rule for modern Android projects)
-dontwarn androidx.**

# Firebase and Google Play Services (add only if your app uses Firebase or Google Play services)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Keep public classes and interfaces that extend Activity (Flutter requires this)
-keep public class * extends android.app.Activity

# JSON and Serialization Libraries

# Gson library (if using Gson for JSON parsing)
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# JSON library (if using Android's built-in org.json library)
-keep class org.json.** { *; }

# Retrofit and OkHttp (if using these for network calls)
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }
-dontwarn retrofit2.**
-dontwarn okhttp3.**

# WorkManager (required if using WorkManager library)
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# Coroutine Rules (if using Kotlin coroutines)
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# General Rules to Avoid Removing Reflection-Based Methods

# Keep annotations
-keepattributes *Annotation*

# Preserve generic types
-keepattributes Signature

# Preserve inner class references
-keepattributes InnerClasses

# Preserve methods called by reflection
-keepattributes EnclosingMethod

# Keep all model classes if they are serialized/deserialized, replace `yourapp.models` with your models' package
#-keep class com.plugilo.plugilo.models.** { *; }

# Android parcelable classes (important for passing data between activities/fragments)
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
# Avoid stripping resource IDs used in layouts
-keepclassmembers class * extends android.view.View {
   public <init>(android.content.Context);
   public <init>(android.content.Context, android.util.AttributeSet);
   public <init>(android.content.Context, android.util.AttributeSet, int);
   void set*(***);
   void get*(***);
}

# Additional configurations for any third-party libraries
# If you encounter warnings for any specific library, add similar `-keep` and `-dontwarn` rules here.

