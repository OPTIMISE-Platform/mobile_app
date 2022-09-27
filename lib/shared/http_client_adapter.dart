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


import "fake_browser_adapter.dart" if (dart.library.html) 'package:dio/adapter_browser.dart';
import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:flutter/foundation.dart';

import '../app_state.dart';

class AppHttpClientAdapter implements HttpClientAdapter {
  late final HttpClientAdapter _adapter;

  AppHttpClientAdapter() {
    _adapter =  kIsWeb ?  BrowserHttpClientAdapter() : Http2Adapter(AppState.connectionManager);
  }

  @override
  void close({bool force = false}) {
    _adapter.close(force: force);
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future? cancelFuture) {
    return _adapter.fetch(options, requestStream, cancelFuture);
  }

}
