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
                "updateWidgetSummary" -> {
                    QuickEntryWidgetProvider.updateSummary(
                        this,
                        call.argument<String>("month") ?: "",
                        call.argument<String>("amount") ?: "R$ 0,00",
                        call.argument<String>("budgets") ?: "[]"
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
    }

    companion object {
        const val EXTRA_WIDGET_QUICK_ENTRY = "widget_quick_entry"
    }
}
