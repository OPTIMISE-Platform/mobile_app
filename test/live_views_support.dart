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

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/live/live_values.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';

import 'golden_helper.dart';

/// Stands in for the MQTT client of a view: keeps the set of subscribed topics
/// and counts disconnects, without a broker.
class RecordingConnection extends LiveConnection {
  final topics = <String>{};
  int disconnects = 0;

  @override
  Future<LiveConnectionState> connect(String host, int port,
          {SecurityContext? context,
          String? username,
          String? password,
          required String clientId,
          Future<LiveConnectParams> Function()? refresh}) async =>
      LiveConnectionState.connected;

  @override
  void subscribe(String topic) => topics.add(topic);

  @override
  void unsubscribe(String topic) => topics.remove(topic);

  @override
  void disconnect() => disconnects++;
}

/// Makes every connection of [LiveValues] a [RecordingConnection] that is also
/// added to [made], in the order they were made.
void recordConnectionsInto(List<RecordingConnection> made) {
  LiveConnection.factory = () {
    final c = RecordingConnection();
    made.add(c);
    return c;
  };
}

/// Restores the real connection of [LiveConnection].
void restoreConnections() => LiveConnection.factory = OfflineLiveConnection.new;

/// A device with the local id `<id>-local`, owned by [owner]. It is watched
/// through a paired gateway once [bindToPairedGateway] names it, else through
/// the cloud.
DeviceInstance testDevice(String id, {String owner = 'owner-1'}) =>
    DeviceInstance(id, '$id-local', id, null, 'type-1', false, owner, id, DeviceConnectionStatus.online);

/// Binds [localIds] to a network whose gateway (paired as `pair-1`, at
/// 10.0.0.5) is paired, so those devices are watched on the gateway's broker.
void bindToPairedGateway(List<String> localIds) {
  AppState().networks.add(
      Network('net-1', 'net', false, localIds, const [], DeviceConnectionStatus.online, 'hash', 'owner-1')
        ..localGateways = [MGW('host', 'svc', 'core', '10.0.0.5', networkId: 'net-1', pairingId: 'pair-1')]);
}

/// The topic a gateway device is watched on.
String gatewayTopic(DeviceInstance device) => 'event/${device.local_id}/+';

/// The topic a device is watched on through the cloud.
String cloudTopic(DeviceInstance device) => 'event/${device.owner_id}/${device.local_id}/+';
