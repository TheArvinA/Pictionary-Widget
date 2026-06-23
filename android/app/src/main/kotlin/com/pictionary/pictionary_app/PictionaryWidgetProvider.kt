package com.pictionary.pictionary_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONException
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

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
        val state = widgetData.getInt("w_state", STATE_NOT_DRAWN)
        // Friends are parsed once for state 2 so the synchronous render and the
        // async thumbnail pass below agree on row index -> friend mapping.
        val friends = if (state == STATE_GUESSING) {
            parseFriends(widgetData.getString("w_friends", null))
        } else {
            emptyList()
        }

        for (appWidgetId in appWidgetIds) {
            val views = when (state) {
                STATE_GUESSING -> buildStateGuessing(context, friends)
                STATE_DONE -> buildStateDone(context, widgetData)
                else -> buildStateNotDrawn(context, widgetData)
            }
            // Render immediately with initials so the widget never waits on the network.
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        // State 2 only: now that initials are on screen, asynchronously fetch each
        // submitted friend's drawing thumbnail and swap it in. Off the main thread.
        if (state == STATE_GUESSING) {
            loadFriendThumbnailsAsync(context, appWidgetManager, appWidgetIds, friends)
        }
    }

    /**
     * Downloads each submitted friend's drawing off the main thread, decodes it
     * downscaled, and pushes it into the matching row's ImageView.
     *
     * Composition with the home_widget base: this 4-arg [onUpdate] is invoked by
     * [HomeWidgetProvider.onUpdate] which itself runs inside [AppWidgetProvider.onReceive]
     * (an ordinary BroadcastReceiver dispatch). We therefore call [goAsync] HERE to keep
     * the broadcast alive past the synchronous render, hand the work to a background
     * Executor, and [android.content.BroadcastReceiver.PendingResult.finish] exactly once
     * when the batch completes or times out — so we never block/ANR the receiver thread.
     */
    private fun loadFriendThumbnailsAsync(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        friends: List<Friend>,
    ) {
        // Build the work list: only the visible drawing cells that are submitted with a
        // url. Mirrors the synchronous bind order in buildStateGuessing — including the
        // overflow rule, so we never load a thumbnail over the "see all" tile.
        val submitted = friends.filter { it.submitted }
        val overflow = submitted.size > MAX_CELLS
        val lastDrawingCell = if (overflow) MAX_CELLS - 1 else MAX_CELLS
        val jobs = ArrayList<Pair<Int, Friend>>(MAX_CELLS)
        for (index in 0 until lastDrawingCell) {
            val friend = submitted.getOrNull(index) ?: continue
            if (friend.thumbUrl.isNotBlank()) {
                jobs.add(index to friend)
            }
        }
        if (jobs.isEmpty()) return

        // goAsync() returns a PendingResult that keeps the broadcast (and process) alive
        // while our background thread works. We do NOT block the receiver thread here: it
        // returns immediately and the worker calls finish() when done. The system allows a
        // goAsync receiver ~10s, so we cap our own work at THUMB_BUDGET_SECONDS to stay under it.
        val pendingResult = goAsync()
        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(THUMB_BUDGET_SECONDS)
            try {
                for ((index, friend) in jobs) {
                    // Respect the overall budget so a stalled download can't run past the
                    // goAsync window; remaining rows simply keep their initial fallback.
                    if (System.nanoTime() > deadline) break

                    val bmp = try {
                        downloadDownscaled(friend.thumbUrl)
                    } catch (e: Throwable) {
                        null // Any download/decode failure -> leave the initial fallback.
                    } ?: continue

                    // Apply this single thumbnail across every widget instance and re-push.
                    for (appWidgetId in appWidgetIds) {
                        try {
                            val views = RemoteViews(context.packageName, R.layout.pictionary_widget_state2)
                            views.setImageViewBitmap(THUMB_IDS[index], bmp)
                            views.setViewVisibility(THUMB_IDS[index], View.VISIBLE)
                            views.setViewVisibility(INITIAL_IDS[index], View.GONE)
                            // partiallyUpdate so we touch ONLY this row, never clobbering names,
                            // statuses, click intents, or already-loaded sibling thumbnails.
                            appWidgetManager.partiallyUpdateAppWidget(appWidgetId, views)
                        } catch (e: Throwable) {
                            // Ignore a single failed push; other rows/instances still update.
                        }
                    }
                }
            } catch (e: Throwable) {
                // Never crash the background pass; initials remain as the fallback.
            } finally {
                try {
                    pendingResult.finish()
                } catch (e: Throwable) {
                    // finish() may already have run; safe to ignore.
                }
                executor.shutdown()
            }
        }
    }

    /**
     * HTTPS GET + downscaled decode using only the Android stdlib. Firebase Storage
     * download URLs are tokenized + public, so a plain GET needs no auth header.
     * Returns null on any non-200, oversized, or undecodable response.
     */
    private fun downloadDownscaled(rawUrl: String): Bitmap? {
        val bytes = fetchBytes(rawUrl) ?: return null

        // Pass 1: bounds only, to compute an inSampleSize that targets ~THUMB_TARGET_PX.
        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, boundsOpts)
        if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = computeSampleSize(boundsOpts.outWidth, boundsOpts.outHeight, THUMB_TARGET_PX)
            inPreferredConfig = Bitmap.Config.RGB_565 // Half the IPC payload of ARGB_8888.
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOpts)
    }

    private fun fetchBytes(rawUrl: String): ByteArray? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(rawUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
            }
            if (conn.responseCode != HttpURLConnection.HTTP_OK) return null
            conn.inputStream.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(8 * 1024)
                var total = 0
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                    if (total > MAX_DOWNLOAD_BYTES) return null // Guard against huge bodies.
                    out.write(buffer, 0, read)
                }
                out.toByteArray()
            }
        } catch (e: Throwable) {
            null
        } finally {
            try {
                conn?.disconnect()
            } catch (e: Throwable) {
                // ignore
            }
        }
    }

    /** Largest power-of-two sample size that keeps both dimensions >= [target]. */
    private fun computeSampleSize(width: Int, height: Int, target: Int): Int {
        var sample = 1
        var w = width
        var h = height
        while (w / 2 >= target && h / 2 >= target) {
            w /= 2
            h /= 2
            sample *= 2
        }
        return sample
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

    /**
     * State 2: user drew; show friends' DRAWINGS in a static 2-wide grid so they can
     * be guessed. Only friends who actually submitted are shown (waiting friends are
     * hidden — the whole grid is dominated by drawings). Capped at [MAX_CELLS]; if more
     * than that submitted, the last cell becomes a "see all in feed" overflow affordance.
     */
    private fun buildStateGuessing(context: Context, friends: List<Friend>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.pictionary_widget_state2)

        // Drawings dominate: render submitted friends only, in order.
        val submitted = friends.filter { it.submitted }
        val overflow = submitted.size > MAX_CELLS

        for (index in 0 until MAX_CELLS) {
            // When there are more submitted friends than cells, reserve the LAST cell
            // as a "see all" overflow tile instead of a friend.
            val isOverflowCell = overflow && index == MAX_CELLS - 1
            val friend = if (isOverflowCell) null else submitted.getOrNull(index)
            bindFriendCell(context, views, friend, index, isOverflowCell)
        }

        // Whole-widget fallback tap -> feed. Tappable cells override this.
        views.setOnClickPendingIntent(R.id.state2_root, route(context, "/feed"))
        return views
    }

    private fun bindFriendCell(
        context: Context,
        views: RemoteViews,
        friend: Friend?,
        index: Int,
        isOverflowCell: Boolean,
    ) {
        val cellId = CELL_IDS[index]
        val nameId = NAME_IDS[index]
        val initialId = INITIAL_IDS[index]
        val thumbId = THUMB_IDS[index]

        // Overflow tile: a "see all" affordance routing to the feed.
        if (isOverflowCell) {
            views.setViewVisibility(cellId, View.VISIBLE)
            views.setViewVisibility(thumbId, View.GONE)
            views.setViewVisibility(initialId, View.VISIBLE)
            views.setTextViewText(initialId, "+")
            views.setTextViewText(nameId, context.getString(R.string.widget_see_more))
            views.setOnClickPendingIntent(cellId, route(context, "/feed"))
            return
        }

        if (friend == null) {
            views.setViewVisibility(cellId, View.GONE)
            return
        }

        views.setViewVisibility(cellId, View.VISIBLE)
        views.setTextViewText(nameId, friend.name)
        views.setTextViewText(initialId, friend.initial())
        // Initial is the synchronous fallback; the async pass swaps in the thumbnail
        // (thumb VISIBLE / initial GONE) only once a bitmap actually decodes.
        views.setViewVisibility(initialId, View.VISIBLE)
        views.setViewVisibility(thumbId, View.GONE)

        // Every submitted cell taps straight into THAT friend's guess screen.
        views.setOnClickPendingIntent(cellId, route(context, "/guess/${friend.uid}"))
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

        /** Number of friend cells the state-2 grid renders (2 cols x 3 rows). */
        private const val MAX_CELLS = 6

        /** Cell index -> view ids, so the async pass and the layout stay in lock-step. */
        private val CELL_IDS = intArrayOf(
            R.id.friend_cell_1, R.id.friend_cell_2, R.id.friend_cell_3,
            R.id.friend_cell_4, R.id.friend_cell_5, R.id.friend_cell_6,
        )
        private val THUMB_IDS = intArrayOf(
            R.id.friend_thumb_1, R.id.friend_thumb_2, R.id.friend_thumb_3,
            R.id.friend_thumb_4, R.id.friend_thumb_5, R.id.friend_thumb_6,
        )
        private val INITIAL_IDS = intArrayOf(
            R.id.friend_initial_1, R.id.friend_initial_2, R.id.friend_initial_3,
            R.id.friend_initial_4, R.id.friend_initial_5, R.id.friend_initial_6,
        )
        private val NAME_IDS = intArrayOf(
            R.id.friend_name_1, R.id.friend_name_2, R.id.friend_name_3,
            R.id.friend_name_4, R.id.friend_name_5, R.id.friend_name_6,
        )

        /**
         * Target min edge (px) for the decoded thumbnail. RemoteViews bitmaps cross an
         * IPC transaction with a hard size limit, so we keep them small (~96px @ RGB_565).
         */
        private const val THUMB_TARGET_PX = 96

        /** Total budget for the whole thumbnail batch before we stop waiting. */
        private const val THUMB_BUDGET_SECONDS = 8L

        private const val CONNECT_TIMEOUT_MS = 4000
        private const val READ_TIMEOUT_MS = 4000

        /** Sanity cap on a single drawing download (raw bytes), before decode. */
        private const val MAX_DOWNLOAD_BYTES = 4 * 1024 * 1024
    }
}
