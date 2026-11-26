package com.im7ames.periodify

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.widget.*
import com.google.android.gms.wearable.*
import java.time.LocalDate
import java.time.LocalTime
import java.util.concurrent.Executors

class WatchActivity : Activity(), SharedPreferences.OnSharedPreferenceChangeListener {
    private val preferences by lazy { WatchSnapshot.preferences(this) }
    private val handler = Handler(Looper.getMainLooper())
    private val updates = Executors.newSingleThreadExecutor()
    private var availableUpdate: WearUpdate? = null
    private var updateMessage: String? = null
    private var installing = false
    private val tick = object : Runnable { override fun run() { render(); handler.postDelayed(this, 30000) } }
    override fun onCreate(state: Bundle?) { super.onCreate(state); render()
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

    private fun lessonAccent(hex: String): Int {
        val muted = Color.rgb(169, 218, 184)
        if (!Regex("^#[0-9a-fA-F]{6}$").matches(hex)) return muted
        val original = Color.parseColor(hex)
        fun blend(base: Int, channel: Int) = (0.65 * base + 0.35 * channel).toInt()
        return Color.rgb(blend(169, Color.red(original)), blend(218, Color.green(original)), blend(184, Color.blue(original)))
    }

    private fun render() {
        val scale = resources.displayMetrics.density
        val content = LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER_HORIZONTAL; setPadding((28*scale).toInt(),(32*scale).toInt(),(28*scale).toInt(),(32*scale).toInt()) }
        val scroll = ScrollView(this).apply { setBackgroundColor(Color.BLACK); addView(content) }
        fun text(value:String,size:Float=16f,accent:Boolean=false, tint: Int = Color.rgb(169,218,184)) { content.addView(TextView(this).apply { text=value; textSize=size; gravity=Gravity.CENTER; setTextColor(if(accent) tint else Color.WHITE); setPadding(0,(7*scale).toInt(),0,(7*scale).toInt()); if(accent) setTypeface(null,Typeface.BOLD) }) }
        content.addView(ImageView(this).apply {
            setImageResource(R.drawable.periodify_launch_mark)
            layoutParams = LinearLayout.LayoutParams((32 * scale).toInt(), (32 * scale).toInt())
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        })
        text("Periodify",18f,true)
        availableUpdate?.let { update ->
            text(updateMessage ?: "Update ${update.version} available", 14f)
            content.addView(Button(this).apply {
                text = "Install update"
                isEnabled = !installing
                setOnClickListener { install(update) }
            })
        }
        val raw = WatchSnapshot.read(this)
        if(raw.isEmpty()) { text("Your day, on your wrist",20f); text("Open Periodify on your phone. Scrape a week, then sync.",14f); setContentView(scroll); return }
        try {
            val schedule = WatchSchedule(raw)
            val today = LocalDate.now()
            text(today.dayOfWeek.toString().lowercase().replaceFirstChar{it.uppercase()},14f,true)
            val now = LocalTime.now()
            var count = 0
            for (lesson in schedule.lessonsOn(today)) {
                val times = lesson.times
                var status = lesson.period
                if (times != null) {
                    if (now >= times.endInclusive) continue
                    status = if (now < times.start) "UPCOMING · ${lesson.period}" else "NOW · ${lesson.period}"
                }
                text(status, 12f, true, lessonAccent(lesson.color))
                text(lesson.subject, 21f)
                text(lesson.room, 18f, true)
                if (lesson.timeLabel.isNotEmpty()) text(lesson.timeLabel, 14f)
                count++
            }
            if(count==0)text("No upcoming lessons saved for today.",17f)
            text("Saved ${schedule.savedDate}",12f)
            text("Refresh from your phone",12f)
        } catch(_:Exception) { text("Please sync a new timetable from your phone.",16f) }
        content.addView(Button(this).apply { text="Clear watch";setOnClickListener{WatchSnapshot.save(this@WatchActivity, "")} })
        setContentView(scroll)
    }
}
