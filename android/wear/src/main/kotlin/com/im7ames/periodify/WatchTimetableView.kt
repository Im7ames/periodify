package com.im7ames.periodify

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.LinearLayout.LayoutParams
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import kotlin.math.roundToInt

internal class WatchTimetableView(context: Context) : LinearLayout(context) {
    private val mint = 0xFFA9DAB8.toInt()
    private val mutedText = 0xFFBBC6BE.toInt()
    private val fadedText = 0xFF9AA69D.toInt()
    private val surface = 0xFF161C19.toInt()

    init {
        orientation = VERTICAL
        val inset = dp(if (resources.configuration.isScreenRound) 18 else 12)
        setPadding(inset, dp(32), inset, dp(32))
    }

    fun addHeader(date: String) {
        val brand = LinearLayout(context).apply {
            gravity = Gravity.CENTER
            addView(ImageView(context).apply {
                setImageResource(R.drawable.periodify_launch_mark)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LayoutParams(dp(16), dp(16)).apply { marginEnd = dp(5) })
            addView(label("Periodify", 12f, mint, bold = true))
        }
        addView(brand, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        addView(label(date, 18f, Color.WHITE, bold = true).apply {
            gravity = Gravity.CENTER
            isAccessibilityHeading = true
            setPadding(0, dp(4), 0, dp(10))
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    fun addMessage(message: String) {
        addView(label(message, 13f, mutedText).apply {
            gravity = Gravity.CENTER
            setPadding(dp(3), dp(5), dp(3), dp(5))
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    fun addLesson(lesson: WatchLesson, status: LessonStatus) {
        val active = status == LessonStatus.CURRENT
        val finished = status == LessonStatus.FINISHED
        val accent = lessonAccent(lesson.color)
        val row = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(44)
            setPadding(dp(9), dp(6), dp(9), dp(6))
            background = GradientDrawable().apply {
                cornerRadius = dp(13).toFloat()
                setColor(ColorUtils.blendARGB(surface, accent, if (active) .21f else .08f))
                if (active) setStroke(dp(1), ColorUtils.blendARGB(surface, accent, .60f))
            }
        }
        val details = LinearLayout(context).apply {
            orientation = VERTICAL
            val subject = label(lesson.subject, 14f, if (finished) mutedText else Color.WHITE, bold = true)
            subject.maxLines = 2
            subject.ellipsize = TextUtils.TruncateAt.END
            addView(subject)
            val caption = listOfNotNull(
                if (active) "Now" else null,
                lesson.period.takeIf(String::isNotBlank),
                lesson.timeLabel.takeIf(String::isNotBlank)?.replace('-', '–'),
            ).joinToString(" · ")
            if (caption.isNotEmpty()) {
                addView(label(caption, 11f, if (finished) fadedText else accent).apply {
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                })
            }
        }
        row.addView(details, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        if (lesson.room.isNotBlank()) {
            row.addView(label(lesson.room, 12f, if (finished) mutedText else accent, bold = true).apply {
                gravity = Gravity.END
                maxWidth = dp((resources.configuration.screenWidthDp * .29f).roundToInt().coerceIn(36, 76))
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp(7)
            })
        }
        addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dp(4)
        })
    }

    private fun lessonAccent(hex: String): Int =
        if (lessonColor.matches(hex)) ColorUtils.blendARGB(mint, Color.parseColor(hex), .35f) else mint

    private fun label(value: String, size: Float, tint: Int, bold: Boolean = false) =
        TextView(context).apply {
            text = value
            textSize = size
            setTextColor(tint)
            if (bold) setTypeface(null, Typeface.BOLD)
        }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()

    private companion object {
        val lessonColor = Regex("#[0-9a-fA-F]{6}")
    }
}
