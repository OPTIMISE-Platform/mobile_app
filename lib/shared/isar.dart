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

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';

import '../models/device_instance.dart';

final Isar? isar = kIsWeb ? null : Isar.openSync([DeviceInstanceSchema, DeviceGroupSchema, NetworkSchema, LocationSchema]);

/// FNV-1a 64bit hash algorithm optimized for Dart Strings
/// Adopted from https://isar.dev/recipes/string_ids.html
var base = int.parse('0xcbf29ce484222325');
int fastHash(String string) {
  var hash = base;

  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }

  return hash;
}
