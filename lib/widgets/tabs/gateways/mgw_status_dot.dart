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

import 'package:flutter/material.dart';
import 'package:mobile_app/services/mgw/reachability.dart';

/// Shows what a paired gateway is currently good for.
///
/// Paired is a stored fact and says nothing about right now: the device may be
/// in a different network, and a reinstalled gateway answers while rejecting
/// the stored credentials. Both look identical in a list that only knows the
/// pairing.
class MgwStatusDot extends StatefulWidget {
  const MgwStatusDot(
      {super.key, required this.host, this.expectNetworkId, this.size = 14});

  final String host;

  /// Network the gateway was bound to, so a stranger at the same address can be
  /// told apart from the gateway itself.
  final String? expectNetworkId;

  final double size;

  @override
  State<MgwStatusDot> createState() => _MgwStatusDotState();

  static Color colorOf(MgwStatus? status) {
    switch (status) {
      case MgwStatus.ok:
        return Colors.green;
      case MgwStatus.unauthorized:
      case MgwStatus.foreign:
        return Colors.red;
      case MgwStatus.unreachable:
        return Colors.grey;
      case null:
        return Colors.grey.shade400;
    }
  }

  static String labelOf(MgwStatus? status) {
    switch (status) {
      case MgwStatus.ok:
        return "Connected";
      case MgwStatus.unauthorized:
        return "Rejected - pair again";
      case MgwStatus.foreign:
        return "A different gateway answers here";
      case MgwStatus.unreachable:
        return "Not in this network";
      case null:
        return "Checking";
    }
  }

}

class _MgwStatusDotState extends State<MgwStatusDot> {
  // Held in state: a future built inside build() is started again on every
  // rebuild, and once the cached answer has expired that is a fresh request
  // each time.
  late Future<MgwStatus> _status;

  @override
  void initState() {
    super.initState();
    _status = _check();
  }

  @override
  void didUpdateWidget(MgwStatusDot old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host ||
        old.expectNetworkId != widget.expectNetworkId) {
      _status = _check();
    }
  }

  Future<MgwStatus> _check() => MgwReachability.statusOf(widget.host,
      expectNetworkId: widget.expectNetworkId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MgwStatus>(
      // The cached answer seeds the builder so a rebuild does not flash grey
      // while the probe it already made is still running.
      initialData: MgwReachability.cachedStatusOf(widget.host,
          expectNetworkId: widget.expectNetworkId),
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        return Tooltip(
          message: MgwStatusDot.labelOf(status),
          child: Icon(
            Icons.fiber_manual_record,
            size: widget.size,
            color: MgwStatusDot.colorOf(status),
            semanticLabel: MgwStatusDot.labelOf(status),
          ),
        );
      },
    );
  }
}
