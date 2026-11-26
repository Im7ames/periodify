package com.im7ames.periodify

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

class WatchScheduleTest {
    private val monday = LocalDate.parse("2026-10-26")
    private val schedule = WatchSchedule(
        """
        {
          "schema": 1,
          "scrapedAt": "2026-10-26T12:00:00Z",
          "rotation": {"weeks": 2, "start": "2026-10-26"},
          "bells": {"P1": "08:40-09:20", "P2": "09:35-10:15", "P3": "10:15-11:10"},
          "periodNames": {"P2": "Morning session"},
          "lessons": [
            {"date": "2026-10-26", "period": "P3", "subject": "English"},
            {"date": "2026-10-26", "period": "P1", "subject": "Maths"},
            {"date": "2026-10-26", "period": "P2", "subject": "Science", "room": "Lab 2", "color": "#2F8FCE"},
            {"date": "2026-10-26", "period": "P4", "subject": "Art"},
            {"date": "2026-11-02", "period": "P1", "subject": "History"},
            {"date": "2026-11-10", "period": "P1", "subject": "Music"}
          ]
        }
        """.trimIndent(),
    )

    @Test fun showsCurrentAndFollowingAtEveryBoundary() {
        val slots = lessonSlots(schedule.lessonsOn(monday), monday, ZoneOffset.UTC)
        fun at(time: String) = slots.firstOrNull {
            val instant = Instant.parse("2026-10-26T${time}:00Z")
            it.start <= instant && instant < it.end
        }?.pair?.text ?: "—"
        assertEquals("—›MAT", at("08:39"))
        assertEquals("MAT›SCI", at("08:40"))
        assertEquals("—›SCI", at("09:20"))
        assertEquals("SCI›ENG", at("09:35"))
        assertEquals("ENG›—", at("10:15"))
        assertEquals("—", at("11:10"))
    }

    @Test fun usesSavedDatesAndRotationWithLocalTiming() {
        assertTrue(schedule.lessonsOn(monday.plusWeeks(2)).isEmpty())
        val summerMonday = LocalDate.parse("2027-03-29")
        val lessons = schedule.lessonsOn(summerMonday)
        assertTrue(lessons.isNotEmpty())
        assertEquals("Morning session", lessons.first { it.subject == "Science" }.period)
        assertNull(lessons.first { it.subject == "Art" }.times)
        val slots = lessonSlots(lessons, summerMonday, ZoneId.of("Europe/London"))
        assertEquals(Instant.parse("2027-03-29T07:40:00Z"), slots[1].start)
        assertEquals("HIS›—", lessonSlots(
            schedule.lessonsOn(summerMonday.plusWeeks(1)), summerMonday.plusWeeks(1), ZoneOffset.UTC,
        )[1].pair.text)
    }

    @Test fun compactCodesHandlePunctuationAndShortNames() {
        assertEquals("CST›PE", LessonPair("C.S.T.", "PE").text)
        assertEquals("ÉCO›HIS", LessonPair("Économie", "History").text)
        assertEquals("—", LessonPair(null, null).text)
    }

    @Test fun listHighlightsOnlyTheLessonInProgress() {
        val lessons = schedule.lessonsOn(monday)
        val maths = lessons.first { it.subject == "Maths" }
        assertEquals(LessonStatus.UPCOMING, maths.statusAt(LocalTime.of(8, 39)))
        assertEquals(LessonStatus.CURRENT, maths.statusAt(LocalTime.of(8, 40)))
        assertEquals(LessonStatus.FINISHED, maths.statusAt(LocalTime.of(9, 20)))
        assertEquals(LessonStatus.UNTIMED, lessons.first { it.subject == "Art" }.statusAt(LocalTime.NOON))
    }

    @Test fun tileShowsTheCurrentLessonAndFitsRowsToWatchSize() {
        val lessons = schedule.lessonsOn(monday).sortedBy { it.times?.start ?: LocalTime.MAX }
        val small = tileLessonCapacity(192, 1f)
        assertEquals(2, small)
        assertEquals(1, tileLessonCapacity(192, 1.5f))
        assertEquals(3, tileLessonCapacity(227, 1f))
        val rows = tileLessons(lessons, LocalTime.of(9, 40), small)
        val (science, status) = rows.first()
        assertEquals(listOf("Science", "English"), rows.map { it.first.subject })
        assertEquals("Lab 2", science.room)
        assertEquals("#2F8FCE", science.color)
        assertEquals("09:35-10:15", science.timeLabel)
        assertEquals(LessonStatus.CURRENT, status)
        val afterEnd = tileLessons(lessons.dropLast(1), LocalTime.NOON, small)
        assertEquals(listOf("Science", "English"), afterEnd.map { it.first.subject })
        assertTrue(afterEnd.all { it.second == LessonStatus.FINISHED })
    }

    @Test fun tileRefreshesAtPeriodBoundariesOrMidnight() {
        val lessons = schedule.lessonsOn(monday)
        val atNine = ZonedDateTime.parse("2026-10-26T09:00:00Z")
        assertEquals(1_200_000L, tileRefreshMillis(lessons, atNine))
        assertEquals(60_000L, tileRefreshMillis(lessons, atNine.plusMinutes(19).plusSeconds(30)))
        assertEquals(7_200_000L, tileRefreshMillis(lessons, atNine.plusHours(13)))
        assertEquals(0L, tileRefreshMillis(null, atNine))
    }
}
