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

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/shared/isar.dart' as app_isar;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Prepares the test process for services that touch platform channels:
/// initializes the test binding and points path_provider at a fresh temp
/// directory, so Hive/Isar write real files without a device. Call once per
/// test file, e.g. from `setUpAll`.
Directory setUpTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory.systemTemp.createTempSync('mobile_app_test');
  PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  return dir;
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._root);

  final String _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<List<String>?> getExternalCachePaths() async => [_root];
}

/// Opens a fresh Isar instance for [schemas] in a temp directory and makes it
/// the app's global [isar]. Tests calling this carry the `isar` tag, see
/// dart_test.yaml: the core binary needs glibc 2.38.
Future<Isar> openTestIsar(List<CollectionSchema<dynamic>> schemas) async {
  // Under .dart_tool rather than next to the test script, where the default
  // download lands - that is the repository root.
  final library = File('.dart_tool/isar/libisar-${Isar.version}.so');
  library.parent.createSync(recursive: true);
  if (library.existsSync()) {
    await Isar.initializeIsarCore(libraries: {Abi.current(): library.path});
  } else {
    // A missing binary is downloaded, in CI whenever the cache of
    // .dart_tool/isar has expired. Into a file of this process first: suites
    // run in parallel, and Isar writes straight into the target and skips the
    // download once the file exists, so another suite would load it half
    // written. The rename is atomic.
    final download = File('${library.path}.$pid');
    // The test binding answers every HTTP request with 400; a suite that set
    // it up before opening Isar could not download at all.
    final testOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): download.path},
        download: true,
      );
    } finally {
      HttpOverrides.global = testOverrides;
    }
    download.renameSync(library.path);
  }
  final db = await Isar.open(
    schemas,
    directory: Directory.systemTemp.createTempSync('mobile_app_isar').path,
    name: 'test${DateTime.now().microsecondsSinceEpoch}',
  );
  app_isar.isar = db;
  return db;
}
