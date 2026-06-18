package com.pictionary.pictionary_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // On a warm relaunch the activity already exists (launchMode=singleTop), so the
    // widget's deep-link arrives as a new intent here rather than as a fresh launch.
    // Forward it to super so the v2-embedding plugins run their NewIntentListeners —
    // home_widget's listener feeds the `widgetClicked` stream that drives
    // app.dart's _openFromWidget. setIntent keeps getIntent() current so
    // initiallyLaunchedFromHomeWidget also reads the latest intent on warm starts.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
