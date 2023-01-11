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

import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mutex/mutex.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../exceptions/no_network_exception.dart';
import 'cache_helper.dart';

class AppUpdater {
  static final _client = http.Client();
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
    if (_foundUpdate != null && _foundUpdateAt != null && _foundUpdateAt!.add(cacheAge).isAfter(DateTime.now())) {
      return _foundUpdate;
    }
  }

  static Future<bool?> updateAvailable({Duration cacheAge = Duration.zero}) async {
    if (!updateSupported) return false;

    if (updateCheckMutex.isLocked) {
      return null;
    }

    if (_foundUpdate != null && _foundUpdateAt != null && _foundUpdateAt!.add(cacheAge).isAfter(DateTime.now())) {
      return _foundUpdate;
    }

    return await updateCheckMutex.protect(() async {
      ConnectivityResult connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult == ConnectivityResult.none) throw NoNetworkException();

      final cacheFile = await CacheHelper.getCacheFile(customSuffix: "_appUpdater_");

      if (cacheFile != null && cacheAge == Duration.zero) {
        HiveCacheStore(cacheFile).clean();
      }

      final options = CacheOptions(
        store: HiveCacheStore(cacheFile),
        policy: CachePolicy.forceCache,
        hitCacheOnErrorExcept: [401, 403],
        maxStale: cacheAge,
        priority: CachePriority.normal,
        keyBuilder: CacheHelper.bodyCacheIDBuilder,
      );

      final url = "https://api.github.com/repos/${dotenv.env["GITHUB_REPO"]!}/releases?per_page=1";

      final dio = Dio(BaseOptions(
          connectTimeout: 5000,
          sendTimeout: 5000,
          receiveTimeout: 5000,
          headers: {"User-Agent": dotenv.env["GITHUB_REPO"] ?? "" + "/" + (dotenv.env["VERSION"] ?? "")}))
        ..interceptors.add(DioCacheInterceptor(options: options));
      final Response<List<dynamic>> resp;
      try {
        resp = await dio.get<List<dynamic>>(url);
      } on DioError catch (e) {
        if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
          throw UnexpectedStatusCodeException(e.response?.statusCode, url);
        }
        rethrow;
      }

      final decoded = (resp.data?[0] ?? {}) as Map<String, dynamic>;
      latestBuild = int.parse((decoded["tag_name"] as String).split("+")[1]);
      currentBuild = int.parse(dotenv.env["VERSION"]!.split("+")[1]);

      _foundUpdateAt = DateTime.now();

      if (latestBuild > currentBuild) {
        final asset = (decoded["assets"] as List<dynamic>).firstWhere((element) => element["name"] == "app-release.apk");
        updateUrl = asset["browser_download_url"];
        downloadSize = asset["size"];
        updateDate = DateTime.parse(asset["updated_at"]);
        return _foundUpdate = true;
      }
      return _foundUpdate = false;
    });
  }

  static Stream<double> downloadUpdate() async* {
    var uri = Uri.parse(updateUrl);
    if (updateUrl.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }

    final req = http.Request('GET', uri);
    final resp = _client.send(req);
    localFile = '${(await getApplicationSupportDirectory()).path}/update.apk';

    final List<List<int>> chunks = [];
    int downloaded = 0;
    double percentage = 0;

    await for (final r in resp.asStream()) {
      if (r.statusCode != 200) {
        throw UnexpectedStatusCodeException(r.statusCode, updateUrl);
      }

      await for (final chunk in r.stream) {
        percentage = downloaded / r.contentLength! * 100;
        yield percentage;
        chunks.add(chunk);
        downloaded += chunk.length;
      }

      percentage = downloaded / r.contentLength! * 100;
      yield percentage;

      File file = File(localFile);
      final Uint8List bytes = Uint8List(r.contentLength!);
      int offset = 0;
      for (List<int> chunk in chunks) {
        bytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      await file.writeAsBytes(bytes);
    }
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
                  Text("Uploaded: ${DateFormat.yMd().add_jms().format(updateDate.toLocal())}"),
                  Text("Download size: ${(downloadSize / 1000000.0).toStringAsFixed(1)} MB"),
                ],
              ),
              actions: [
                PlatformDialogAction(
                  child: PlatformText('Cancel'),
                  onPressed: () => Navigator.pop(context, false),
                ),
                PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, true))
              ],
            ));
    if (proceed != true) {
      return;
    }
    final stream = downloadUpdate().asBroadcastStream();
    stream.listen(null, onDone: () => OpenFile.open(localFile));
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
                  onPressed: snapshot.data == 100 ? () => OpenFile.open(localFile) : null,
                  child: PlatformText(snapshot.data == 100 ? 'Install' : 'Downloading...')))
        ],
      ),
    );
  }
}
