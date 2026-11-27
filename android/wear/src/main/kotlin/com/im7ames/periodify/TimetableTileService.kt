package com.im7ames.periodify

import android.graphics.Color
import androidx.wear.protolayout.ActionBuilders.AndroidActivity
import androidx.wear.protolayout.ActionBuilders.LaunchAction
import androidx.wear.protolayout.ActionBuilders.LoadAction
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.weight
import androidx.wear.protolayout.LayoutElementBuilders.Box
import androidx.wear.protolayout.LayoutElementBuilders.Column
import androidx.wear.protolayout.LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER
import androidx.wear.protolayout.LayoutElementBuilders.HORIZONTAL_ALIGN_END
import androidx.wear.protolayout.LayoutElementBuilders.HORIZONTAL_ALIGN_START
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.LayoutElementBuilders.Row
import androidx.wear.protolayout.LayoutElementBuilders.Spacer
import androidx.wear.protolayout.LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE
import androidx.wear.protolayout.LayoutElementBuilders.VERTICAL_ALIGN_CENTER
import androidx.wear.protolayout.ModifiersBuilders.Background
import androidx.wear.protolayout.ModifiersBuilders.Border
import androidx.wear.protolayout.ModifiersBuilders.Clickable
import androidx.wear.protolayout.ModifiersBuilders.Corner
import androidx.wear.protolayout.ModifiersBuilders.Modifiers
import androidx.wear.protolayout.ModifiersBuilders.Padding
import androidx.wear.protolayout.StateBuilders.State
import androidx.wear.protolayout.TimelineBuilders.Timeline
import androidx.wear.protolayout.expression.dynamicDataMapOf
import androidx.wear.protolayout.expression.intAppDataKey
import androidx.wear.protolayout.expression.mapTo
import androidx.wear.protolayout.material3.ButtonColors
import androidx.wear.protolayout.material3.MaterialScope
import androidx.wear.protolayout.material3.Typography
import androidx.wear.protolayout.material3.primaryLayout
import androidx.wear.protolayout.material3.text
import androidx.wear.protolayout.material3.textButton
import androidx.wear.protolayout.material3.textEdgeButton
import androidx.wear.protolayout.modifiers.LayoutModifier
import androidx.wear.protolayout.modifiers.clickable
import androidx.wear.protolayout.modifiers.contentDescription
import androidx.wear.protolayout.types.LayoutColor
import androidx.wear.protolayout.types.layoutString
import androidx.wear.tiles.Material3TileService
import androidx.wear.tiles.RequestBuilders.TileRequest
import androidx.wear.tiles.TileBuilders.Tile
import androidx.wear.tiles.tile
import java.time.ZonedDateTime
import kotlin.time.Duration.Companion.milliseconds

class TimetableTileService : Material3TileService(allowDynamicTheme = false) {
    private companion object {
        val pageKey = intAppDataKey("timetable_page")
        val dayKey = intAppDataKey("timetable_day")
    }

    override suspend fun MaterialScope.tileResponse(requestParams: TileRequest): Tile {
        val device = requestParams.deviceConfiguration
        val now = ZonedDateTime.now()
        val day = now.toLocalDate()
        val dayNumber = day.toEpochDay().toInt()
        val lessons = runCatching {
            WatchSchedule(WatchSnapshot.read(this@TimetableTileService)).lessonsOn(day)
        }.getOrNull()
        val count = tileLessonCapacity(device.screenHeightDp, device.fontScale)
        val state = requestParams.currentState.stateMap
        val requestedPage = state[pageKey].takeIf { state[dayKey] == dayNumber }
        val page = tileLessonPage(lessons.orEmpty(), now.toLocalTime(), count, requestedPage)
        val paged = page.pageCount > 1
        val open = Clickable.Builder()
            .setId("open_timetable")
            .setOnClick(LaunchAction.Builder().setAndroidActivity(
                AndroidActivity.Builder()
                    .setPackageName(packageName)
                    .setClassName(WatchActivity::class.java.name)
                    .build(),
            ).build())
            .build()

        return tile(
            state = if (paged && requestedPage != null) pageState(dayNumber, page.index) else State.Builder().build(),
            timeline = Timeline.fromLayoutElement(primaryLayout(
                titleSlot = {
                    if (paged) {
                        text(
                            getString(R.string.timetable_tile_page, page.index + 1, page.pageCount).layoutString,
                            modifier = LayoutModifier.clickable(open).contentDescription(
                                getString(R.string.timetable_tile_page_description, page.index + 1, page.pageCount),
                            ),
                            maxLines = 1,
                        )
                    } else {
                        text(getString(R.string.timetable_tile_title).layoutString)
                    }
                },
                mainSlot = {
                    if (page.rows.isEmpty()) {
                        val empty = if (lessons == null) R.string.timetable_tile_no_sync else R.string.timetable_tile_empty
                        text(getString(empty).layoutString, maxLines = 2)
                    } else {
                        Column.Builder().setWidth(expand()).apply {
                            page.rows.forEachIndexed { index, (lesson, status) ->
                                if (index > 0) addContent(Spacer.Builder().setHeight(dp(4f)).build())
                                addContent(lessonRow(lesson, status))
                            }
                        }.build()
                    }
                },
                bottomSlot = {
                    if (paged) {
                        pageNavigation(dayNumber, page)
                    } else {
                        textEdgeButton(
                            onClick = open,
                            modifier = LayoutModifier.contentDescription(getString(R.string.timetable_tile_open_description)),
                            colors = pageButtonColors(),
                        ) {
                            text(getString(R.string.timetable_tile_open).layoutString)
                        }
                    }
                },
            )),
            freshness = tileRefreshMillis(lessons, now).milliseconds,
        )
    }

    private fun pageState(day: Int, index: Int): State =
        State.Builder().setStateMap(dynamicDataMapOf(dayKey mapTo day, pageKey mapTo index)).build()

    private fun MaterialScope.pageNavigation(day: Int, page: TileLessonPage): LayoutElement {
        val buttons = Row.Builder()
            .addContent(pageButton(day, page, -1, "‹", R.string.timetable_tile_previous))
            .addContent(Spacer.Builder().setWidth(dp(8f)).build())
            .addContent(pageButton(day, page, 1, "›", R.string.timetable_tile_next))
            .build()
        return Box.Builder().setWidth(expand()).setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
            .addContent(buttons).build()
    }

    private fun MaterialScope.pageButton(
        day: Int,
        page: TileLessonPage,
        direction: Int,
        symbol: String,
        description: Int,
    ): LayoutElement {
        val target = page.index + direction
        if (target !in 0 until page.pageCount) {
            return Spacer.Builder().setWidth(dp(48f)).setHeight(dp(48f)).build()
        }
        return textButton(
            onClick = Clickable.Builder()
                .setId("timetable_page_$target")
                .setOnClick(LoadAction.Builder().setRequestState(pageState(day, target)).build())
                .build(),
            labelContent = { text(symbol.layoutString, typography = Typography.TITLE_MEDIUM) },
            modifier = LayoutModifier.contentDescription(getString(description)),
            width = dp(48f),
            height = dp(48f),
            contentPadding = Padding.Builder().build(),
            colors = pageButtonColors(),
        )
    }

    private fun pageButtonColors() = ButtonColors(
        containerColor = LayoutColor(WatchTimetableColors.mint),
        labelColor = LayoutColor(0xFF173526.toInt()),
    )

    private fun MaterialScope.lessonRow(lesson: WatchLesson, status: LessonStatus): LayoutElement {
        val active = status == LessonStatus.CURRENT
        val finished = status == LessonStatus.FINISHED
        val colors = WatchTimetableColors
        val accent = colors.accent(lesson.color)
        val modifiers = Modifiers.Builder()
            .setPadding(Padding.Builder().setStart(dp(8f)).setEnd(dp(8f))
                .setTop(dp(3f)).setBottom(dp(3f)).build())
            .setBackground(Background.Builder().setColor(argb(colors.background(accent, active)))
                .setCorner(Corner.Builder().setRadius(dp(12f)).build()).build())
        if (active) modifiers.setBorder(Border.Builder().setWidth(dp(1f)).setColor(argb(colors.border(accent))).build())
        val caption = lesson.timeLabel.ifBlank { lesson.period }.replace('-', '–')
        val detail = if (active) "${getString(R.string.timetable_tile_now)} · $caption" else caption
        return Row.Builder().setWidth(expand()).setVerticalAlignment(VERTICAL_ALIGN_CENTER)
            .setModifiers(modifiers.build())
            .addContent(
                Column.Builder().setWidth(weight(1f)).setHorizontalAlignment(HORIZONTAL_ALIGN_START)
                    .addContent(text(lesson.subject.layoutString, typography = Typography.BODY_SMALL,
                        color = LayoutColor(if (finished) colors.mutedText else Color.WHITE),
                        maxLines = 1, overflow = TEXT_OVERFLOW_ELLIPSIZE))
                    .addContent(text(detail.layoutString, typography = Typography.BODY_EXTRA_SMALL,
                        color = LayoutColor(if (finished) colors.fadedText else accent),
                        maxLines = 1, overflow = TEXT_OVERFLOW_ELLIPSIZE))
                    .build(),
            )
            .apply {
                if (lesson.room.isNotBlank()) {
                    addContent(Spacer.Builder().setWidth(dp(4f)).build())
                    addContent(Box.Builder().setWidth(weight(.38f)).setHorizontalAlignment(HORIZONTAL_ALIGN_END)
                        .addContent(text(lesson.room.layoutString, typography = Typography.LABEL_SMALL,
                            modifier = LayoutModifier.contentDescription(getString(R.string.timetable_tile_room, lesson.room)),
                            color = LayoutColor(if (finished) colors.mutedText else accent),
                            maxLines = 2, overflow = TEXT_OVERFLOW_ELLIPSIZE))
                        .build())
                }
            }.build()
    }
}
