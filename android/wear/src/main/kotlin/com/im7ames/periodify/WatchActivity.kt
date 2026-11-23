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
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalTime

class WatchActivity : Activity(), SharedPreferences.OnSharedPreferenceChangeListener {
    private val preferences by lazy { getSharedPreferences("periodify", MODE_PRIVATE) }
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable { override fun run() { render(); handler.postDelayed(this, 30000) } }
    override fun onCreate(state: Bundle?) { super.onCreate(state); render()
        Wearable.getDataClient(this).dataItems.addOnSuccessListener { items ->
            try { for (item in items) if (item.uri.path == "/periodify/snapshot") {
                val raw = DataMapItem.fromDataItem(item).dataMap.getString("snapshot") ?: ""
                if (raw.length <= 90000) preferences.edit().putString("snapshot",raw).apply()
            }} finally { items.release() }
        }
    }
    override fun onResume() { super.onResume(); preferences.registerOnSharedPreferenceChangeListener(this); handler.post(tick) }
    override fun onPause() { handler.removeCallbacks(tick); preferences.unregisterOnSharedPreferenceChangeListener(this); super.onPause() }
    override fun onSharedPreferenceChanged(p: SharedPreferences?, key: String?) { runOnUiThread { render() } }
    private fun render() {
        val scale = resources.displayMetrics.density
        val content = LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER_HORIZONTAL; setPadding((28*scale).toInt(),(32*scale).toInt(),(28*scale).toInt(),(32*scale).toInt()) }
        val scroll = ScrollView(this).apply { setBackgroundColor(Color.BLACK); addView(content) }
        fun text(value:String,size:Float=16f,accent:Boolean=false) { content.addView(TextView(this).apply { text=value; textSize=size; gravity=Gravity.CENTER; setTextColor(if(accent) Color.rgb(169,218,184) else Color.WHITE); setPadding(0,(7*scale).toInt(),0,(7*scale).toInt()); if(accent) setTypeface(null,Typeface.BOLD) }) }
        text("periodify",18f,true)
        val raw=preferences.getString("snapshot","") ?: ""
        if(raw.isEmpty()) { text("Your day, on your wrist",20f); text("Open Periodify on your phone. Scrape a week, then sync.",14f); setContentView(scroll); return }
        try {
            val data=JSONObject(raw); val today=LocalDate.now().toString(); val lessons=data.getJSONArray("lessons");val bells=data.optJSONObject("bells") ?: JSONObject()
            text(LocalDate.now().dayOfWeek.toString().lowercase().replaceFirstChar{it.uppercase()},14f,true)
            var count=0
            for(i in 0 until lessons.length()) {
                val l=lessons.getJSONObject(i);if(l.getString("date")!=today)continue
                val period=l.getString("period"); val times=bells.optString(period,""); var status=period
                if(times.contains("-")) { val parts=times.split("-"); val now=LocalTime.now();val start=LocalTime.parse(parts[0]);val end=LocalTime.parse(parts[1]);if(!now.isBefore(end))continue; status=if(!now.isBefore(start)) "NOW · $period" else "UPCOMING · $period" }
                text(status,12f,true);text(l.getString("subject"),21f);text(l.optString("room"),18f,true);if(times.isNotEmpty())text(times,14f);count++
            }
            if(count==0)text("No upcoming lessons saved for today.",17f)
            text("Saved ${data.getString("scrapedAt").take(10)}",12f)
            text("Refresh from your phone",12f)
        } catch(_:Exception) { text("Please sync a new timetable from your phone.",16f) }
        content.addView(Button(this).apply { text="Clear watch";setOnClickListener{preferences.edit().remove("snapshot").apply()} })
        setContentView(scroll)
    }
}
