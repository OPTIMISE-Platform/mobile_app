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

class DeviceState {
    var value: Object? = null
    var functionId: String = ""
    var isControlling: Boolean = false
    var transitioning: Boolean  = false
    var serviceId: String? = null
    var serviceGroupKey: String? = null
    var aspectId: String? = null
    var groupId: String? = null
    var deviceClassId: String? = null
    var deviceId: String? = null
    var path: String? = null
    var name: String? = null
    var serviceGroupName: String? = null
}
