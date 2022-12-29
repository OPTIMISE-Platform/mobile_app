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

import android.util.Log
import com.google.gson.*

class DeviceCommandResponse(id: String) {
    var status_code: Int = -1
    var message: Any? = null

    companion object {
        fun fromJSONList(json: String): MutableList<DeviceCommandResponse> {
            val arr = JsonParser.parseString(json).asJsonArray
            val l = mutableListOf<DeviceCommandResponse>()
            for (e in arr) {
                l.add(DeviceCommandResponse(e.toString()))
            }
            return l
        }

        fun toJSONList(l: List<DeviceCommandResponse>): String {
            val arr = JsonArray()
            for (e in l) {
                arr.add(e.getJSONTree())
            }
            return arr.toString()
        }
    }

    init {
        val base = JsonParser.parseString(id).asJsonObject
        if (base.get("status_code") != null && !base.get("status_code").isJsonNull)
            status_code = base.get("status_code").asInt
        if (base.get("message") != null && !base.get("message").isJsonNull) {
            val tmp = base.get("message")
            if (tmp.isJsonPrimitive) {
                val tmpP = tmp.asJsonPrimitive
                if (tmpP.isBoolean)
                    message = tmpP.asBoolean
                if (tmpP.isNumber)
                    message = tmpP.asDouble
                if (tmpP.isString)
                    message = tmpP.asString
            } else {
                Log.w("DeviceCommandResponse", "Value not primitive, cannot parse from JSON: $tmp")
            }
        }
    }

    fun toJSON(): String {
        return getJSONTree().toString()
    }

    private fun getJSONTree(): JsonObject {
        val obj = JsonObject()

        obj.add("status_code", JsonPrimitive(status_code))
        if (message != null) {
            if (message is Boolean)
                obj.add("message", JsonPrimitive(message as Boolean))
            if (message is Int)
                obj.add("message", JsonPrimitive(message as Int))
            if (message is Float)
                obj.add("message", JsonPrimitive(message as Float))
            if (message is String)
                obj.add("message", JsonPrimitive(message as String))
        }
        return obj
    }
}
