package com.im7ames.periodify

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataTimeline
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingTimelineComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.TimeInterval
import androidx.wear.watchface.complications.datasource.TimelineEntry
import java.time.LocalDate
import java.time.ZoneId

class LessonComplicationService : SuspendingTimelineComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationDataTimeline? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) return null
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val schedule = runCatching { WatchSchedule(WatchSnapshot.read(this)) }.getOrNull()
        val todayLessons = runCatching { schedule?.lessonsOn(today).orEmpty() }.getOrDefault(emptyList())
        val tomorrow = today.plusDays(1)
        val tomorrowLessons = runCatching { schedule?.lessonsOn(tomorrow).orEmpty() }.getOrDefault(emptyList())
        val noLesson = LessonPair(null, null)
        val todaySlots = lessonSlots(todayLessons, today, zone)
        val tomorrowSlots = lessonSlots(tomorrowLessons, tomorrow, zone)
        val openWatch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, WatchActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val fallback = when {
            schedule == null -> R.string.lesson_complication_no_sync
            todayLessons.isNotEmpty() && todaySlots.isEmpty() -> R.string.lesson_complication_no_times
            else -> R.string.lesson_complication_no_lessons
        }
        return ComplicationDataTimeline(
            defaultComplicationData = display(noLesson, getString(fallback), openWatch),
            timelineEntries = (todaySlots + tomorrowSlots).map { slot ->
                TimelineEntry(TimeInterval(slot.start, slot.end), display(slot.pair, tap = openWatch))
            },
        )
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.SHORT_TEXT) display(LessonPair("Maths", "English")) else null

    private fun display(
        pair: LessonPair,
        description: String? = null,
        tap: PendingIntent? = null,
    ): ShortTextComplicationData {
        val none = getString(R.string.lesson_complication_none)
        return ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder(pair.text).build(),
            contentDescription = PlainComplicationText.Builder(
                description ?: getString(
                    R.string.lesson_complication_description, pair.current ?: none, pair.next ?: none,
                ),
            ).build(),
        ).setTapAction(tap).build()
    }
}
