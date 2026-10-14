package com.gastoclaro.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var widgetChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gasto_claro/widget"
        )
        widgetChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialQuickEntry" -> {
                    result.success(intent?.getBooleanExtra(EXTRA_WIDGET_QUICK_ENTRY, false) == true)
                    intent?.removeExtra(EXTRA_WIDGET_QUICK_ENTRY)
                }
                "getInitialBudgetPage" -> {
                    result.success(intent?.getBooleanExtra(EXTRA_WIDGET_BUDGETS, false) == true)
                    intent?.removeExtra(EXTRA_WIDGET_BUDGETS)
                }
                "updateWidgetSummary" -> {
                    QuickEntryWidgetProvider.updateSummary(
                        this,
                        call.argument<String>("months") ?: "[]"
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(EXTRA_WIDGET_QUICK_ENTRY, false)) {
            widgetChannel?.invokeMethod("openEntry", null)
            intent.removeExtra(EXTRA_WIDGET_QUICK_ENTRY)
        }
        if (intent.getBooleanExtra(EXTRA_WIDGET_BUDGETS, false)) {
            widgetChannel?.invokeMethod("openBudgets", null)
            intent.removeExtra(EXTRA_WIDGET_BUDGETS)
        }
    }

    companion object {
        const val EXTRA_WIDGET_QUICK_ENTRY = "widget_quick_entry"
        const val EXTRA_WIDGET_BUDGETS = "widget_open_budgets"
    }
}
