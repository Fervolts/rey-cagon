package com.ahimismito.rey_cagon

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.ZoneId

/**
 * Widget con el botón de registrar y el contador del día.
 * El botón llama al callback Dart `widgetCague` (lib/widget.dart); el contador abre la app.
 */
class ReyCagonWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // El contador es del día en que se guardó: al cambiar de día vuelve a 0 sin abrir la app.
        val hoy = LocalDate.now(ZoneId.of("America/Caracas")).toString()
        val cuenta = if (widgetData.getString("fecha", null) == hoy) widgetData.getString("hoy", "0") else "0"
        val estado = widgetData.getString("estado", null) ?: context.getString(R.string.widget_hoy, cuenta)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_cague).apply {
                setTextViewText(R.id.widget_estado, estado)
                setOnClickPendingIntent(
                    R.id.widget_boton,
                    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("reycagon://cague")),
                )
                setOnClickPendingIntent(
                    R.id.widget_estado,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
