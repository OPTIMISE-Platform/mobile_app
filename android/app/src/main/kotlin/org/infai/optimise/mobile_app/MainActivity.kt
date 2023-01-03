/*
 * Copyright 2022 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

package org.infai.optimise.mobile_app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    var delayedIntent: Intent? = null

    @RequiresApi(Build.VERSION_CODES.R)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            flutterEngine!!.plugins.add(AppControlsProviderService())
        } catch (e: Exception) {
            io.flutter.Log.e("MainActivity", "Error registering plugin android_control_plugin, org.infai.optimise.mobile_app.AppControlsProviderService", e)
        }
        delayedIntent = intent
    }

    override fun onResume() {
        super.onResume()
        if (delayedIntent != null) {
            handleIntent(delayedIntent!!)
            delayedIntent = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        io.flutter.Log.d("MainActivity", "Extra org.infai.optimise.mobile_app.DetailPage: " + intent.getStringExtra("org.infai.optimise.mobile_app.DetailPage"))

        if (intent.getStringExtra("org.infai.optimise.mobile_app.DetailPage") != null) {
            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "flutter/controlMethodChannel")
                    .invokeMethod("openDetailPage", intent.getStringExtra("org.infai.optimise.mobile_app.DetailPage"))
        }
    }
}
