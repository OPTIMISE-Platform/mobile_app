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
import 'package:isar/isar.dart';

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

  ExceptionLogElement.Log(this.message) {
    stack = StackTrace.current.toString();
    if (isar != null) {
      isar!.writeTxnSync(() {
        isar!.exceptionLogElements.putSync(this);
        isar!.exceptionLogElements.where().logTimeLessThan(logTime.subtract(const Duration(days: 7))).deleteAllSync();
      });
    }
  }

  @override
  String toString() {
    return "${logTime.toIso8601String()}: ${message ?? ""}\n$stack";
  }
}
