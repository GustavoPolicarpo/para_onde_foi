package com.gastoclaro.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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
            budgetStatus: String,
            budgetProgress: Int,
            hasBudget: Boolean
        ) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
                .putString("month", month)
                .putString("amount", amount)
                .putString("budget_status", budgetStatus)
                .putInt("budget_progress", budgetProgress.coerceIn(0, 100))
                .putBoolean("has_budget", hasBudget)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, QuickEntryWidgetProvider::class.java)
            )
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
            val hasBudget = preferences.getBoolean("has_budget", false)
            views.setTextViewText(
                R.id.widget_month_label,
                if (month.isBlank()) "GASTOS DO MÊS" else "GASTOS EM $month"
            )
            views.setTextViewText(
                R.id.widget_total,
                preferences.getString("amount", "R$ 0,00") ?: "R$ 0,00"
            )
            val budgetStatus = preferences.getString(
                "budget_status",
                "Abra o app para atualizar seus dados"
            ) ?: ""
            views.setTextViewText(R.id.widget_budget_status, budgetStatus)
            views.setTextColor(
                R.id.widget_budget_status,
                if (budgetStatus.contains("acima dos limites")) 0xFFB43D36.toInt()
                else 0xFF53635A.toInt()
            )
            views.setViewVisibility(
                R.id.widget_budget_progress,
                if (hasBudget) android.view.View.VISIBLE else android.view.View.GONE
            )
            views.setProgressBar(
                R.id.widget_budget_progress,
                100,
                preferences.getInt("budget_progress", 0),
                false
            )
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
