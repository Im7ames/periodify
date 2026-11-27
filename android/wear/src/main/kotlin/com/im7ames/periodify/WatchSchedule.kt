package com.im7ames.periodify

import org.json.JSONObject
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters.previousOrSame
import java.util.Locale

internal class WatchSchedule(raw: String) {
    private val data = JSONObject(raw)
    private val lessons = data.getJSONArray("lessons")
    private val bells = data.optJSONObject("bells") ?: JSONObject()
    private val periodNames = data.optJSONObject("periodNames") ?: JSONObject()
    private val rotation = data.optJSONObject("rotation")
    val savedDate: String get() = data.getString("scrapedAt").take(10)

    fun lessonsOn(day: LocalDate): List<WatchLesson> {
        val source = sourceDay(day).toString()
        return (0 until lessons.length()).mapNotNull { index ->
            val lesson = lessons.getJSONObject(index)
            if (lesson.getString("date") != source) return@mapNotNull null
            val label = lesson.getString("period")
            val times = bells.optString(label)
            val range = runCatching {
                val (start, end) = times.split('-', limit = 2).map(LocalTime::parse)
                if (start < end) start..end else null
            }.getOrNull()
            WatchLesson(
                lesson.getString("subject"),
                lesson.optString("room"),
                lesson.optString("color"),
                periodNames.optString(label, label),
                times,
                range,
            )
        }
    }

    private fun sourceDay(day: LocalDate): LocalDate {
        val weeks = rotation?.optInt("weeks") ?: 0
        if (weeks !in 1..12) return day
        val start = day.with(previousOrSame(DayOfWeek.MONDAY))
        val end = start.plusDays(6)
        for (i in 0 until lessons.length()) {
            val date = LocalDate.parse(lessons.getJSONObject(i).getString("date"))
            if (date in start..end) return day
        }
        val anchor = LocalDate.parse(rotation!!.getString("start"))
            .with(previousOrSame(DayOfWeek.MONDAY))
        val index = Math.floorMod(ChronoUnit.WEEKS.between(anchor, start), weeks.toLong())
        return anchor.plusWeeks(index).plusDays((day.dayOfWeek.value - 1).toLong())
    }
}

internal data class WatchLesson(
    val subject: String,
    val room: String,
    val color: String,
    val period: String,
    val timeLabel: String,
    val times: ClosedRange<LocalTime>?,
) {
    fun statusAt(now: LocalTime): LessonStatus {
        val range = times ?: return LessonStatus.UNTIMED
        return when {
            now < range.start -> LessonStatus.UPCOMING
            now < range.endInclusive -> LessonStatus.CURRENT
            else -> LessonStatus.FINISHED
        }
    }
}

internal enum class LessonStatus { UNTIMED, UPCOMING, CURRENT, FINISHED }

internal fun tileLessonCapacity(screenHeightDp: Int, fontScale: Float): Int =
    ((screenHeightDp - 96) / (37 * fontScale.coerceAtLeast(1f) + 4)).toInt().coerceIn(1, 4)

internal data class TileLessonPage(
    val index: Int,
    val pageCount: Int,
    val rows: List<Pair<WatchLesson, LessonStatus>>,
)

internal fun tileLessonPage(
    lessons: List<WatchLesson>,
    now: LocalTime,
    capacity: Int,
    requestedPage: Int?,
): TileLessonPage {
    val rows = lessons.map { it to it.statusAt(now) }
    if (rows.isEmpty()) return TileLessonPage(0, 1, emptyList())
    val pages = rows.chunked(capacity)
    val current = rows.indexOfFirst { it.second == LessonStatus.CURRENT }
    val upcoming = rows.indexOfFirst { it.second == LessonStatus.UPCOMING }
    val suggested = when {
        current >= 0 -> current / capacity
        upcoming >= 0 -> upcoming / capacity
        rows.any { it.second == LessonStatus.UNTIMED } -> 0
        else -> pages.lastIndex
    }
    val index = requestedPage?.coerceIn(0, pages.lastIndex) ?: suggested
    return TileLessonPage(index, pages.size, pages[index])
}

internal fun tileRefreshMillis(lessons: List<WatchLesson>?, now: ZonedDateTime): Long {
    if (lessons == null) return 0
    val day = now.toLocalDate()
    val midnight = day.plusDays(1).atStartOfDay(now.zone)
    val next = lessons.asSequence().mapNotNull { it.times }
        .flatMap { sequenceOf(it.start, it.endInclusive) }
        .map { day.atTime(it).atZone(now.zone) }
        .filter { it.isAfter(now) }.minOrNull() ?: midnight
    return Duration.between(now, next).toMillis().coerceAtLeast(60_000)
}

internal data class LessonPair(val current: String?, val next: String?) {
    val text: String
        get() = if (current == null && next == null) "—" else "${lessonCode(current)}›${lessonCode(next)}"

    private fun lessonCode(subject: String?): String {
        val letters = subject.orEmpty().uppercase(Locale.ROOT).codePoints()
            .filter { Character.isLetter(it) }.limit(3).toArray()
        return if (letters.isEmpty()) "—" else String(letters, 0, letters.size)
    }
}

internal data class LessonSlot(val start: Instant, val end: Instant, val pair: LessonPair)

internal fun lessonSlots(lessons: List<WatchLesson>, day: LocalDate, zone: ZoneId): List<LessonSlot> {
    data class TimedLesson(val subject: String, val start: Instant, val end: Instant)

    val timed = lessons.mapNotNull { lesson ->
        val times = lesson.times ?: return@mapNotNull null
        val start = day.atTime(times.start).atZone(zone).toInstant()
        val end = day.atTime(times.endInclusive).atZone(zone).toInstant()
        if (start < end) TimedLesson(lesson.subject, start, end) else null
    }.sortedBy { it.start }
    if (timed.isEmpty()) return emptyList()

    val boundaries = (listOf(day.atStartOfDay(zone).toInstant()) +
        timed.flatMap { listOf(it.start, it.end) }).distinct().sorted()
    val slots = mutableListOf<LessonSlot>()
    for ((start, end) in boundaries.zipWithNext()) {
        val current = timed.firstOrNull { it.start <= start && start < it.end }
        val next = timed.firstOrNull { start < it.start }
        val pair = LessonPair(current?.subject, next?.subject)
        if (pair.current == null && pair.next == null) continue
        val previous = slots.lastOrNull()
        if (previous != null && previous.end == start && previous.pair == pair) {
            slots[slots.lastIndex] = previous.copy(end = end)
        } else {
            slots.add(LessonSlot(start, end, pair))
        }
    }
    return slots
}
