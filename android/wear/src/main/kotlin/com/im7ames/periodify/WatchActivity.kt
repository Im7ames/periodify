package com.im7ames.periodify

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.widget.*
import com.google.android.gms.wearable.*
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalTime
import java.time.temporal.ChronoUnit
import java.util.concurrent.Executors

class WatchActivity : Activity(), SharedPreferences.OnSharedPreferenceChangeListener {
    private val preferences by lazy { getSharedPreferences("periodify", MODE_PRIVATE) }
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
                if (raw.length <= 90000) preferences.edit().putString("snapshot",raw).apply()
            }} finally { items.release() }
        }
    }
    override fun onResume() { super.onResume(); preferences.registerOnSharedPreferenceChangeListener(this); handler.post(tick) }
    override fun onPause() { handler.removeCallbacks(tick); preferences.unregisterOnSharedPreferenceChangeListener(this); super.onPause() }
    override fun onDestroy() { updates.shutdownNow(); super.onDestroy() }
    override fun onSharedPreferenceChanged(p: SharedPreferences?, key: String?) { runOnUiThread { render() } }

    private fun scheduleDay(today: LocalDate, lessons: JSONArray, rotation: JSONObject?): LocalDate {
        val start = today.minusDays((today.dayOfWeek.value - 1).toLong())
        val end = start.plusDays(6)
        val weeks = rotation?.optInt("weeks") ?: 0
        if (weeks !in 1..12) return today
        for (i in 0 until lessons.length()) {
            val date = LocalDate.parse(lessons.getJSONObject(i).getString("date"))
            if (!date.isBefore(start) && !date.isAfter(end)) return today
        }
        val anchor = LocalDate.parse(rotation!!.getString("start"))
        val index = Math.floorMod(ChronoUnit.WEEKS.between(anchor, start), weeks.toLong())
        return anchor.plusWeeks(index).plusDays((today.dayOfWeek.value - 1).toLong())
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
        text("periodify",18f,true)
        availableUpdate?.let { update ->
            text(updateMessage ?: "Update ${update.version} available", 14f)
            content.addView(Button(this).apply {
                text = "Install update"
                isEnabled = !installing
                setOnClickListener { install(update) }
            })
        }
        val raw=preferences.getString("snapshot","") ?: ""
        if(raw.isEmpty()) { text("Your day, on your wrist",20f); text("Open Periodify on your phone. Scrape a week, then sync.",14f); setContentView(scroll); return }
        try {
            val data = JSONObject(raw)
            val today = LocalDate.now()
            val lessons = data.getJSONArray("lessons")
            val bells = data.optJSONObject("bells") ?: JSONObject()
            val sourceDay = scheduleDay(today, lessons, data.optJSONObject("rotation")).toString()
            text(today.dayOfWeek.toString().lowercase().replaceFirstChar{it.uppercase()},14f,true)
            var count=0
            for(i in 0 until lessons.length()) {
                val l=lessons.getJSONObject(i);if(l.getString("date")!=sourceDay)continue
                val period=l.getString("period"); val times=bells.optString(period,""); var status=period
                if(times.contains("-")) { val parts=times.split("-"); val now=LocalTime.now();val start=LocalTime.parse(parts[0]);val end=LocalTime.parse(parts[1]);if(!now.isBefore(end))continue; status=if(!now.isBefore(start)) "NOW · $period" else "UPCOMING · $period" }
                text(status,12f,true,lessonAccent(l.optString("color")));text(l.getString("subject"),21f);text(l.optString("room"),18f,true);if(times.isNotEmpty())text(times,14f);count++
            }
            if(count==0)text("No upcoming lessons saved for today.",17f)
            text("Saved ${data.getString("scrapedAt").take(10)}",12f)
            text("Refresh from your phone",12f)
        } catch(_:Exception) { text("Please sync a new timetable from your phone.",16f) }
        content.addView(Button(this).apply { text="Clear watch";setOnClickListener{preferences.edit().remove("snapshot").apply()} })
        setContentView(scroll)
    }
}
