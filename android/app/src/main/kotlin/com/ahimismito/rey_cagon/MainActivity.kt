package com.ahimismito.rey_cagon

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // De extremo a extremo en todas las versiones, no solo en Android 15+ (lo que pide Play).
        // Flutter reparte los bordes del sistema con SafeArea y Scaffold.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_ICONO).setMethodCallHandler { call, result ->
            when (call.method) {
                // Prende el alias `alias` (por ejemplo "Dorado") y apaga los otros. Sin matar la app.
                "poner" -> {
                    val alias = call.arguments as? String
                    if (alias == null || alias !in ALIAS) {
                        result.error("alias", "alias desconocido", null)
                    } else {
                        try {
                            ponerIcono(alias)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("icono", e.message, null)
                        }
                    }
                }
                // El alias prendido ahora ("Normal" si no se sabe).
                "actual" -> result.success(iconoActual())
                else -> result.notImplemented()
            }
        }
    }

    private fun componente(alias: String) = ComponentName(this, "$packageName.Icono$alias")

    private fun iconoActual(): String =
        // Solo Normal está prendido en el manifest; los demás solo si MainActivity los prendió.
        ALIAS.firstOrNull {
            packageManager.getComponentEnabledSetting(componente(it)) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } ?: "Normal"

    private fun ponerIcono(alias: String) {
        // Primero prende el nuevo y después apaga los demás: así nunca se queda sin ícono de lanzador.
        packageManager.setComponentEnabledSetting(
            componente(alias), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP
        )
        for (a in ALIAS) if (a != alias) {
            packageManager.setComponentEnabledSetting(
                componente(a), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP
            )
        }
    }

    companion object {
        const val CANAL_ICONO = "rey_cagon/icono"
        val ALIAS = listOf("Normal", "Dorado", "Corona", "Noche", "Cloaca")
    }
}
