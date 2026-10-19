package com.ahimismito.rey_cagon

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * Widget de ranking de la semana: tu puesto y quién va justo arriba y abajo (entre los que sigues).
 * Dart escribe `rk` (JSON [{p, n, t, yo}]) y `rk_hora` en lib/widget.dart → refrescarRanking().
 */
class ReyCagonRankingWidget : HomeWidgetProvider() {
    private val filas = listOf(
        Triple(R.id.rk_fila0, R.id.rk_pos0, Pair(R.id.rk_nombre0, R.id.rk_total0)),
        Triple(R.id.rk_fila1, R.id.rk_pos1, Pair(R.id.rk_nombre1, R.id.rk_total1)),
        Triple(R.id.rk_fila2, R.id.rk_pos2, Pair(R.id.rk_nombre2, R.id.rk_total2)),
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val datos = try {
            JSONArray(widgetData.getString("rk", "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        val hora = widgetData.getString("rk_hora", null)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_ranking)
            views.setTextViewText(R.id.rk_titulo, if (hora == null) "RANKING · SEMANA" else "RANKING · SEMANA · $hora")
            views.setViewVisibility(R.id.rk_vacio, if (datos.length() == 0) View.VISIBLE else View.GONE)
            filas.forEachIndexed { i, (fila, pos, nombreTotal) ->
                if (i < datos.length()) {
                    val f = datos.getJSONObject(i)
                    val yo = f.optBoolean("yo")
                    views.setViewVisibility(fila, View.VISIBLE)
                    views.setInt(fila, "setBackgroundResource", if (yo) R.drawable.widget_fila_yo else R.drawable.widget_fila)
                    views.setTextViewText(pos, String.format("%02d", f.optInt("p")))
                    views.setTextViewText(nombreTotal.first, if (yo) "${f.optString("n")} (tú)" else f.optString("n"))
                    views.setTextViewText(nombreTotal.second, f.optInt("t").toString())
                } else {
                    views.setViewVisibility(fila, View.GONE)
                }
            }
            views.setOnClickPendingIntent(R.id.rk_raiz, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
