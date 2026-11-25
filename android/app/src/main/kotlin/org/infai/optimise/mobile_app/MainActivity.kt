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

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        // the notifier sends notifications with "silent": true on this channel; a notification on a
        // channel the app has not created falls back to the default channel and plays its sound
        const val SILENT_CHANNEL_ID = "silent"
    }

    var delayedIntent: Intent? = null

    @RequiresApi(Build.VERSION_CODES.R)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSilentChannel()
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

    // low importance: shown in the shade and as an icon, without sound, vibration or heads-up, so
    // that a notification updated every minute does not alert each time
    private fun createSilentChannel() {
        val channel = NotificationChannel(SILENT_CHANNEL_ID, getString(R.string.silent_channel_name), NotificationManager.IMPORTANCE_LOW)
        channel.description = getString(R.string.silent_channel_description)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun handleIntent(intent: Intent) {
        val deviceId = intent.getStringExtra(DeviceState.DETAIL_PAGE_EXTRA)
        val groupId = intent.getStringExtra(DeviceState.GROUP_DETAIL_PAGE_EXTRA)
        io.flutter.Log.d("MainActivity", "Extras device: " + deviceId + ", group: " + groupId)

        val channel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "flutter/controlMethodChannel")
        if (groupId != null) {
            channel.invokeMethod("openDetailPage", mapOf("groupId" to groupId))
        } else if (deviceId != null) {
            channel.invokeMethod("openDetailPage", deviceId)
        }
    }
}
