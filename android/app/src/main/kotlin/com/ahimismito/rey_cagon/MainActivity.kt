package com.ahimismito.rey_cagon

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_EQUIPO).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> result.success(infoEquipo())
                    // Por qué se cerraron los procesos anteriores (Android 11+), los más nuevos primero.
                    "salidas" -> result.success(salidas())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("equipo", e.message, null)
            }
        }
    }

    private fun gestor() = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

    private fun infoEquipo(): Map<String, Any?> {
        val am = gestor()
        val mem = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mem)
        val rt = Runtime.getRuntime()
        return mapOf(
            "modelo" to Build.MODEL,
            "marca" to Build.MANUFACTURER,
            "sdk" to Build.VERSION.SDK_INT,
            "ram_baja" to am.isLowRamDevice,
            "clase_mb" to am.memoryClass,
            "clase_grande_mb" to am.largeMemoryClass,
            "ram_mb" to mem.totalMem / MB,
            "libre_mb" to mem.availMem / MB,
            "umbral_mb" to mem.threshold / MB,
            "memoria_baja" to mem.lowMemory,
            "java_usada_mb" to (rt.totalMemory() - rt.freeMemory()) / MB,
            "java_max_mb" to rt.maxMemory() / MB,
            "nativa_mb" to android.os.Debug.getNativeHeapAllocatedSize() / MB,
        )
    }

    private fun salidas(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return gestor().getHistoricalProcessExitReasons(packageName, 0, 5).map {
            mapOf(
                "razon" to razon(it.reason),
                "descripcion" to it.description,
                "importancia" to it.importance,
                "pss_mb" to it.pss / 1024,
                "rss_mb" to it.rss / 1024,
                "cuando" to it.timestamp,
                "estado" to it.status,
            )
        }
    }

    private fun razon(r: Int): String = when (r) {
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_nativo"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependencia"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "exceso_recursos"
        ApplicationExitInfo.REASON_EXIT_SELF -> "salio_solo"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "fallo_inicio"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "poca_memoria"
        ApplicationExitInfo.REASON_OTHER -> "otro"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permiso"
        ApplicationExitInfo.REASON_SIGNALED -> "senal"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "usuario"
        ApplicationExitInfo.REASON_USER_STOPPED -> "usuario_detuvo"
        else -> "codigo_$r"
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
        const val CANAL_EQUIPO = "rey_cagon/equipo"
        const val MB = 1024L * 1024L
        val ALIAS = listOf("Normal", "Dorado", "Corona", "Noche", "Cloaca")
    }
}
