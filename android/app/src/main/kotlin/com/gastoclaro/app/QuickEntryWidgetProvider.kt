package com.gastoclaro.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import java.util.Locale

class QuickEntryWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
    }

    companion object {
        private const val PREFERENCES = "quick_entry_widget"

        fun updateSummary(
            context: Context,
            month: String,
            amount: String,
            budgetsJson: String
        ) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
                .putString("month", month)
                .putString("amount", amount)
                .putString("budgets", budgetsJson)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, QuickEntryWidgetProvider::class.java)
            )
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_budgets)
            ids.forEach { updateWidget(context, manager, it) }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_quick_entry)
            val month = preferences.getString("month", "")?.uppercase(Locale("pt", "BR"))
                ?: ""
            views.setTextViewText(
                R.id.widget_month_label,
                if (month.isBlank()) "GASTOS DO MÊS" else "GASTOS EM $month"
            )
            views.setTextViewText(
                R.id.widget_total,
                preferences.getString("amount", "R$ 0,00") ?: "R$ 0,00"
            )
            val budgets = preferences.getString("budgets", "[]") ?: "[]"
            val hasBudgets = budgets != "[]"
            views.setViewVisibility(
                R.id.widget_budget_empty,
                if (hasBudgets) android.view.View.GONE else android.view.View.VISIBLE
            )
            val serviceIntent = Intent(context, WidgetBudgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_budgets, serviceIntent)
            views.setEmptyView(R.id.widget_budgets, R.id.widget_budget_empty)
            views.setOnClickPendingIntent(
                R.id.widget_expense_button,
                createPendingIntent(context, appWidgetId)
            )
            manager.updateAppWidget(appWidgetId, views)
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
    }
}
