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
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.controls.Control
import android.service.controls.DeviceTypes
import android.service.controls.templates.ControlButton
import android.service.controls.templates.RangeTemplate
import android.service.controls.templates.ToggleTemplate
import android.util.Log
import androidx.annotation.RequiresApi
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.JsonPrimitive

class DeviceState(id: String) {
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

    // What the control is and, for a range, how it sets its value. Not part of
    // the control id, see getId.
    var kind: String? = null
    var min: Double? = null
    var max: Double? = null
    var step: Double? = null
    var unit: String? = null
    var integer: Boolean = false

    companion object {
        const val DETAIL_PAGE_EXTRA = "org.infai.optimise.mobile_app.DetailPage"
        const val GROUP_DETAIL_PAGE_EXTRA = "org.infai.optimise.mobile_app.GroupDetailPage"
        const val KIND_RANGE = "range"

        // Fields of the tree that belong to the entry but not to the control id.
        // Android stores the id of every control a user added, so the id must be
        // the same string as before these fields existed: a new field is added at
        // the end of getJSONTree and removed here.
        private val NOT_IN_ID = listOf("value", "isControlling", "transitioning",
                "kind", "min", "max", "step", "unit", "integer")

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
        val tree = getJSONTree()
        for (field in NOT_IN_ID) {
            if (tree.has(field))
                tree.remove(field)
        }
        return tree.toString()
    }

    init {
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
        if (base.get("value") != null && !base.get("value").isJsonNull) {
            if (base.get("value").isJsonPrimitive) {
                val tmpP = base.get("value").asJsonPrimitive
                if (tmpP.isBoolean)
                    value = tmpP.asBoolean
                if (tmpP.isNumber)
                    value = tmpP.asDouble
                if (tmpP.isString)
                    value = tmpP.asString
            } else {
                Log.w("DeviceState", "Value not primitive, cannot parse from JSON: " + base.get("value").toString())
            }
        }
        if (base.get("kind") != null && !base.get("kind").isJsonNull)
            kind = base.get("kind").asString
        if (base.get("min") != null && !base.get("min").isJsonNull)
            min = base.get("min").asDouble
        if (base.get("max") != null && !base.get("max").isJsonNull)
            max = base.get("max").asDouble
        if (base.get("step") != null && !base.get("step").isJsonNull)
            step = base.get("step").asDouble
        if (base.get("unit") != null && !base.get("unit").isJsonNull)
            unit = base.get("unit").asString
        if (base.get("integer") != null && !base.get("integer").isJsonNull)
            integer = base.get("integer").asBoolean
    }

    private fun isRange(): Boolean {
        return kind == KIND_RANGE
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun pi(context: Context): PendingIntent {
        val i = Intent(context, MainActivity::class.java)
        // A control of a group opens the group, any other its device.
        if (deviceId == null && groupId != null) {
            i.putExtra(GROUP_DETAIL_PAGE_EXTRA, this.groupId)
        } else {
            i.putExtra(DETAIL_PAGE_EXTRA, this.deviceId)
        }
        for (key in i.extras!!.keySet()) {
            Log.d("DeviceState", key + " --> " + (this.deviceId ?: this.groupId))
        }
        return PendingIntent.getActivity(context, (deviceId ?: groupId).hashCode(), i, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun title(): String {
        return name ?: ""
    }

    // The service group of a device's reading; a group's has none, so it says
    // that it is one.
    private fun subtitle(): String {
        return serviceGroupName ?: if (groupId != null) "Group" else ""
    }

    private fun deviceType(): Int {
        return if (isRange()) DeviceTypes.TYPE_UNKNOWN else DeviceTypes.TYPE_SWITCH
    }

    @RequiresApi(Build.VERSION_CODES.R)
    fun statelessControl(context: Context): Control {
        return Control.StatelessBuilder(getId(), pi(context))
                // Required: The name of the control
                .setTitle(title())
                // Required: Usually the room where the control is located
                .setSubtitle(subtitle())
                // Required: Type of device, i.e., thermostat, light, switch
                .setDeviceType(deviceType())
                .build()
    }

    @RequiresApi(Build.VERSION_CODES.R)
    fun statefulControl(context: Context): Control {
        val builder = Control.StatefulBuilder(getId(), pi(context))
                .setTitle(title())
                .setSubtitle(subtitle())
                .setDeviceType(deviceType())
        if (isRange()) {
            applyRange(builder)
        } else {
            builder.setStatus(Control.STATUS_OK)
                    .setControlTemplate(
                            ToggleTemplate(
                                    "", ControlButton(
                                    value.toString().toBoolean(),
                                    "Toggle switch"
                            )
                            )
                    )
        }
        return builder.build()
    }

    // RangeTemplate throws when the current value lies outside the range or the
    // step is not positive, so the value is held to the range and a range that
    // cannot be built leaves the control without a template.
    @RequiresApi(Build.VERSION_CODES.R)
    private fun applyRange(builder: Control.StatefulBuilder) {
        val lo = min?.toFloat()
        val hi = max?.toFloat()
        val stepValue = step?.toFloat()
        if (lo == null || hi == null || stepValue == null || !lo.isFinite() || !hi.isFinite() || hi < lo || !(stepValue > 0f)) {
            Log.w("DeviceState", "No usable range for " + getId())
            builder.setStatus(Control.STATUS_UNKNOWN)
            return
        }
        val current = (value as? Number)?.toFloat()?.takeIf { it.isFinite() }
        // The unit may hold a percent sign, which the format would read as a
        // conversion.
        val format = "%." + (if (integer) 0 else 1) + "f" + (unit?.let { " " + it.replace("%", "%%") } ?: "")
        builder.setStatus(if (current == null) Control.STATUS_UNKNOWN else Control.STATUS_OK)
                .setControlTemplate(RangeTemplate("", lo, hi, (current ?: lo).coerceIn(lo, hi), stepValue, format))
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
        when (val v = value) {
            is Boolean -> obj.add("value", JsonPrimitive(v))
            is Number -> obj.add("value", JsonPrimitive(v))
            is String -> obj.add("value", JsonPrimitive(v))
        }
        obj.add("isControlling", JsonPrimitive(isControlling))
        obj.add("transitioning", JsonPrimitive(transitioning))
        // After everything that makes up the id, see NOT_IN_ID.
        if (kind != null)
            obj.add("kind", JsonPrimitive(kind))
        if (min != null)
            obj.add("min", JsonPrimitive(min))
        if (max != null)
            obj.add("max", JsonPrimitive(max))
        if (step != null)
            obj.add("step", JsonPrimitive(step))
        if (unit != null)
            obj.add("unit", JsonPrimitive(unit))
        obj.add("integer", JsonPrimitive(integer))
        return obj
    }
}
