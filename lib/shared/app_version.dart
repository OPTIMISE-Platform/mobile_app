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

import 'package:package_info_plus/package_info_plus.dart';

/// Version and build number of the installed package, as set by
/// `flutter build --build-name --build-number`. Read once at startup.
class AppVersion {
  AppVersion._();

  static PackageInfo? _info;

  static Future<void> init() async {
    _info = await PackageInfo.fromPlatform();
  }

  static String get version => _info?.version ?? "";

  /// Null when the package carries no numeric build number.
  static int? get build => int.tryParse(_info?.buildNumber ?? "");

  /// `version+build`, the form of the release tags.
  static String get display => build == null ? version : "$version+$build";
}
