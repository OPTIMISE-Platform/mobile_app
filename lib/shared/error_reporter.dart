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

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/widgets/shared/toast.dart';

/// The one place that decides whether a failure in the state layer reaches the
/// user.
///
/// AppState's mixins and the cache refresh used to call [Toast] directly, once
/// per endpoint. A single offline start therefore queued up ten toasts that all
/// meant the same thing, and the state layer decided UI on its own. Reporting
/// through here keeps every detail in the log, names the shared cause once when
/// the cause is a missing connection, and drops an identical repeat that
/// arrives while the first is still on screen.
///
/// Widgets that respond to something the user just did keep calling [Toast]:
/// that message is about the action, not about a background failure.
class ErrorReporter {
  ErrorReporter._();

  static final _logger = Logger(printer: SimplePrinter());

  /// Shown instead of the endpoint-specific message when the cause is that the
  /// platform cannot be reached. Every failing endpoint maps onto this same
  /// string, which is what collapses the burst into one toast.
  static const offlineMessage = "No connection to the platform";

  /// How long a message keeps an identical follow-up off the screen. Roughly
  /// the time a toast is visible.
  static const _window = Duration(seconds: 5);

  /// Injectable so a test does not have to wait out [_window].
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// The only dependency on the toast, and injectable for the same reason: a
  /// unit test must not reach for the platform channel behind it.
  @visibleForTesting
  static void Function(String) present = Toast.showToastNoContext;

  static String? _lastShown;
  static DateTime? _lastShownAt;

  @visibleForTesting
  static void resetForTest() {
    _lastShown = null;
    _lastShownAt = null;
    clock = DateTime.now;
    present = Toast.showToastNoContext;
  }

  /// Logs [message] with [error] and shows it unless it repeats what is
  /// already on screen.
  static void report(String message, [Object? error]) {
    _logger.e(error == null ? message : "$message: $error");
    _show(isOffline(error) ? offlineMessage : message);
  }

  /// For a failure whose cause is already known to be a missing connection, or
  /// which has no exception to inspect.
  static void reportOffline() => _show(offlineMessage);

  static void _show(String text) {
    final now = clock();
    final last = _lastShownAt;
    if (_lastShown == text && last != null && now.difference(last) < _window) {
      return;
    }
    _lastShown = text;
    _lastShownAt = now;
    present(text);
  }

  /// Whether [error] means the platform could not be reached, as opposed to it
  /// having answered with a refusal.
  static bool isOffline(Object? error) {
    if (error is ApiUnavailableException || error is SocketException) {
      return true;
    }
    // No status code means no response arrived at all.
    if (error is UnexpectedStatusCodeException) return error.code == null;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return true;
        default:
          return isOffline(error.error);
      }
    }
    return false;
  }
}
