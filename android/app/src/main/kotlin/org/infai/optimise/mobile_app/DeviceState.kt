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

import android.app.PendingIntent
import android.os.Build
import android.service.controls.Control
import android.service.controls.DeviceTypes
import android.service.controls.templates.ControlButton
import android.service.controls.templates.ToggleTemplate
import androidx.annotation.RequiresApi
import com.google.gson.Gson

class DeviceState {
    var deviceId: String? = null
    var groupId: String? = null
    var functionId: String? = null
    var aspectId: String? = null
    var path: String? = null
    var deviceClassId: String? = null
    var serviceGroupKey: String? = null
    var serviceId: String? = null
    var name: String? = null
    var serviceGroupName: String? = null

    var value: Any? = null
    var isControlling: Boolean = false
    var transitioning: Boolean = false


    fun getId(): String {
        var tree = Gson().toJsonTree(this).asJsonObject;
        tree.remove("value")
        tree.remove("isControlling")
        tree.remove("transitioning")
        return tree.toString()
    }

    constructor(id: String) {
        val base = Gson().fromJson(id, DeviceState::class.java)
        deviceId = base.deviceId
        groupId = base.groupId
        functionId = base.functionId
        aspectId = base.aspectId
        path = base.path
        deviceClassId = base.deviceClassId
        serviceGroupKey = base.serviceGroupKey
        serviceId = base.serviceId
        name = base.name
        serviceGroupName = base.serviceGroupName
    }

    @RequiresApi(Build.VERSION_CODES.R)
    fun statelessToggleControl(pi: PendingIntent): Control {
        var subtitle = ""
        var title = ""
        if (name != null) {
            title = name!!
        }
        if (serviceGroupName != null) {
            subtitle = serviceGroupName!!
        }
        return Control.StatelessBuilder(getId(), pi)
            // Required: The name of the control
            .setTitle(title)
            // Required: Usually the room where the control is located
            .setSubtitle(subtitle)
            // Required: Type of device, i.e., thermostat, light, switch
            .setDeviceType(DeviceTypes.TYPE_LIGHT) // For example, DeviceTypes.TYPE_THERMOSTAT
            .build()
    }

    @RequiresApi(Build.VERSION_CODES.R)
    fun statefulToggleControl(pi: PendingIntent): Control {
        var title = ""
        var subtitle = ""
        if (name != null) {
            title = name!!
        }
        if (serviceGroupName != null) {
            subtitle = serviceGroupName!!
        }
        return Control.StatefulBuilder(getId(), pi)
            // Required: The name of the control
            .setTitle(title)
            // Required: Usually the room where the control is located
            .setSubtitle(subtitle)
            // Required: Type of device, i.e., thermostat, light, switch
            .setDeviceType(DeviceTypes.TYPE_LIGHT) // For example, DeviceTypes.TYPE_THERMOSTAT
            .setStatus(Control.STATUS_OK)
            .setControlTemplate(
                ToggleTemplate(
                    "", ControlButton(
                        value.toString().toBoolean(),
                        "Toggle switch"
                    )
                )
            )
            .build()
    }
}
