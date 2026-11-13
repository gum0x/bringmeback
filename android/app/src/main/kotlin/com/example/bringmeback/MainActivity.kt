package com.example.bringmeback

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Passes share links to the app on the "bringmeback/links" channel (see lib/sync/app_links_io.dart):
/// a link the app was opened with, or text shared to it from another app's share menu. Also opens the
/// share sheet for the app's own link.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initial: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // A recreated activity was already handed its link.
        if (savedInstanceState == null) initial = linkFrom(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bringmeback/links").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "initial" -> {
                        result.success(initial)
                        initial = null
                    }
                    "share" -> {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, call.arguments as? String)
                        }
                        startActivity(Intent.createChooser(send, null))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        linkFrom(intent)?.let { channel?.invokeMethod("link", it) }
    }

    private fun linkFrom(intent: Intent?): String? = when (intent?.action) {
        Intent.ACTION_VIEW -> intent.dataString
        Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
        else -> null
    }
}
