package com.im7ames.periodify

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import android.content.Intent
import android.app.Activity
import java.io.File

class MainActivity : FlutterActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportPayload: String? = null
    private var timetableWidget: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        timetableWidget = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "com.im7ames.periodify/timetableWidget",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                val payload = call.arguments as? String
                when {
                    call.method != "save" -> result.notImplemented()
                    payload == null -> result.error("PAYLOAD", "Invalid widget timetable", null)
                    else -> {
                        TimetableWidgets.save(this, payload)
                        result.success(null)
                    }
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.im7ames.periodify/update")
            .setMethodCallHandler { call, result ->
                if (call.method == "cacheDirectory") {
                    result.success(cacheDir.path)
                } else if (call.method != "install") {
                    result.notImplemented()
                } else {
                    try {
                        if (UpdateInstaller.offer(this, File(call.arguments as String))) result.success(null)
                        else result.error("INSTALL_PERMISSION", "Android requires installation permission", null)
                    } catch (_: Exception) {
                        result.error("INSTALL", "Android could not open this update", null)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.im7ames.periodify/watch")
            .setMethodCallHandler { call, result ->
                if (call.method == "export") {
                    if (exportResult != null) { result.error("BUSY", "Export already open", null) }
                    else {
                        exportResult = result
                        exportPayload = call.arguments as? String
                        try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, "periodify.json")
                        }, 7301) } catch (_: Exception) {
                            exportResult = null; exportPayload = null
                            result.error("EXPORT", "No document picker is available", null)
                        }
                    }
                } else if (call.method != "sync" && call.method != "clear") {
                    result.notImplemented()
                } else {
                    val payload = if (call.method == "clear") "" else call.arguments as? String
                    if (payload != null) TimetableWidgets.save(this, payload)
                    if (payload == null || payload.toByteArray().size > 90000) {
                        result.error("PAYLOAD", "Timetable exceeds watch transfer limit", null)
                    } else {
                        val request = PutDataMapRequest.create("/periodify/snapshot").apply {
                            dataMap.putString("snapshot", payload)
                            dataMap.putLong("revision", System.currentTimeMillis())
                        }.asPutDataRequest().setUrgent()
                        Wearable.getDataClient(this).putDataItem(request)
                            .addOnSuccessListener { result.success(null) }
                            .addOnFailureListener { result.error("SYNC", "Watch transfer failed", null) }
                    }
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == TimetableWidgets.openAction) {
            timetableWidget?.invokeMethod("openToday", null)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        timetableWidget?.setMethodCallHandler(null)
        timetableWidget = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("Activity result API used for Flutter host compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7301) return
        try {
            if (resultCode == Activity.RESULT_OK) {
                val uri = data?.data ?: throw IllegalStateException()
                val stream = contentResolver.openOutputStream(uri) ?: throw IllegalStateException()
                stream.use { it.write((exportPayload ?: "").toByteArray(Charsets.UTF_8)) }
            }
            exportResult?.success(null)
        } catch (_: Exception) { exportResult?.error("EXPORT", "Could not save snapshot", null) }
        finally { exportResult = null; exportPayload = null }
    }
}
