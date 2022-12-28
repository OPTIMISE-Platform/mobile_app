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
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.JsonPrimitive

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
    
    companion object {
        fun fromJSONList(json: String): MutableList<DeviceState> {
            val arr = JsonParser.parseString(json).asJsonArray
            val l = mutableListOf<DeviceState>()
            for (e in arr) {
                l.add(DeviceState(e.toString()))
            }
            return l
        }
        
        fun toJSONList(l: List<DeviceState>): String {
            val arr = JsonArray()
            for (e in l) {
                arr.add(e.getJSONTree())
            }
            return arr.toString()
        }
    }


    fun getId(): String {
        var tree = getJSONTree()
        if (tree.has("value"))
            tree.remove("value")
        if (tree.has("isControlling"))
            tree.remove("isControlling")
        if (tree.has("transitioning"))
            tree.remove("transitioning")
        return tree.toString()
    }

    constructor(id: String) {
        val base = JsonParser.parseString(id).asJsonObject

        if (base.get("deviceId") != null && !base.get("deviceId").isJsonNull)
            deviceId = base.get("deviceId").asString

        if (base.get("groupId") != null && !base.get("groupId").isJsonNull)
            groupId = base.get("groupId").asString

        if (base.get("functionId") != null && !base.get("functionId").isJsonNull)
            functionId = base.get("functionId").asString

        if (base.get("aspectId") != null && !base.get("aspectId").isJsonNull)
            aspectId = base.get("aspectId").asString

        if (base.get("path") != null && !base.get("path").isJsonNull)
            path = base.get("path").asString

        if (base.get("deviceClassId") != null && !base.get("deviceClassId").isJsonNull)
            deviceClassId = base.get("deviceClassId").asString

        if (base.get("serviceGroupKey") != null && !base.get("serviceGroupKey").isJsonNull)
            serviceGroupKey = base.get("serviceGroupKey").asString

        if (base.get("serviceId") != null && !base.get("serviceId").isJsonNull)
            serviceId = base.get("serviceId").asString

        if (base.get("name") != null && !base.get("name").isJsonNull)
            name = base.get("name").asString

        if (base.get("serviceGroupName") != null && !base.get("serviceGroupName").isJsonNull)
            serviceGroupName = base.get("serviceGroupName").asString
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

    fun toJSON(): String {
        return getJSONTree().toString()
    }

    private fun getJSONTree(): JsonObject {
        val obj = JsonObject()

        if (deviceId != null)
            obj.add("deviceId", JsonPrimitive(deviceId))
        if (groupId != null)
            obj.add("groupId", JsonPrimitive(groupId))
        if (functionId != null)
            obj.add("functionId", JsonPrimitive(functionId))
        if (aspectId != null)
            obj.add("aspectId", JsonPrimitive(aspectId))
        if (path != null)
            obj.add("path", JsonPrimitive(path))
        if (deviceClassId != null)
            obj.add("deviceClassId", JsonPrimitive(deviceClassId))
        if (serviceGroupKey != null)
            obj.add("serviceGroupKey", JsonPrimitive(serviceGroupKey))
        if (serviceId != null)
            obj.add("serviceId", JsonPrimitive(serviceId))
        if (name != null)
            obj.add("name", JsonPrimitive(name))
        if (serviceGroupName != null)
            obj.add("serviceGroupName", JsonPrimitive(serviceGroupName))
        if (value != null)
            obj.add("value", JsonPrimitive(value as? Boolean))
        if (isControlling != null)
            obj.add("isControlling", JsonPrimitive(isControlling))
        if (transitioning != null)
            obj.add("transitioning", JsonPrimitive(transitioning))
        return obj
    }
}
