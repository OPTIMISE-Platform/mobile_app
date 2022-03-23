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


import 'package:mobile_app/models/device_command.dart';

class DeviceState {
  dynamic value;
  String functionId;
  bool isControlling, transitioning = false;
  String? serviceId, serviceGroupKey, aspectId, groupId, deviceClassId, deviceId;

  DeviceState(this.value, this.serviceId, this.serviceGroupKey, this.functionId, this.aspectId, this.isControlling, this.groupId, this.deviceClassId, this.deviceId);

  DeviceCommand toCommand([dynamic value]) {
    return DeviceCommand(functionId, deviceId, serviceId, aspectId, groupId, deviceClassId, value);
  }
}
