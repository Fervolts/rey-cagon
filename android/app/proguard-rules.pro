# shared_preferences_android usa estas clases por JNI con firmas exactas. Si R8 las borra o
# renombra, la app se cuelga al arrancar en release.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.** { *; }
