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

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:http_cache_hive_store/http_cache_hive_store.dart';import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mutex/mutex.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mobile_app/services/cache_helper.dart';

import '../shared/api_available_interceptor.dart';

class AppUpdater {

  static final githubHeaders = {
    "User-Agent": dotenv.env["GITHUB_REPO"] ??
        "/${dotenv.env["VERSION"] ?? ""}"
  };


  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static final updateSupported = _updateSupported();

  static late int currentBuild;
  static late int latestBuild;
  static late int downloadSize;
  static late DateTime updateDate;

  static late String updateUrl;
  static late String localFile;

  static final updateCheckMutex = Mutex();

  static bool? _foundUpdate;
  static DateTime? _foundUpdateAt;

  static cleanup() async {
    if (kIsWeb) return;
    final f = '${(await getApplicationSupportDirectory()).path}/update.apk';
    final file = File(f);
    if (await file.exists()) {
      try {
        await file.delete(recursive: true);
      } catch (e) {
        _logger.e("Can't cleanup update file $e");
      }
    }
  }

  static bool _updateSupported() {
    if (!kIsWeb &&
        Platform.isAndroid &&
        dotenv.env["DISTRIBUTOR"] == "github" &&
        dotenv.env["GITHUB_REPO"] != null &&
        dotenv.env["VERSION"] != null) {
      return true;
    }
    return false;
  }

  static bool? updateAvailableSync({Duration cacheAge = Duration.zero}) {
    if (!Settings.getLocalMode() &&
        _foundUpdate != null &&
        _foundUpdateAt != null &&
        _foundUpdateAt!.add(cacheAge).isAfter(DateTime.now())) {
      return _foundUpdate;
    }
    return null;
  }

  static Future<bool?> updateAvailable({Duration cacheAge = Duration.zero}) async {
    if (Settings.getLocalMode() || !updateSupported) return false;

    if (updateCheckMutex.isLocked) {
      return null;
    }

    if (_foundUpdate != null &&
        _foundUpdateAt != null &&
        _foundUpdateAt!.add(cacheAge).isAfter(DateTime.now())) {
      return _foundUpdate;
    }

    return await updateCheckMutex.protect(() async {
      final cacheFile =
          await CacheHelper.getCacheFile(customSuffix: "_appUpdater_");

      if (cacheFile != null && cacheAge == Duration.zero) {
        await HiveCacheStore(cacheFile).clean();
      }

      final options = CacheOptions(
        store: HiveCacheStore(cacheFile),
        policy: CachePolicy.forceCache,
        maxStale: cacheAge,
        priority: CachePriority.normal,
        keyBuilder: CacheHelper.newCacheKeyBuilder,
      );

      var url =
          "https://api.github.com/repos/${dotenv.env["GITHUB_REPO"]!}/releases/latest";
      if (Settings.getPreReleaseMode()){
        url =
        "https://api.github.com/repos/${dotenv.env["GITHUB_REPO"]!}/releases?per_page=1";
      }

      //TODO: switch to factory
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(milliseconds: 5000),
          sendTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 5000),
          headers: githubHeaders))
        ..interceptors.add(DioCacheInterceptor(options: options))
        ..interceptors.add(ApiAvailableInterceptor());

      Map decoded;
      if (Settings.getPreReleaseMode()){
        final Response<List<dynamic>> resp;
        try {
          resp = await dio.get<List<dynamic>>(url);
        } on DioException catch (e) {
          _logger.e(
              "Update check failed: $url ${e.message} (status ${e.response?.statusCode})");
          return null; // couldn't determine — surface as "check again later"
        }
        decoded = (resp.data?[0] ?? {}) as Map<String, dynamic>;
      } else {
        final Response<dynamic> resp;
        try {
          resp = await dio.get<dynamic>(url);
        } on DioException catch (e) {
          _logger.e(
              "Update check failed: $url ${e.message} (status ${e.response?.statusCode})");
          return null; // couldn't determine — surface as "check again later"
        }
        decoded = (resp.data ?? {}) as Map<dynamic, dynamic>;
      }
      latestBuild = int.parse((decoded["tag_name"] as String).split("+")[1]);
      currentBuild = int.parse(dotenv.env["VERSION"]!.split("+")[1]);

      _foundUpdateAt = DateTime.now();

      if (latestBuild > currentBuild) {
        final asset = (decoded["assets"] as List<dynamic>)
            .firstWhere((element) => element["name"] == "app-release.apk");
        updateUrl = asset["browser_download_url"];
        downloadSize = asset["size"];
        updateDate = DateTime.parse(asset["updated_at"]);
        return _foundUpdate = true;
      }
      return _foundUpdate = false;
    });
  }

  static Future<Stream<double>> downloadUpdate() async {
    final dio = await DioFactory.create(DioConfig.standard);
    // Per-request headers: setHeaders wrote them permanently into the shared
    // standard instance, so every later platform request carried them too.
    final head = await dio.head(updateUrl, options: Options(headers: githubHeaders));
    final redirectedUpdateUrl = head.redirects.last.location;
    final controller = StreamController<double>();

    localFile = '${(await getApplicationSupportDirectory()).path}/update.apk';
    dio.download(redirectedUpdateUrl.toString(), localFile, options: Options(headers: githubHeaders), onReceiveProgress: (received, total) {
      if (total != -1) {
        controller.add(received / total * 100);
      }
    }).then((value) => controller.close());
    return controller.stream;
  }

  static showUpdateDialog(BuildContext context) async {
    final proceed = await showPlatformDialog(
        context: context,
        builder: (context) => PlatformAlertDialog(
              title: const Text("Update now?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Current Build: ${currentBuild}"),
                  Text("Latest Build: ${latestBuild}"),
                  Text(
                      "Uploaded: ${DateFormat.yMd().add_jms().format(updateDate.toLocal())}"),
                  Text(
                      "Download size: ${(downloadSize / 1000000.0).toStringAsFixed(1)} MB"),
                ],
              ),
              actions: [
                PlatformDialogAction(
                  child: PlatformText('Cancel'),
                  onPressed: () => Navigator.pop(context, false),
                ),
                PlatformDialogAction(
                    child: PlatformText('OK'),
                    onPressed: () => Navigator.pop(context, true))
              ],
            ));
    if (proceed != true) {
      return;
    }
    final stream = (await downloadUpdate()).asBroadcastStream();
    stream.listen(null, onDone: () => OpenFilex.open(localFile));
    await showPlatformDialog(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: const Text("Update"),
        content: StreamBuilder<double>(
            stream: stream,
            initialData: 0,
            builder: (context, snapshot) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                LinearProgressIndicator(value: snapshot.data! / 100),
                Text("${snapshot.data!.toStringAsFixed(2)} %"),
              ]);
            }),
        actions: [
          StreamBuilder<double>(
              stream: stream,
              initialData: 0,
              builder: (context, snapshot) => PlatformDialogAction(
                  onPressed: snapshot.data == 100
                      ? () => OpenFilex.open(localFile)
                      : null,
                  child: PlatformText(
                      snapshot.data == 100 ? 'Install' : 'Downloading...')))
        ],
      ),
    );
  }
}
