/*
 * Copyright 2026 InfAI (CC SES)
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

import 'package:isar_community/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/isar.dart';

/// One-time copy of the favorites that used to live on the cached device and
/// group rows into the per-account lists in [Settings].
///
/// Purely local and offline-safe. It has to run before anything drops the
/// entity cache, because until it has run the rows are the only record.
class FavoritesMigration {
  FavoritesMigration._();

  static final _logger = Logger(printer: SimplePrinter());

  static Future<void> run() async {
    if (isar == null || Settings.getFavoritesMoved()) return;
    // Without an account the lists have no key to be stored under; try again on
    // the next start, once someone is signed in.
    if (Settings.getAccount() == null) return;

    final deviceIds = (await isar!.deviceInstances
            .where()
            .favoriteEqualTo(true)
            .idProperty()
            .findAll())
        .toSet();
    final groupIds = (await isar!.deviceGroups
            .where()
            .favoriteEqualTo(true)
            .idProperty()
            .findAll())
        .toSet();

    // Merge rather than overwrite: a favorite set in this version is already in
    // the list, and the rows may be older than it.
    await Settings.setFavoriteDeviceIds(
        Settings.getFavoriteDeviceIds()..addAll(deviceIds));
    await Settings.setFavoriteGroupIds(
        Settings.getFavoriteGroupIds()..addAll(groupIds));
    await Settings.setFavoritesMoved(true);
    _logger.d(
        "Moved ${deviceIds.length} device and ${groupIds.length} group favorites off the cache");
  }
}
