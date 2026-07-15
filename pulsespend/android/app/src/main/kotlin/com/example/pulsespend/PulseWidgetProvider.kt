package com.example.pulsespend

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Renders the PulseSpend home widget from values the Flutter side saves via
 * the home_widget plugin (HomeWidgetService.update): `balance`, `month_spend`.
 * Tapping the widget opens the app.
 */
class PulseWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.pulse_widget).apply {
                setTextViewText(R.id.widget_balance, widgetData.getString("balance", "—"))
                setTextViewText(R.id.widget_spend, widgetData.getString("month_spend", ""))

                val launchIntent: PendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                )
                setOnClickPendingIntent(R.id.widget_title, launchIntent)
                setOnClickPendingIntent(R.id.widget_balance, launchIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
