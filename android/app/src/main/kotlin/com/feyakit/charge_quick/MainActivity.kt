package com.feyakit.charge_quick

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val AD_SKIP_CHANNEL = "com.feyakit.charge_quick/ad_skip"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AD_SKIP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isAdSkipServiceEnabled())
                    "openSettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "armSkipWindow" -> {
                        val durationMs = (call.argument<Number>("durationMs")?.toLong() ?: 6000L)
                            .coerceIn(1000L, 15000L)
                        AlipayAdSkipService.armWindow(durationMs)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAdSkipServiceEnabled(): Boolean {
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val expected = ComponentName(this, AlipayAdSkipService::class.java)
        val fullName = expected.flattenToString()
        val shortName = expected.flattenToShortString()
        return enabledServices.split(':').any { entry ->
            entry.equals(fullName, ignoreCase = true) ||
                entry.equals(shortName, ignoreCase = true)
        }
    }
}
