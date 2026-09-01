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

import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart' as settings_service;
import 'package:mobile_app/widgets/shared/toast.dart';

/// Settings entry that refreshes all caches and shows the progress inline.
/// While running, the tile is disabled and a determinate bar advances one
/// step per completed refresh task.
class RefreshCacheTile extends StatefulWidget {
  const RefreshCacheTile({super.key});

  @override
  State<RefreshCacheTile> createState() => _RefreshCacheTileState();
}

class _RefreshCacheTileState extends State<RefreshCacheTile> {
  /// null while idle, otherwise overall progress in 0..1.
  double? _progress;

  // Phase boundaries: clearing is quick, then the Isar-collection refresh,
  // then the metadata reload (which fetches against the cleared cache).
  static const _afterClear = 0.05;
  static const _afterRefresh = 0.60;

  Future<void> _refresh() async {
    setState(() => _progress = 0);
    try {
      await CacheHelper.clearCache();
      _setProgress(_afterClear);
      await CacheHelper.refreshCache(
          includeMetadata: false,
          onProgress: (p) =>
              _setProgress(_afterClear + (_afterRefresh - _afterClear) * p));
      await AppState().reloadMetadata(
          onProgress: (p) =>
              _setProgress(_afterRefresh + (1 - _afterRefresh) * p));
      Toast.showToastNoContext("Cache refreshed");
    } catch (e) {
      Toast.showToastNoContext("Could not refresh cache: $e");
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  void _setProgress(double value) {
    // _progress == null means no refresh is running: Future.wait fails fast,
    // so a task surviving a failed refresh still reports progress afterwards
    // and must not re-disable the tile.
    if (mounted && _progress != null) setState(() => _progress = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled =
        settings_service.Settings.getLocalMode() || _progress != null;
    return ListTile(
      title: Text("Refresh Cache",
          style: disabled
              ? TextStyle(color: Theme.of(context).disabledColor)
              : null),
      subtitle: _progress == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: _progress),
            ),
      onTap: disabled ? null : _refresh,
    );
  }
}
