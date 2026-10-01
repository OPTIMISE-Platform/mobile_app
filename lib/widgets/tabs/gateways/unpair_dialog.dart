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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/theme.dart';

/// Asks whether to remove the pairing with [mgw]; true when confirmed.
Future<bool> confirmRemovePairing(BuildContext context, MGW mgw) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return AlertDialog(
        title: const Text("Remove pairing?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mgw.mDNSServiceName, style: theme.textTheme.titleSmall),
            Text(mgw.ip,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Spacing.lg),
            const Text("The app stops talking to this gateway directly and "
                "uses the cloud instead. Your devices are not affected."),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Remove"),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

enum PairingRemoval {
  cancelled,
  removed,

  /// The entry is no longer stored, so nothing was removed.
  notFound,
  failed,
}

/// Confirms, then removes the pairing with [mgw].
Future<PairingRemoval> removePairing(BuildContext context, MGW mgw) async {
  if (!await confirmRemovePairing(context, mgw)) return PairingRemoval.cancelled;
  return removeConfirmedPairing(mgw);
}

/// Removes the pairing with [mgw] without asking.
Future<PairingRemoval> removeConfirmedPairing(MGW mgw) async {
  final bool removed;
  try {
    // Awaited: it clears the stored secrets. loadStoredMGWs then has to run
    // too - the lists read AppState.gateways, which only that call refills,
    // and a list that missed a change shows what was asked to be removed.
    removed = await MgwStorage.RemovePairedMGW(mgw);
    await AppState().loadStoredMGWs();
  } catch (e, s) {
    ErrorReporter.report("Could not remove the pairing", e, s);
    return PairingRemoval.failed;
  }
  if (!removed) return PairingRemoval.notFound;
  // Not awaited: it probes the remaining gateways, and nothing on screen waits
  // for that - it only stops routing requests to the removed one.
  unawaited(AppState().mergeGatewaysWithNetworks().catchError(
      (Object e, StackTrace s) => ErrorReporter.log(
          "Could not update the gateways after removing a pairing", e, s)));
  return PairingRemoval.removed;
}

/// What to tell the user when nothing was removed.
const pairingNotFoundMessage =
    "Nothing was removed: this pairing is no longer stored.";
