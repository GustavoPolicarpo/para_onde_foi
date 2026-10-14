package com.gastoclaro.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

class QuickEntryWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_PREVIOUS_MONTH && intent.action != ACTION_NEXT_MONTH) return
        val manager = AppWidgetManager.getInstance(context)
        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        )
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            changeMonth(
                context,
                manager,
                appWidgetId,
                if (intent.action == ACTION_PREVIOUS_MONTH) -1 else 1
            )
        }
    }

    companion object {
        private const val PREFERENCES = "quick_entry_widget"
        private const val ACTION_PREVIOUS_MONTH = "com.gastoclaro.app.PREVIOUS_MONTH"
        private const val ACTION_NEXT_MONTH = "com.gastoclaro.app.NEXT_MONTH"
        private const val EXPANDED_HEIGHT_DP = 110

        fun updateSummary(context: Context, monthsJson: String) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            preferences.edit().putString("months", monthsJson).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, QuickEntryWidgetProvider::class.java)
            )
            ids.forEach { updateWidget(context, manager, it) }
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_budgets)
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val months = parseMonths(preferences.getString("months", "[]"))
            val selectionKey = "month_key_$appWidgetId"
            val selectedKey = preferences.getString(selectionKey, null)
            val selectedIndex = findMonthIndex(months, selectedKey)
            val month = months.optJSONObject(selectedIndex) ?: JSONObject()
            val monthKey = month.optString("key")
            val budgets = month.optJSONArray("budgets") ?: JSONArray()
            preferences.edit()
                .putString(selectionKey, monthKey)
                .putString("budgets_$appWidgetId", budgets.toString())
                .apply()

            val views = RemoteViews(context.packageName, R.layout.widget_quick_entry)
            views.setTextViewText(R.id.widget_month_label, month.optString("label", "MÊS"))
            views.setTextViewText(R.id.widget_total, month.optString("amount", "R$ 0,00"))

            val options = manager.getAppWidgetOptions(appWidgetId)
            val minHeight = options.getInt(
                AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
                50
            )
            val expanded = minHeight >= EXPANDED_HEIGHT_DP
            views.setViewVisibility(
                R.id.widget_budgets,
                if (expanded) View.VISIBLE else View.GONE
            )
            views.setViewVisibility(
                R.id.widget_budget_empty,
                if (expanded && budgets.length() == 0) View.VISIBLE else View.GONE
            )

            val serviceIntent = Intent(context, WidgetBudgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_budgets, serviceIntent)
            views.setEmptyView(R.id.widget_budgets, R.id.widget_budget_empty)
            views.setPendingIntentTemplate(
                R.id.widget_budgets,
                budgetPagePendingIntent(context, appWidgetId)
            )
            views.setOnClickPendingIntent(
                R.id.widget_root,
                openAppPendingIntent(context, appWidgetId)
            )
            views.setOnClickPendingIntent(
                R.id.widget_month_previous,
                monthPendingIntent(context, appWidgetId, ACTION_PREVIOUS_MONTH, 0)
            )
            views.setOnClickPendingIntent(
                R.id.widget_month_next,
                monthPendingIntent(context, appWidgetId, ACTION_NEXT_MONTH, 1)
            )
            views.setViewVisibility(
                R.id.widget_month_previous,
                if (selectedIndex > 0) View.VISIBLE else View.INVISIBLE
            )
            views.setViewVisibility(
                R.id.widget_month_next,
                if (selectedIndex < months.length() - 1) View.VISIBLE else View.INVISIBLE
            )
            views.setOnClickPendingIntent(
                R.id.widget_expense_button,
                createPendingIntent(context, appWidgetId)
            )
            manager.updateAppWidget(appWidgetId, views)
        }

        private fun changeMonth(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            direction: Int
        ) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val months = parseMonths(preferences.getString("months", "[]"))
            if (months.length() == 0) return
            val key = "month_key_$appWidgetId"
            val current = findMonthIndex(months, preferences.getString(key, null))
            val nextIndex = (current + direction).coerceIn(0, months.length() - 1)
            val next = months.optJSONObject(nextIndex) ?: return
            preferences.edit().putString(key, next.optString("key")).apply()
            updateWidget(context, manager, appWidgetId)
            manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_budgets)
        }

        private fun parseMonths(raw: String?): JSONArray = try {
            JSONArray(raw ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }

        private fun findMonthIndex(months: JSONArray, key: String?): Int {
            if (months.length() == 0) return -1
            if (!key.isNullOrBlank()) {
                for (index in 0 until months.length()) {
                    if (months.optJSONObject(index)?.optString("key") == key) return index
                }
            }
            for (index in 0 until months.length()) {
                if (months.optJSONObject(index)?.optBoolean("current") == true) return index
            }
            return months.length() - 1
        }

        private fun monthPendingIntent(
            context: Context,
            appWidgetId: Int,
            action: String,
            offset: Int
        ): PendingIntent {
            val intent = Intent(context, QuickEntryWidgetProvider::class.java).apply {
                this.action = action
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse("gastoclaro://widget/month/$appWidgetId/$offset")
            }
            return PendingIntent.getBroadcast(
                context,
                appWidgetId * 10 + offset + 1,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun createPendingIntent(
            context: Context,
            appWidgetId: Int
        ): PendingIntent {
            val intent = Intent(context, QuickEntryActivity::class.java).apply {
                putExtra(MainActivity.EXTRA_WIDGET_QUICK_ENTRY, true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK
            }
            return PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun openAppPendingIntent(
            context: Context,
            appWidgetId: Int
        ): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                10000 + appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun budgetPagePendingIntent(
            context: Context,
            appWidgetId: Int
        ): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                putExtra(MainActivity.EXTRA_WIDGET_BUDGETS, true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                20000 + appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
        }
    }
}
