package com.gastoclaro.app

import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class QuickEntryActivity : FlutterActivity() {
    private var quickEntryChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        quickEntryChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gasto_claro/widget"
        )
        quickEntryChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialQuickEntry" -> result.success(true)
                "finishQuickEntry" -> {
                    val saved = call.arguments as? Boolean ?: false
                    if (saved) {
                        Toast.makeText(this, "Lançamento salvo", Toast.LENGTH_SHORT).show()
                    }
                    result.success(null)
                    finish()
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
}
