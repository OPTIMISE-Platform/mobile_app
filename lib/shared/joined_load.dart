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

/// Lets concurrent calls of a loader share one run, and its outcome.
///
/// A caller arriving while a run is in flight gets that run's result, not an
/// assumed success: the settings refresh reported "Cache refreshed" over a
/// joined load that had failed.
class JoinedLoad {
  Future<bool>? _running;

  Future<bool> run(Future<bool> Function() load) =>
      _running ??= load().whenComplete(() => _running = null);
}
