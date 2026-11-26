package com.im7ames.periodify

import android.content.ComponentName
import android.content.Context
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import org.json.JSONObject

internal object WatchSnapshot {
    private const val key = "snapshot"

    fun preferences(context: Context) = context.getSharedPreferences("periodify", Context.MODE_PRIVATE)

    fun read(context: Context): String = preferences(context).getString(key, "").orEmpty()

    fun save(context: Context, raw: String) {
        if (raw.length > 90000 || read(context) == raw) return
        if (raw.isNotEmpty() && runCatching { JSONObject(raw).getInt("schema") }.getOrNull() != 1) return
        preferences(context).edit().putString(key, raw).apply()
        ComplicationDataSourceUpdateRequester.create(
            context, ComponentName(context, LessonComplicationService::class.java),
        ).requestUpdateAll()
        TileService.getUpdater(context).requestUpdate(TimetableTileService::class.java)
    }
}
