/*
 * Copyright 2023 InfAI (CC SES)
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

import 'package:isar_community/isar.dart';
import 'package:logger/logger.dart';

import 'package:mobile_app/shared/isar.dart';
part 'exception_log_element.g.dart';

@collection
class ExceptionLogElement {
  final Id isarId = Isar.autoIncrement;

  final String? message;

  String stack = "";

  @Index()
  final DateTime logTime = DateTime.now().toUtc();

  ExceptionLogElement(this.message, this.stack);

  /// [from] is the trace of the site that caught the failure. Without one the
  /// trace of this call is recorded, which says little - it is the same few
  /// frames every time.
  ExceptionLogElement.Log(this.message, [StackTrace? from]) {
    stack = (from ?? StackTrace.current).toString();
    _persist();
  }

  /// How long a logged entry is kept.
  static const _keep = Duration(days: 7);

  static final _logger = Logger(printer: SimplePrinter());

  /// How many retries may be waiting at once.
  ///
  /// A retry holds an async write transaction open, which is itself the
  /// condition that pushes the next log onto that path - so without a limit an
  /// error burst queues one transaction per exception, each holding on to a
  /// full stack trace. The cap has to clear a whole burst, though: a failing
  /// cache refresh reports three endpoints at once while its own write is
  /// open, and a smaller limit would drop exactly the entries that explain it.
  static const _maxPending = 32;

  static int _pending = 0;

  /// Writes this entry away, and never throws.
  ///
  /// Almost every entry is written from inside a catch block, through
  /// [ErrorReporter.report], so anything escaping here would replace the error
  /// that block was handling with an unrelated one. Isar refuses a synchronous
  /// write while an asynchronous one is open in the isolate, and the device
  /// cache holds one per chunk, so that case is retried asynchronously. What
  /// neither attempt can serve - logging from inside a transaction, a closed
  /// or broken database, a retry already pending - loses the entry and says so
  /// on the console.
  void _persist() {
    final db = isar;
    if (db == null) return;
    try {
      db.writeTxnSync(() {
        db.exceptionLogElements.putSync(this);
        db.exceptionLogElements
            .where()
            .logTimeLessThan(logTime.subtract(_keep))
            .deleteAllSync();
      });
    } catch (e) {
      if (_pending >= _maxPending) {
        _logger.w("Dropped a log entry, $_pending retries pending: $message");
        return;
      }
      _pending++;
      unawaited(_persistAsync(db));
    }
  }

  Future<void> _persistAsync(Isar db) async {
    try {
      await db.writeTxn(() async {
        await db.exceptionLogElements.put(this);
        await db.exceptionLogElements
            .where()
            .logTimeLessThan(logTime.subtract(_keep))
            .deleteAll();
      });
    } catch (e) {
      // Not reported through ErrorReporter: that logs an ExceptionLogElement
      // and would come straight back here. The console is the one place left
      // that says logging itself has stopped working.
      _logger.w("Could not persist a log entry: $e");
    } finally {
      _pending--;
    }
  }

  @override
  String toString() {
    return "${logTime.toIso8601String()}: ${message ?? ""}\n$stack";
  }
}
