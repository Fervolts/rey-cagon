package com.ahimismito.rey_cagon

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * Widget de ranking semanal (entre los que sigues): puesto, cuánto falta para subir y vecinos.
 * Los datos (`rk`, `rk_puesto`, `rk_de`, `rk_frase`, `rk_rey`) los escribe lib/widget.dart.
 * El ícono de la esquina registra una cagada sin abrir la app.
 * [ReyCagonRankingGlobalWidget] es el mismo widget con el ranking de todos (claves `rkg…`).
 */
open class ReyCagonRankingWidget : HomeWidgetProvider() {
    protected open val prefijo = "rk"

    private val filas = listOf(
        listOf(R.id.rk_fila0, R.id.rk_pos0, R.id.rk_nombre0, R.id.rk_total0),
        listOf(R.id.rk_fila1, R.id.rk_pos1, R.id.rk_nombre1, R.id.rk_total1),
        listOf(R.id.rk_fila2, R.id.rk_pos2, R.id.rk_nombre2, R.id.rk_total2),
        listOf(R.id.rk_fila3, R.id.rk_pos3, R.id.rk_nombre3, R.id.rk_total3),
        listOf(R.id.rk_fila4, R.id.rk_pos4, R.id.rk_nombre4, R.id.rk_total4),
        listOf(R.id.rk_fila5, R.id.rk_pos5, R.id.rk_nombre5, R.id.rk_total5),
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val datos = try {
            JSONArray(widgetData.getString(prefijo, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        val rey = widgetData.getBoolean("${prefijo}_rey", false)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_ranking)
            views.setTextViewText(R.id.rk_puesto, widgetData.getString("${prefijo}_puesto", "--"))
            views.setTextViewText(R.id.rk_de, widgetData.getString("${prefijo}_de", null) ?: context.getString(R.string.widget_semana))
            views.setTextViewText(R.id.rk_frase, widgetData.getString("${prefijo}_frase", null) ?: context.getString(R.string.widget_abrir))
            views.setImageViewResource(R.id.rk_icono, if (rey) R.drawable.widget_corona else R.drawable.widget_poop)

            filas.forEachIndexed { i, (fila, pos, nombre, total) ->
                if (i < datos.length()) {
                    val f = datos.getJSONObject(i)
                    val yo = f.optBoolean("yo")
                    val color = if (yo) 0xFFFFD60A.toInt() else 0xFFF2F0EC.toInt()
                    views.setViewVisibility(fila, View.VISIBLE)
                    views.setTextViewText(pos, String.format("%02d", f.optInt("p")))
                    views.setTextViewText(nombre, if (yo) context.getString(R.string.widget_tu, f.optString("n")) else f.optString("n"))
                    views.setTextViewText(total, f.optInt("t").toString())
                    views.setTextColor(nombre, color)
                    views.setTextColor(total, color)
                } else {
                    views.setViewVisibility(fila, View.GONE)
                }
            }
            views.setOnClickPendingIntent(R.id.rk_raiz, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            views.setOnClickPendingIntent(
                R.id.rk_icono,
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("reycagon://cague")),
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
