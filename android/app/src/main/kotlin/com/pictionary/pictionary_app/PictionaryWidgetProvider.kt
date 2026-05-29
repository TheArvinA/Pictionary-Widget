package com.pictionary.pictionary_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONException

/**
 * Native home-screen widget for the daily Pictionary game.
 *
 * Reads state that the Flutter app pushes via HomeWidget.saveWidgetData and renders one of three
 * layouts. Click targets deep-link back into the app using the
 * `pictionary://open?route=<url-encoded go_router location>` scheme.
 *
 * Cross-side contract (must match Flutter):
 *   w_state  int     1 | 2 | 3  (default 1)
 *   w_words  String  JSON array of up to 3 strings
 *   w_friends String JSON array of {uid,name,thumbUrl,submitted}
 *   w_streak int     (default 0)
 *   w_day    int     (default 0)
 *   w_solved int     (default 0)
 *   w_total  int     (default 0)
 */
class PictionaryWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = when (widgetData.getInt("w_state", STATE_NOT_DRAWN)) {
                STATE_GUESSING -> buildStateGuessing(context, widgetData)
                STATE_DONE -> buildStateDone(context, widgetData)
                else -> buildStateNotDrawn(context, widgetData)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /** State 1: user has not drawn yet — show the 3 word choices as tappable cells. */
    private fun buildStateNotDrawn(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.pictionary_widget_state1)
        val words = parseStringArray(data.getString("w_words", null))

        bindWordCell(context, views, words, 0, R.id.word_cell_1, R.id.word_1)
        bindWordCell(context, views, words, 1, R.id.word_cell_2, R.id.word_2)
        bindWordCell(context, views, words, 2, R.id.word_cell_3, R.id.word_3)
        return views
    }

    private fun bindWordCell(
        context: Context,
        views: RemoteViews,
        words: List<String>,
        index: Int,
        cellId: Int,
        textId: Int,
    ) {
        val word = words.getOrNull(index)
        if (word.isNullOrBlank()) {
            views.setViewVisibility(cellId, View.GONE)
            return
        }
        views.setViewVisibility(cellId, View.VISIBLE)
        views.setTextViewText(textId, word)
        views.setOnClickPendingIntent(cellId, route(context, "/canvas?word=$word"))
    }

    /** State 2: user drew; show friends who submitted so they can be guessed. */
    private fun buildStateGuessing(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.pictionary_widget_state2)
        val friends = parseFriends(data.getString("w_friends", null))

        bindFriendRow(context, views, friends, 0, R.id.friend_row_1, R.id.friend_name_1, R.id.friend_status_1, R.id.friend_initial_1)
        bindFriendRow(context, views, friends, 1, R.id.friend_row_2, R.id.friend_name_2, R.id.friend_status_2, R.id.friend_initial_2)
        bindFriendRow(context, views, friends, 2, R.id.friend_row_3, R.id.friend_name_3, R.id.friend_status_3, R.id.friend_initial_3)

        // Whole-widget fallback tap -> feed. The friend rows that are tappable override this.
        views.setOnClickPendingIntent(R.id.state2_root, route(context, "/feed"))
        views.setOnClickPendingIntent(R.id.see_all, route(context, "/feed"))
        return views
    }

    private fun bindFriendRow(
        context: Context,
        views: RemoteViews,
        friends: List<Friend>,
        index: Int,
        rowId: Int,
        nameId: Int,
        statusId: Int,
        initialId: Int,
    ) {
        val friend = friends.getOrNull(index)
        if (friend == null) {
            views.setViewVisibility(rowId, View.GONE)
            return
        }
        views.setViewVisibility(rowId, View.VISIBLE)
        views.setTextViewText(nameId, friend.name)
        views.setTextViewText(initialId, friend.initial())

        if (friend.submitted) {
            views.setTextViewText(statusId, context.getString(R.string.widget_guess))
            // Placeholder tile + name; thumbnails are a followUp (async bitmap fetch not done in v1).
            views.setOnClickPendingIntent(rowId, route(context, "/guess/${friend.uid}"))
        } else {
            views.setTextViewText(statusId, context.getString(R.string.widget_waiting))
            // Non-submitted friend falls through to the whole-widget feed tap.
            views.setOnClickPendingIntent(rowId, route(context, "/feed"))
        }
    }

    /** State 3: user drew AND guessed everyone available — show streak / day / summary. */
    private fun buildStateDone(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.pictionary_widget_state3)
        val streak = data.getInt("w_streak", 0)
        val day = data.getInt("w_day", 0)
        val solved = data.getInt("w_solved", 0)
        val total = data.getInt("w_total", 0)

        views.setTextViewText(R.id.streak_value, streak.toString())
        views.setTextViewText(R.id.day_value, context.getString(R.string.widget_day_label, day))
        views.setTextViewText(R.id.summary_value, context.getString(R.string.widget_summary, solved, total))

        views.setOnClickPendingIntent(R.id.state3_root, route(context, "/results"))
        return views
    }

    /** Build a deep-link PendingIntent for a go_router location. */
    private fun route(context: Context, location: String) =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("pictionary://open?route=" + Uri.encode(location)),
        )

    private fun parseStringArray(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { arr.optString(it, null) }.filter { it.isNotBlank() }
        } catch (e: JSONException) {
            emptyList()
        }
    }

    private fun parseFriends(raw: String?): List<Friend> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val obj = arr.optJSONObject(i) ?: return@mapNotNull null
                val uid = obj.optString("uid", "")
                if (uid.isBlank()) return@mapNotNull null
                Friend(
                    uid = uid,
                    name = obj.optString("name", "").ifBlank { "Friend" },
                    thumbUrl = obj.optString("thumbUrl", ""),
                    submitted = obj.optBoolean("submitted", false),
                )
            }
        } catch (e: JSONException) {
            emptyList()
        }
    }

    private data class Friend(
        val uid: String,
        val name: String,
        val thumbUrl: String,
        val submitted: Boolean,
    ) {
        fun initial(): String = name.trim().firstOrNull()?.uppercase() ?: "?"
    }

    companion object {
        private const val STATE_NOT_DRAWN = 1
        private const val STATE_GUESSING = 2
        private const val STATE_DONE = 3
    }
}
