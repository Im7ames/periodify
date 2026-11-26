package com.im7ames.periodify

import com.google.android.gms.wearable.*

class SnapshotService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.dataItem.uri.path != "/periodify/snapshot") continue
            val raw = if (event.type == DataEvent.TYPE_DELETED) "" else DataMapItem.fromDataItem(event.dataItem).dataMap.getString("snapshot") ?: ""
            WatchSnapshot.save(this, raw)
        }
    }
}
