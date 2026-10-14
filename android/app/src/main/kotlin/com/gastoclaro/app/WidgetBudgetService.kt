package com.gastoclaro.app

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class WidgetBudgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        return BudgetRemoteViewsFactory(applicationContext, appWidgetId)
    }
}

private class BudgetRemoteViewsFactory(
    private val context: android.content.Context,
    private val appWidgetId: Int
) : RemoteViewsService.RemoteViewsFactory {
    private var rows = JSONArray()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val raw = context.getSharedPreferences("quick_entry_widget", 0)
            .getString("budgets_$appWidgetId", "[]") ?: "[]"
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
        val hasLimit = row.optBoolean("hasLimit", true)
        views.setTextViewText(R.id.widget_budget_category, row.optString("label"))
        views.setTextViewText(
            R.id.widget_budget_amount,
            if (hasLimit) {
                "${row.optString("spent")} / ${row.optString("limit")}"
            } else {
                "${row.optString("spent")} · sem limite"
            }
        )
        views.setTextColor(
            R.id.widget_budget_amount,
            if (over) 0xFFB43D36.toInt() else 0xFF53635A.toInt()
        )
        views.setTextViewText(R.id.widget_budget_remaining, row.optString("remaining"))
        views.setTextColor(
            R.id.widget_budget_remaining,
            if (row.optBoolean("remainingOver", false)) 0xFFB43D36.toInt()
            else 0xFF6B756E.toInt()
        )
        views.setProgressBar(
            R.id.widget_budget_row_progress,
            100,
            row.optInt("progress", 0).coerceIn(0, 100),
            false
        )
        views.setViewVisibility(
            R.id.widget_budget_row_progress,
            if (hasLimit) View.VISIBLE else View.GONE
        )
        val fillInIntent = Intent().putExtra(MainActivity.EXTRA_WIDGET_BUDGETS, true)
        views.setOnClickFillInIntent(R.id.widget_budget_item_root, fillInIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
}
