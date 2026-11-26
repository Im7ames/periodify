package com.im7ames.periodify

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

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
            {"date": "2026-10-26", "period": "P2", "subject": "Science"},
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
}
