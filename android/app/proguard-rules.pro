# shared_preferences_android llama a estos métodos por JNI con firmas exactas; si R8 los borra
# o renombra las clases de kotlin (Continuation, Result, ...) que usa el puente, la app se cuelga al arrancar en release.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.** { *; }
