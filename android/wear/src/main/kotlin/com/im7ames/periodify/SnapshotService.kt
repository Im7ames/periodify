package com.im7ames.periodify

import com.google.android.gms.wearable.*
import org.json.JSONObject

class SnapshotService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.dataItem.uri.path != "/periodify/snapshot") continue
            val raw = if (event.type == DataEvent.TYPE_DELETED) "" else DataMapItem.fromDataItem(event.dataItem).dataMap.getString("snapshot") ?: ""
            if (raw.length > 90000) continue
            if (raw.isNotEmpty()) {
                try { if (JSONObject(raw).getInt("schema") != 1) continue } catch (_: Exception) { continue }
            }
            getSharedPreferences("periodify", MODE_PRIVATE).edit().putString("snapshot", raw).apply()
        }
    }
}
