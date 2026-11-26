package com.im7ames.periodify

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.content.SharedPreferences
import android.graphics.Color
import android.view.InputDevice
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.Button
import android.widget.ScrollView
import com.google.android.gms.wearable.*
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors

class WatchActivity : Activity(), SharedPreferences.OnSharedPreferenceChangeListener {
    private val preferences by lazy { WatchSnapshot.preferences(this) }
    private val handler = Handler(Looper.getMainLooper())
    private val updates = Executors.newSingleThreadExecutor()
    private var availableUpdate: WearUpdate? = null
    private var updateMessage: String? = null
    private var installing = false
    private lateinit var timetable: WatchTimetableView
    private lateinit var scroll: ScrollView
    private var rotaryRemainder = 0f
    private val rotaryScrollFactor by lazy { ViewConfiguration.get(this).scaledVerticalScrollFactor }
    private var lastContent: TimetableContent? = null

    private data class TimetableContent(
        val dateLabel: String,
        val rows: List<Pair<WatchLesson, LessonStatus>>,
        val savedDate: String?,
        val message: String?,
        val updateLabel: String?,
        val installing: Boolean,
    )

    private val tick = object : Runnable { override fun run() { render(); handler.postDelayed(this, 30000) } }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        timetable = WatchTimetableView(this)
        scroll = ScrollView(this).apply {
            id = R.id.watch_timetable_scroll
            setBackgroundColor(Color.BLACK)
            isVerticalScrollBarEnabled = true
            addView(timetable)
        }
        setContentView(scroll)
        render()
        @Suppress("DEPRECATION")
        val installed = packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
        updates.execute {
            val offer = runCatching { WearUpdates.check(installed) }.getOrNull()
            runOnUiThread {
                if (!isDestroyed && offer != null) {
                    availableUpdate = offer
                    render()
                }
            }
        }
        Wearable.getDataClient(this).dataItems.addOnSuccessListener { items ->
            try { for (item in items) if (item.uri.path == "/periodify/snapshot") {
                val raw = DataMapItem.fromDataItem(item).dataMap.getString("snapshot") ?: ""
                WatchSnapshot.save(this, raw)
            }} finally { items.release() }
        }
    }
    override fun onResume() { super.onResume(); preferences.registerOnSharedPreferenceChangeListener(this); handler.post(tick) }
    override fun onPause() { handler.removeCallbacks(tick); preferences.unregisterOnSharedPreferenceChangeListener(this); super.onPause() }
    override fun onDestroy() { updates.shutdownNow(); super.onDestroy() }
    override fun onSharedPreferenceChanged(p: SharedPreferences?, key: String?) { runOnUiThread { render() } }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.actionMasked != MotionEvent.ACTION_SCROLL ||
            !event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)
        ) {
            return super.dispatchGenericMotionEvent(event)
        }
        val delta = -event.getAxisValue(MotionEvent.AXIS_SCROLL) * rotaryScrollFactor
        if (delta == 0f) return super.dispatchGenericMotionEvent(event)
        val pixels = rotaryRemainder + delta
        val wholePixels = pixels.toInt()
        rotaryRemainder = pixels - wholePixels
        if (wholePixels != 0) scroll.scrollBy(0, wholePixels)
        return true
    }

    private fun install(update: WearUpdate) {
        installing = true
        updateMessage = "Verifying download…"
        render()
        updates.execute {
            val packageFile = runCatching { WearUpdates.download(update, cacheDir) }.getOrNull()
            runOnUiThread {
                if (isDestroyed) return@runOnUiThread
                updateMessage = when {
                    packageFile == null -> "Download failed. Try again."
                    else -> try {
                        if (UpdateInstaller.offer(this, packageFile)) "Follow the installer prompts."
                        else "Allow installation and try again."
                    } catch (_: Exception) {
                        "Install the Wear OS APK from GitHub using your phone."
                    }
                }
                installing = false
                render()
            }
        }
    }

    private fun render() {
        val now = LocalDateTime.now()
        val raw = WatchSnapshot.read(this)
        val update = availableUpdate
        val saved = runCatching {
            val schedule = WatchSchedule(raw)
            schedule.savedDate to schedule.lessonsOn(now.toLocalDate())
        }.getOrNull()
        val rows = saved?.second.orEmpty().map { it to it.statusAt(now.toLocalTime()) }
        val message = when {
            raw.isEmpty() -> "Scrape and sync a timetable from Periodify on your phone."
            saved == null -> "Please sync a new timetable from your phone."
            rows.isEmpty() -> "No lessons saved for today."
            else -> null
        }
        val content = TimetableContent(
            now.format(DateTimeFormatter.ofPattern("EEE, d MMM")),
            rows,
            saved?.first,
            message,
            update?.let { updateMessage ?: "Update ${it.version} available" },
            installing,
        )
        if (content == lastContent) return
        lastContent = content
        timetable.removeAllViews()
        timetable.addHeader(content.dateLabel)
        content.message?.let(timetable::addMessage)
        for ((lesson, status) in content.rows) timetable.addLesson(lesson, status)
        content.savedDate?.let { timetable.addMessage("Saved $it") }
        if (update != null && content.updateLabel != null) {
            timetable.addMessage(content.updateLabel)
            timetable.addView(Button(this).apply {
                text = "Install update"
                isEnabled = !content.installing
                setOnClickListener { install(update) }
            })
        }
        if (raw.isNotEmpty()) {
            timetable.addView(Button(this).apply {
                text = "Clear watch"
                setOnClickListener { WatchSnapshot.save(this@WatchActivity, "") }
            })
        }
    }
}
