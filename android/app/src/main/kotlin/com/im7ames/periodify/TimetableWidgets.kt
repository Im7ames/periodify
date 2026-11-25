package com.im7ames.periodify

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

class TodayTimetableWidget : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in setOf(TimetableWidgets.refreshAction, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_DATE_CHANGED)) {
            TimetableWidgets.refresh(context)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = TimetableWidgets.refresh(context)
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) = TimetableWidgets.refresh(context)
    override fun onDisabled(context: Context) = TimetableWidgets.refresh(context)
}

class NextLessonWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = TimetableWidgets.refresh(context)
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) = TimetableWidgets.refresh(context)
    override fun onDisabled(context: Context) = TimetableWidgets.refresh(context)
}

object TimetableWidgets {
    const val openAction = "com.im7ames.periodify.OPEN_TODAY"
    const val refreshAction = "com.im7ames.periodify.REFRESH_WIDGETS"
    private const val snapshotKey = "snapshot"

    private fun preferences(context: Context) = context.getSharedPreferences("periodify_widgets", Context.MODE_PRIVATE)

    fun save(context: Context, snapshot: String) {
        preferences(context).edit().putString(snapshotKey, snapshot).apply()
        runCatching { refresh(context) }
            .onFailure { Log.w("TimetableWidgets", "Could not refresh home screen widgets") }
    }

    fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val today = manager.getAppWidgetIds(ComponentName(context, TodayTimetableWidget::class.java))
        val next = manager.getAppWidgetIds(ComponentName(context, NextLessonWidget::class.java))
        val alarm = context.getSystemService(AlarmManager::class.java)
        val refresh = PendingIntent.getBroadcast(
            context, 0, Intent(context, TodayTimetableWidget::class.java).setAction(refreshAction),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarm?.cancel(refresh)
        if (today.isEmpty() && next.isEmpty()) return

        val raw = preferences(context).getString(snapshotKey, null).orEmpty()
        val day = WidgetDay.read(raw)
        val launch = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).setAction(openAction)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        for (id in today) manager.updateAppWidget(id, responsive(context, manager.getAppWidgetOptions(id), day, launch, next = false))
        for (id in next) manager.updateAppWidget(id, responsive(context, manager.getAppWidgetOptions(id), day, launch, next = true))

        // Inexact RTC updates follow local period changes and midnight without a wake-up alarm.
        alarm?.set(AlarmManager.RTC, day.nextRefresh, refresh)
    }

    @Suppress("DEPRECATION")
    private fun responsive(context: Context, options: Bundle, day: WidgetDay, launch: PendingIntent, next: Boolean): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val sizes = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            if (!sizes.isNullOrEmpty() && sizes.size <= 16) {
                return RemoteViews(sizes.associateWith { render(context, it, day, launch, next) })
            }
        }
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 145).toFloat()
        val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth.toInt()).toFloat()
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 90).toFloat()
        val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minHeight.toInt()).toFloat()
        val landscape = render(context, SizeF(maxWidth, minHeight), day, launch, next)
        val portrait = render(context, SizeF(minWidth, maxHeight), day, launch, next)
        return RemoteViews(landscape, portrait)
    }

    private fun render(context: Context, size: SizeF, day: WidgetDay, launch: PendingIntent, next: Boolean): RemoteViews {
        val fontScale = context.resources.configuration.fontScale.coerceAtLeast(1f)
        val usable = size.height / fontScale
        val details = usable >= 104
        val showDate = usable >= 142
        val title = if (next) day.focusTitle else R.string.widget_today
        val views = RemoteViews(context.packageName, R.layout.widget_timetable)
        views.setOnClickPendingIntent(android.R.id.background, launch)
        views.setTextViewText(R.id.widget_title, context.getText(title))
        if (usable < 84) {
            val padding = (8 * context.resources.displayMetrics.density).toInt()
            views.setViewPadding(android.R.id.background, padding, padding, padding, padding)
        }
        views.setTextViewText(R.id.widget_date, day.date)
        views.setViewVisibility(R.id.widget_date, if (showDate) View.VISIBLE else View.GONE)
        views.removeAllViews(R.id.widget_rows)

        val lessons = if (next) listOfNotNull(day.focus) else day.lessons
        if (lessons.isEmpty()) {
            val empty = when {
                !day.hasSnapshot -> R.string.widget_open_to_save
                next && day.lessons.isNotEmpty() -> R.string.widget_day_complete
                else -> R.string.widget_no_lessons_today
            }
            views.setTextViewText(R.id.widget_empty, context.getText(empty))
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            return views
        }
        views.setViewVisibility(R.id.widget_empty, View.GONE)
        val reserved = if (showDate) 69 else 51
        val rowHeight = if (details) 43 else 24
        val capacity = ((usable - reserved) / rowHeight).toInt().coerceIn(1, 12)
        for (lesson in lessons.take(capacity)) {
            val row = RemoteViews(context.packageName, R.layout.widget_timetable_row)
            row.setTextViewText(R.id.widget_subject, lesson.subject)
            val information = if (size.width < 190) listOf(lesson.time, lesson.room) else listOf(lesson.period, lesson.time, lesson.room)
            row.setTextViewText(R.id.widget_detail, information.filter(String::isNotBlank).joinToString(" · "))
            row.setViewVisibility(R.id.widget_detail, if (details) View.VISIBLE else View.GONE)
            views.addView(R.id.widget_rows, row)
        }
        if (!next && lessons.size > capacity && usable >= 135) {
            views.setTextViewText(R.id.widget_more, context.getString(R.string.widget_more_lessons, lessons.size - capacity))
            views.setViewVisibility(R.id.widget_more, View.VISIBLE)
        }
        return views
    }
}

private data class WidgetLesson(val subject: String, val room: String, val period: String, val time: String) {
    private fun minute(text: String): Int? {
        val parts = text.split(':')
        return if (parts.size == 2) parts[0].toIntOrNull()?.let { hours -> parts[1].toIntOrNull()?.let { hours * 60 + it } } else null
    }
    val start: Int? get() = minute(time.substringBefore('-'))
    val end: Int? get() = minute(time.substringAfter('-', ""))
}

private data class WidgetDay(
    val hasSnapshot: Boolean,
    val date: String,
    val lessons: List<WidgetLesson>,
    val focus: WidgetLesson?,
    val focusTitle: Int,
    val nextRefresh: Long,
) {
    companion object {
        fun read(raw: String): WidgetDay {
            val now = Calendar.getInstance()
            val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            val tomorrow = (now.clone() as Calendar).apply { add(Calendar.DATE, 1); atMinute(0) }
            val date = SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(now.time)
            val lessons = runCatching { if (raw.isBlank()) null else lessonsOn(JSONObject(raw), now) }.getOrNull()
                ?: return WidgetDay(false, date, emptyList(), null, R.string.widget_next, tomorrow.timeInMillis)
            val timed = lessons.sortedBy { it.start ?: Int.MAX_VALUE }
            val current = timed.firstOrNull { lesson -> lesson.start?.let { it <= minute } == true && lesson.end?.let { minute < it } == true }
            val upcoming = timed.firstOrNull { it.start?.let { start -> start > minute } == true }
            val untimed = lessons.firstOrNull { it.start == null }
            val boundary = timed.flatMap { listOfNotNull(it.start, it.end) }.filter { it > minute }.minOrNull()
            val nextRefresh = boundary?.let { (now.clone() as Calendar).apply { atMinute(it) }.timeInMillis }
                ?.takeIf { it > now.timeInMillis } ?: tomorrow.timeInMillis
            val title = when {
                current != null -> R.string.widget_in_progress
                upcoming == null && untimed != null -> R.string.widget_today_lessons
                else -> R.string.widget_next
            }
            return WidgetDay(true, date, lessons, current ?: upcoming ?: untimed, title, nextRefresh)
        }

        // Date-only arithmetic in UTC avoids daylight-saving jumps between weeks.
        private fun lessonsOn(data: JSONObject, now: Calendar): List<WidgetLesson> {
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("UTC"); isLenient = false }
            val today = Calendar.getInstance(format.timeZone).apply {
                clear()
                set(now.get(Calendar.YEAR), now.get(Calendar.MONTH), now.get(Calendar.DAY_OF_MONTH))
            }
            var source = format.format(today.time)
            val monday = (today.clone() as Calendar).apply { add(Calendar.DATE, -offsetFromMonday()) }
            val weekStart = format.format(monday.time)
            val weekEnd = format.format((monday.clone() as Calendar).apply { add(Calendar.DATE, 6) }.time)
            val array = data.getJSONArray("lessons")
            val rows = (0 until array.length()).map { array.getJSONObject(it) }
            val repeat = data.optJSONObject("rotation")
            val weeks = repeat?.optInt("weeks") ?: 0
            if (weeks in 1..12 && rows.none { it.optString("date") in weekStart..weekEnd }) {
                val anchor = format.parse(repeat!!.getString("start"))
                val offset = ((monday.timeInMillis - anchor!!.time) / 604800000L).toInt()
                val index = ((offset % weeks) + weeks) % weeks
                source = format.format((monday.clone() as Calendar).apply {
                    time = anchor
                    add(Calendar.DATE, index * 7 + today.offsetFromMonday())
                }.time)
            }
            val times = data.optJSONObject("bells") ?: JSONObject()
            val names = data.optJSONObject("periodNames") ?: JSONObject()
            return rows.filter { it.optString("date") == source }.map {
                val label = it.getString("period")
                WidgetLesson(it.getString("subject"), it.optString("room"), names.optString(label, label), times.optString(label))
            }
        }

        private fun Calendar.offsetFromMonday() = (get(Calendar.DAY_OF_WEEK) + 5) % 7

        private fun Calendar.atMinute(minute: Int) {
            set(Calendar.HOUR_OF_DAY, minute / 60)
            set(Calendar.MINUTE, minute % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }
}
