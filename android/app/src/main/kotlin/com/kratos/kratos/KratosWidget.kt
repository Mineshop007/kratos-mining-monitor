package com.kratos.kratos

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.kratos.miningmonitor.MainActivity
import es.antonborri.home_widget.HomeWidgetProvider

class KratosWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val layoutId = context.resources.getIdentifier(
                "kratos_widget", "layout", context.packageName)
            val views = RemoteViews(context.packageName, layoutId)

            // Tap anywhere → open app
            val launchIntent = Intent(context, MainActivity::class.java)
            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            val pendingIntent = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val rootId = context.resources.getIdentifier(
                "widget_root", "id", context.packageName)
            views.setOnClickPendingIntent(rootId, pendingIntent)

            fun id(n: String) = context.resources
                .getIdentifier(n, "id", context.packageName)

            views.setTextViewText(id("widget_hashrate"),
                widgetData.getString("hashrate", "-- GH/s") ?: "-- GH/s")
            views.setTextViewText(id("widget_online"),
                widgetData.getString("online", "--") ?: "--")
            views.setTextViewText(id("widget_offline"),
                widgetData.getString("offline", "--") ?: "--")
            views.setTextViewText(id("widget_best_share"),
                widgetData.getString("bestShare", "--") ?: "--")
            views.setTextViewText(id("widget_updated"),
                widgetData.getString("updated", "--:--") ?: "--:--")

            val offlineCount = (widgetData.getString("offline", "0") ?: "0")
                .toIntOrNull() ?: 0
            views.setTextColor(id("widget_offline"),
                if (offlineCount > 0)
                    android.graphics.Color.parseColor("#FF4A4A")
                else
                    android.graphics.Color.parseColor("#4A4A6A"))

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
