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

import 'package:dio/dio.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';

/// The highest status a read still treats as usable. No validateStatus is
/// configured, so dio's default rejects everything outside 2xx and a redirect
/// or cache revalidation code reaches the caller as a failure - for a read
/// those are not one.
const _readTolerated = 304;

/// Writes have no revalidation codes: anything past 2xx failed.
const _writeTolerated = 299;

/// Throws [UnexpectedStatusCodeException] unless a read may keep going with
/// this status. Returns normally otherwise, so the call site can `rethrow` and
/// keep the original stack trace.
void checkReadStatus(DioException e, String uri) =>
    _check(e, uri, _readTolerated);

/// The write counterpart of [checkReadStatus].
void checkWriteStatus(DioException e, String uri) =>
    _check(e, uri, _writeTolerated);

/// Whether a response a read got back carries a usable status. For the places
/// that inspect the response instead of catching an exception, which happens
/// where a single failure must not fail a batch.
bool isReadableStatus(int? statusCode) =>
    statusCode != null && statusCode <= _readTolerated;

/// The stricter counterpart of [isReadableStatus], for a response that has to
/// be a plain success. The smart-service dashboard widgets use it: they render
/// whatever came back, so a redirect is no more usable to them than an error.
bool isSuccessStatus(int? statusCode) =>
    statusCode != null && statusCode <= _writeTolerated;

void _check(DioException e, String uri, int tolerated) {
  final code = e.response?.statusCode;
  if (code == null || code > tolerated) {
    throw UnexpectedStatusCodeException(code, "$uri ${e.message}");
  }
}
