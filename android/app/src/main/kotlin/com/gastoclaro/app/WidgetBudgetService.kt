package com.gastoclaro.app

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class WidgetBudgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        BudgetRemoteViewsFactory(applicationContext)
}

private class BudgetRemoteViewsFactory(
    private val context: android.content.Context
) : RemoteViewsService.RemoteViewsFactory {
    private var rows = JSONArray()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val raw = context.getSharedPreferences("quick_entry_widget", 0)
            .getString("budgets", "[]") ?: "[]"
        rows = try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    override fun onDestroy() = Unit

    override fun getCount(): Int = rows.length()

    override fun getViewAt(position: Int): RemoteViews? {
        if (position !in 0 until rows.length()) return null
        val row = rows.optJSONObject(position) ?: return null
        val views = RemoteViews(context.packageName, R.layout.widget_budget_item)
        val over = row.optBoolean("over", false)
        views.setTextViewText(R.id.widget_budget_category, row.optString("label"))
        views.setTextViewText(
            R.id.widget_budget_amount,
            "${row.optString("spent")} / ${row.optString("limit")}" 
        )
        views.setTextColor(
            R.id.widget_budget_amount,
            if (over) 0xFFB43D36.toInt() else 0xFF53635A.toInt()
        )
        views.setProgressBar(
            R.id.widget_budget_row_progress,
            100,
            row.optInt("progress", 0).coerceIn(0, 100),
            false
        )
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
}
