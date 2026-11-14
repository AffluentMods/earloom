// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

package com.affluentlabs.earloom.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import com.affluentlabs.earloom.MainActivity
import com.affluentlabs.earloom.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * The Now playing home screen widget. It only shows what the app last wrote
 * (lib/platform/widget_bridge.dart) and sends media buttons to the playback
 * service. It never talks to a server.
 */
class NowPlayingWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context, widgetData))
        }
    }

    private fun build(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_now_playing)
        val hasBook = data.getBoolean("np.hasBook", false)
        views.setTextViewText(R.id.widget_title, data.getString("np.title", "") ?: "")
        views.setTextViewText(R.id.widget_subtitle, data.getString("np.subtitle", "") ?: "")
        views.setProgressBar(R.id.widget_progress, 1000, data.getInt("np.progress", 0), false)
        val playing = data.getBoolean("np.playing", false)
        views.setImageViewResource(
            R.id.widget_play,
            if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
        )
        views.setContentDescription(R.id.widget_play, data.getString(if (playing) "l.pause" else "l.play", ""))
        views.setContentDescription(R.id.widget_back, data.getString("l.back", ""))
        val visible = if (hasBook) View.VISIBLE else View.GONE
        views.setViewVisibility(R.id.widget_back, visible)
        views.setViewVisibility(R.id.widget_progress, visible)

        val cover = data.getString("np.cover", null)?.let { File(it) }
        val bitmap = cover?.takeIf { it.exists() }?.let { file ->
            // Decode small: widgets have a tight memory budget.
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 256) sample *= 2
            BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
        }
        if (bitmap != null) {
            views.setImageViewBitmap(R.id.widget_cover, bitmap)
        } else {
            views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
        }

        val open = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            if (hasBook) Uri.parse("earloom://player") else null,
        )
        views.setOnClickPendingIntent(R.id.widget_root, open)
        views.setOnClickPendingIntent(R.id.widget_play, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 1))
        views.setOnClickPendingIntent(R.id.widget_back, mediaButton(context, KeyEvent.KEYCODE_MEDIA_REWIND, 2))
        return views
    }

    /** A media button press for the playback service, as headphones send. */
    private fun mediaButton(context: Context, keyCode: Int, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
