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

import 'package:isar_community/isar.dart';

/// Changes whenever the cached data stops belonging to the signed-in account.
/// A fetch that started under an older value drops its result instead of
/// storing it.
class AccountEpoch {
  AccountEpoch._();

  static int _value = 0;

  static int get current => _value;

  /// Called before the cache is wiped for a logout or an account change.
  static void advance() => _value++;

  /// Runs [write] in a transaction on [db] unless the account changed since
  /// [epoch], and returns whether it ran. Checked inside the transaction, so a
  /// wipe queued after the change always runs after the check.
  static Future<bool> writeIfCurrent(
      Isar db, int epoch, Future<void> Function() write) async {
    var written = false;
    await db.writeTxn(() async {
      if (epoch != _value) return;
      await write();
      written = true;
    });
    return written;
  }
}
