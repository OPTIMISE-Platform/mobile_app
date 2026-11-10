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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/live/live_values.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/live/raw_value_source.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/protocol.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/services/settings.dart';

import 'golden_helper.dart';

/// Stands in for the MQTT client: records what [LiveValues] asks of it and
/// delivers the messages a test pushes.
class FakeConnection extends LiveConnection {
  final incoming = StreamController<(String, Uint8List)>.broadcast();
  final stateEvents = StreamController<LiveConnectionState>.broadcast();
  final subscribed = <String>{};
  final subscribeCalls = <String>[];
  final unsubscribeCalls = <String>[];
  int connectCalls = 0;
  int disconnectCalls = 0;
  String? host;
  int? port;
  String? clientId;
  String? username;
  String? password;
  bool hasContext = false;
  LiveConnectionState outcome = LiveConnectionState.connected;
  LiveConnectionState current = LiveConnectionState.disconnected;

  @override
  LiveConnectionState get state => current;

  @override
  Stream<(String, Uint8List)> get messages => incoming.stream;

  @override
  Stream<LiveConnectionState> get states => stateEvents.stream;

  @override
  Future<LiveConnectionState> connect(String host, int port,
      {SecurityContext? context,
      String? username,
      String? password,
      required String clientId,
      Future<LiveConnectParams> Function()? refresh}) async {
    connectCalls++;
    this.host = host;
    this.port = port;
    this.clientId = clientId;
    this.username = username;
    this.password = password;
    hasContext = context != null;
    current = outcome;
    stateEvents.add(outcome);
    return outcome;
  }

  @override
  void subscribe(String topic) {
    subscribeCalls.add(topic);
    subscribed.add(topic);
  }

  @override
  void unsubscribe(String topic) {
    unsubscribeCalls.add(topic);
    subscribed.remove(topic);
  }

  @override
  void disconnect() {
    disconnectCalls++;
    current = LiveConnectionState.disconnected;
    stateEvents.add(LiveConnectionState.disconnected);
  }

  void send(String topic, String payload) => incoming.add((topic, Uint8List.fromList(utf8.encode(payload))));
}

ContentVariable variable(String name,
        {String? characteristic, String? function, List<ContentVariable>? subs}) =>
    ContentVariable(null, name, characteristic, null, null, function, ContentVariable.none, subs, null, null);

DeviceState state(String serviceId, String function, String path,
        {bool controlling = false, DeviceInstance? device}) =>
    DeviceState(null, serviceId, 'group', function, null, controlling, null, null, device?.id, path, null)
      ..deviceInstance = device;

DeviceInstance device(String id, {String owner = 'owner-1'}) =>
    DeviceInstance(id, '$id-local', id, null, 'type-1', false, owner, id, DeviceConnectionStatus.online);

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  final protocols = <String, Protocol>{
    'proto-cloud': Protocol('proto-cloud', 'cloud', [ProtocolSegment('seg-json', 'body')]),
    'proto-one': Protocol('proto-one', 'one', [ProtocolSegment('seg-raw', 'data')]),
    // Like the platform's standard-connector protocol.
    'proto-two': Protocol('proto-two', 'standard-connector',
        [ProtocolSegment('seg-meta', 'metadata'), ProtocolSegment('seg-data', 'data')]),
  };

  final deviceType = DeviceType('type-1', 'Meter', '', 'class', [
    Service('sA', 'svcA', 'A', '', 'proto-cloud', 'event', 'group', null, [
      Content('c1', 'json', 'seg-json', variable('reading', subs: [
        variable('temp', characteristic: 'char-c', function: 'fn-temp'),
        variable('hum', characteristic: 'char-pct', function: 'fn-hum'),
      ])),
    ]),
    Service('sB', 'svcB', 'B', '', 'proto-one', 'event', 'group', null, [
      Content('c2', 'plain-text', 'seg-raw', variable('power', characteristic: 'char-w', function: 'fn-power')),
    ]),
    Service('sD', 'svcD', 'D', '', 'proto-two', 'event', 'group', null, [
      Content('c3', 'plain-text', 'seg-data', variable('x', characteristic: 'char-x', function: 'fn-x')),
      Content('c4', 'plain-text', 'seg-meta', variable('meta', characteristic: 'char-x', function: 'fn-meta')),
    ]),
  ], null);

  late List<FakeConnection> made;
  late Map<String, int> protocolLoads;
  late DateTime now;
  late bool cloudOn;
  late LiveValues live;
  late DeviceInstance cloudDevice, gatewayDevice;
  late DeviceState temp, hum, control, transitioning, power, extra;
  var notifications = 0;
  late Map<String, DeviceInstance> knownDevices;
  Completer<void>? deviceGate;
  late Object? Function() contextFailure;
  late LiveConnectionState outcomeOfNew;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    if (Settings.getAccount() != 'test-account') await Settings.setAccount('test-account');
    made = [];
    deviceGate = null;
    contextFailure = () => null;
    protocolLoads = {};
    now = DateTime.utc(2026, 11, 9, 12);
    cloudOn = true;
    outcomeOfNew = LiveConnectionState.connected;
    LiveConnection.factory = () {
      final c = FakeConnection()..outcome = outcomeOfNew;
      made.add(c);
      return c;
    };
    live = LiveValues(
      now: () => now,
      certificate: () async => (certPem: 'cert', keyPem: 'key'),
      contextOf: (_, __) {
        final failure = contextFailure();
        if (failure != null) throw failure;
        return SecurityContext();
      },
      deviceById: (id) async {
        await deviceGate?.future;
        return knownDevices[id];
      },
      gatewayLogin: (pairingId) async =>
          pairingId == 'pair-1' ? (username: 'user', password: 'secret') : null,
      clientId: ([suffix = '']) async => 'optimise-app-test${suffix.isEmpty ? '' : '-$suffix'}',
      cloudEndpoint: () => cloudOn ? (host: 'mqtt.test', port: 28888) : null,
      protocol: (id) async {
        protocolLoads[id] = (protocolLoads[id] ?? 0) + 1;
        return protocols[id];
      },
    );

    AppState().deviceTypes['type-1'] = deviceType;
    cloudDevice = device('dev-1');
    temp = state('sA', 'fn-temp', 'reading.temp', device: cloudDevice);
    hum = state('sA', 'fn-hum', 'reading.hum', device: cloudDevice);
    control = state('sA', 'fn-ctl', 'reading.temp', controlling: true, device: cloudDevice);
    transitioning = state('sA', 'fn-busy', 'reading.hum', device: cloudDevice)..transitioning = true;
    cloudDevice.states.addAll([temp, hum, control, transitioning]);

    gatewayDevice = device('dev-gw');
    power = state('sB', 'fn-power', 'power', device: gatewayDevice);
    extra = state('sD', 'fn-x', 'x', device: gatewayDevice);
    gatewayDevice.states.addAll([power, extra]);
    AppState().networks.add(Network('net-1', 'net', false, ['dev-gw-local'], ['dev-gw'],
        DeviceConnectionStatus.online, 'hash', 'owner-1')
      ..localGateways = [MGW('host', 'svc', 'core', '10.0.0.5', networkId: 'net-1', pairingId: 'pair-1')]);

    knownDevices = {'dev-1': cloudDevice, 'dev-gw': gatewayDevice};
    notifications = 0;
    cloudDevice.stateNotifier.addListener(() => notifications++);
  });

  tearDown(() async {
    live.accountChanged();
    LiveConnection.factory = OfflineLiveConnection.new;
    AppState().deviceTypes.remove('type-1');
    resetAppStateForGolden();
    await Settings.setFunctionPreferredCharacteristicId('fn-temp', null);
    if (Settings.getAccount() != 'test-account') await Settings.setAccount('test-account');
  });

  const cloudTopic = 'event/owner-1/dev-1-local/+';
  const cloudEvent = 'event/owner-1/dev-1-local/svcA';
  String reading(num t, num h, [String? timestamp]) => jsonEncode({
        'body': jsonEncode({'temp': t, 'hum': h}),
        if (timestamp != null) 'timestamp_rfc3339nano': timestamp,
      });

  group('routing', () {
    test('a device without a paired gateway goes to the cloud with the owner in the topic', () async {
      live.watch(cloudDevice);
      await pumpEventQueue();

      expect(made, hasLength(1));
      final c = made.single;
      expect(c.host, 'mqtt.test');
      expect(c.port, 28888);
      expect(c.clientId, 'optimise-app-test');
      expect(c.hasContext, isTrue);
      expect(c.username, isNull);
      expect(c.subscribed, {cloudTopic});
      expect(live.hasConnection(LiveValues.cloudRoute), isTrue);
    });

    test('a device behind a paired gateway goes to its broker with the login and no owner in the topic', () async {
      live.watch(gatewayDevice);
      await pumpEventQueue();

      expect(made, hasLength(1));
      final c = made.single;
      expect(c.host, '10.0.0.5');
      expect(c.port, 1883);
      expect(c.hasContext, isFalse);
      expect(c.username, 'user');
      expect(c.password, 'secret');
      expect(c.clientId, 'optimise-app-test-pair-1');
      expect(c.subscribed, {'event/dev-gw-local/+'});
      expect(live.hasConnection(LiveValues.gatewayRoute('pair-1')), isTrue);
      expect(live.hasConnection(LiveValues.cloudRoute), isFalse);
    });

    test('a gateway whose broker needs no login connects without one', () async {
      AppState().networks.single.localGateways = [
        MGW('host', 'svc', 'core', '10.0.0.6', networkId: 'net-1', pairingId: 'pair-2')
      ];
      live.watch(gatewayDevice);
      await pumpEventQueue();

      expect(made.single.host, '10.0.0.6');
      expect(made.single.username, isNull);
    });

    test('without LIVE_MQTT_URL the cloud is off and watch does nothing', () async {
      cloudOn = false;
      final handle = live.watch(cloudDevice);
      await pumpEventQueue();

      expect(made, isEmpty);
      handle.release();
    });

    test('a gateway that becomes known after the watch takes the device over', () async {
      // At start the paired gateways are not known yet, and the cloud is off.
      cloudOn = false;
      final gateways = AppState().networks.single.localGateways;
      AppState().networks.single.localGateways = null;
      live.watch(gatewayDevice);
      await pumpEventQueue();
      expect(made, isEmpty);

      AppState().networks.single.localGateways = gateways;
      AppState().notifyListeners();
      await pumpEventQueue();

      expect(made.single.host, '10.0.0.5');
      expect(made.single.subscribed, {'event/dev-gw-local/+'});
    });

    test('a gateway that goes away moves the device to the cloud and closes its connection', () async {
      live.watch(gatewayDevice);
      await pumpEventQueue();
      final gatewayConnection = made.single;

      AppState().networks.single.localGateways = null;
      AppState().notifyListeners();
      await pumpEventQueue();

      expect(gatewayConnection.subscribed, isEmpty);
      expect(gatewayConnection.disconnectCalls, 1);
      expect(made.last.host, 'mqtt.test');
      expect(made.last.subscribed, {'event/owner-1/dev-gw-local/+'});
    });
  });

  group('reference counting', () {
    test('one release of two watches keeps the subscription, the last one ends it and the connection', () async {
      final first = live.watch(cloudDevice);
      final second = live.watch(cloudDevice);
      await pumpEventQueue();
      final c = made.single;
      expect(made, hasLength(1));

      first.release();
      first.release(); // twice does not count twice
      expect(c.subscribed, {cloudTopic});
      expect(c.unsubscribeCalls, isEmpty);
      expect(c.disconnectCalls, 0);

      second.release();
      expect(c.subscribed, isEmpty);
      expect(c.unsubscribeCalls, [cloudTopic]);
      expect(c.disconnectCalls, 1);
      expect(live.hasConnection(LiveValues.cloudRoute), isFalse);
    });

    test('devices of one route share the connection, which closes with the last of them', () async {
      final other = device('dev-2');
      other.states.add(state('sA', 'fn-temp', 'reading.temp', device: other));
      final a = live.watch(cloudDevice);
      final b = live.watch(other);
      await pumpEventQueue();
      expect(made, hasLength(1));
      expect(made.single.subscribed, {cloudTopic, 'event/owner-1/dev-2-local/+'});

      a.release();
      expect(made.single.subscribed, {'event/owner-1/dev-2-local/+'});
      expect(made.single.disconnectCalls, 0);
      b.release();
      expect(made.single.disconnectCalls, 1);
    });

    test('a reloaded object of a watched device gets the values too, its release keeps the subscription',
        () async {
      final reloaded = device('dev-1');
      final reloadedTemp = state('sA', 'fn-temp', 'reading.temp', device: reloaded);
      reloaded.states.add(reloadedTemp);
      final old = live.watch(cloudDevice);
      final fresh = live.watch(reloaded);
      await pumpEventQueue();
      final c = made.single;

      c.send(cloudEvent, reading(22, 41));
      await pumpEventQueue();
      expect(temp.value, 22);
      expect(reloadedTemp.value, 22);

      old.release();
      expect(c.subscribed, {cloudTopic});
      expect(c.disconnectCalls, 0);
      c.send(cloudEvent, reading(23, 42));
      await pumpEventQueue();
      expect(reloadedTemp.value, 23);
      expect(temp.value, 22, reason: 'the released object is no longer updated');

      fresh.release();
      expect(c.disconnectCalls, 1);
    });

    test('a device watched again after the last release opens a new connection', () async {
      live.watch(cloudDevice).release();
      await pumpEventQueue();
      live.watch(cloudDevice);
      await pumpEventQueue();

      expect(made, hasLength(2));
      expect(made.last.subscribed, {cloudTopic});
    });
  });

  group('cloud messages', () {
    test('update value and time of the readings and notify once', () async {
      live.watch(cloudDevice);
      await pumpEventQueue();
      final writesBefore = temp.valueWrites;

      made.single.send(cloudEvent, reading(21.5, 40, '2026-11-09T10:00:00.123456789Z'));
      await pumpEventQueue();

      expect(temp.value, 21.5);
      expect(hum.value, 40);
      expect(temp.lastMessageTime, DateTime.utc(2026, 11, 9, 10, 0, 0, 123, 456));
      expect(hum.lastMessageTime, DateTime.utc(2026, 11, 9, 10, 0, 0, 123, 456));
      expect(temp.valueWrites, writesBefore + 1);
      expect(notifications, 1);
      expect(protocolLoads['proto-cloud'], 1);
    });

    test('without a timestamp the time is the receive time', () async {
      live.watch(cloudDevice);
      await pumpEventQueue();

      made.single.send(cloudEvent, reading(1, 2));
      await pumpEventQueue();

      expect(temp.lastMessageTime, now);
    });

    test('a controlling state and a state that is transitioning stay as they are', () async {
      live.watch(cloudDevice);
      await pumpEventQueue();

      made.single.send(cloudEvent, reading(21.5, 40));
      await pumpEventQueue();

      for (final s in [control, transitioning]) {
        expect(s.value, isNull);
        expect(s.valueWrites, 0);
        expect(s.lastMessageTime, isNull);
      }
      expect(transitioning.transitioning, isTrue);
    });

    test('the value setter runs first, so a time loaded late cannot take the place of the live one', () async {
      live.watch(cloudDevice);
      await pumpEventQueue();
      final writes = temp.valueWrites;

      made.single.send(cloudEvent, reading(21.5, 40));
      await pumpEventQueue();

      // device_mixin.loadMissingStateTimes applies a time only to a state whose
      // valueWrites it saw before the request, and with ??=.
      expect(temp.valueWrites, isNot(writes));
      final live1 = temp.lastMessageTime;
      temp.lastMessageTime ??= DateTime.utc(2000);
      expect(temp.lastMessageTime, live1);
      expect(temp.lastMessageTime, isNotNull);
    });

    test('in the preferred characteristic by a formula of the concept', () async {
      await Settings.setFunctionPreferredCharacteristicId('fn-temp', 'char-f');
      AppState().platformFunctions['fn-temp'] = PlatformFunction('fn-temp', 'temp', 'concept-1', 'Temperature');
      AppState().concepts['concept-1'] = Concept('concept-1', 'temperature', 'char-c', [],
          [ConceptConversion('char-c', 'char-f', 1, 'x * 9 / 5 + 32', 'x')]);
      live.watch(cloudDevice);
      await pumpEventQueue();

      made.single.send(cloudEvent, reading(100, 40));
      await pumpEventQueue();

      expect(temp.value, 212);
      expect(hum.value, 40, reason: 'a function without a preferred characteristic stays raw');
    });

    test('a value that cannot be converted leaves its state unchanged and the others are still updated', () async {
      await Settings.setFunctionPreferredCharacteristicId('fn-temp', 'char-nowhere');
      live.watch(cloudDevice);
      await pumpEventQueue();

      made.single.send(cloudEvent, reading(100, 40));
      await pumpEventQueue();

      expect(temp.value, isNull);
      expect(temp.valueWrites, 0);
      expect(hum.value, 40);
      expect(notifications, 1);
    });

    test('messages for another device, an unknown service, another owner or garbage change nothing', () async {
      live.watch(cloudDevice);
      await pumpEventQueue();
      final c = made.single;

      c.send('event/owner-1/other-local/svcA', reading(1, 2));
      c.send('event/owner-1/dev-1-local/svcUnknown', reading(1, 2));
      c.send('event/someone-else/dev-1-local/svcA', reading(1, 2));
      c.send('event/owner-1/svcA', reading(1, 2));
      c.send(cloudEvent, 'not json');
      c.send(cloudEvent, '[1,2]');
      c.send(cloudEvent, jsonEncode({'body': '{}'}));
      await pumpEventQueue();

      expect(temp.valueWrites, 0);
      expect(hum.valueWrites, 0);
      expect(notifications, 0);
    });

    test('a message that arrives after the last release is ignored', () async {
      final handle = live.watch(cloudDevice);
      await pumpEventQueue();
      final c = made.single;
      handle.release();

      c.send(cloudEvent, reading(1, 2));
      await pumpEventQueue();

      expect(temp.valueWrites, 0);
    });
  });

  group('non-finite values', () {
    String body(String temp) => jsonEncode({'body': '{"temp": $temp, "hum": 40}'});

    test('a raw value that is infinite leaves the state unchanged', () async {
      live.watch(cloudDevice);
      await pumpEventQueue();

      made.single.send(cloudEvent, body('1e999'));
      await pumpEventQueue();

      expect(temp.value, isNull);
      expect(temp.valueWrites, 0);
      expect(hum.value, 40);
    });

    test('a converted value that is infinite leaves the state unchanged', () async {
      await Settings.setFunctionPreferredCharacteristicId('fn-temp', 'char-f');
      AppState().platformFunctions['fn-temp'] = PlatformFunction('fn-temp', 'temp', 'concept-1', 'Temperature');
      AppState().concepts['concept-1'] = Concept('concept-1', 'temperature', 'char-c', [],
          [ConceptConversion('char-c', 'char-f', 1, 'x * x', 'x')]);
      live.watch(cloudDevice);
      await pumpEventQueue();

      made.single.send(cloudEvent, reading(1e200, 40));
      await pumpEventQueue();

      expect(temp.value, isNull);
      expect(temp.valueWrites, 0);
      expect(hum.value, 40);
    });
  });

  group('connect failures', () {
    testWidgets('an exception while preparing the connection is retried with backoff', (tester) async {
      var failures = 1;
      contextFailure = () => failures-- > 0 ? const TlsException('no key') : null;
      live.watch(cloudDevice);
      await tester.pump();
      expect(made.single.connectCalls, 0);

      await tester.pump(const Duration(seconds: 1));
      expect(made.single.connectCalls, 0, reason: 'the first delay is 2 s');

      await tester.pump(const Duration(seconds: 2));
      expect(made.single.connectCalls, 1);
      expect(made.single.hasContext, isTrue);
    });

    testWidgets('no retry once the connection is closed or the app is paused', (tester) async {
      contextFailure = () => const TlsException('no key');
      final handle = live.watch(cloudDevice);
      await tester.pump();
      handle.release();
      await tester.pump(const Duration(minutes: 5));
      expect(made.single.connectCalls, 0);

      live.watch(cloudDevice);
      await tester.pump();
      live.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 5));
      expect(made.last.connectCalls, 0);
    });
  });

  group('watchRaw', () {
    RawValueSource source({String service = 'sA', String column = 'reading.temp', String? target, String? concept}) =>
        RawValueSource(
            deviceId: 'dev-1', serviceId: service, column: column, targetCharacteristicId: target, conceptId: concept);

    late List<(dynamic, DateTime)> got;
    void collect(dynamic value, DateTime time) => got.add((value, time));

    setUp(() => got = []);

    test('delivers the raw value with the message time on the route of the device', () async {
      live.watchRaw(source(), collect);
      await pumpEventQueue();

      expect(made.single.subscribed, {cloudTopic});
      made.single.send(cloudEvent, reading(21.5, 40, '2026-11-09T11:00:00.123456789Z'));
      await pumpEventQueue();

      expect(got, [(21.5, DateTime.utc(2026, 11, 9, 11, 0, 0, 123, 456))]);
      expect(temp.value, isNull, reason: 'no device object is watched, none is touched');
    });

    test('without a timestamp the time is the receive time', () async {
      live.watchRaw(source(column: 'reading.hum'), collect);
      await pumpEventQueue();
      made.single.send(cloudEvent, reading(1, 40));
      await pumpEventQueue();
      expect(got, [(40, now)]);
    });

    test('a device behind a gateway is read from its broker', () async {
      knownDevices['dev-gw'] = gatewayDevice;
      live.watchRaw(const RawValueSource(deviceId: 'dev-gw', serviceId: 'sB', column: 'power'), collect);
      await pumpEventQueue();

      expect(made.single.subscribed, {'event/dev-gw-local/+'});
      made.single.send('event/dev-gw-local/svcB', '1500');
      await pumpEventQueue();
      expect(got.map((e) => e.$1), ['1500']);
    });

    test('shares the subscription with a device watch and ends it with the last user', () async {
      final view = live.watch(cloudDevice);
      final raw = live.watchRaw(source(), collect);
      final second = live.watchRaw(source(column: 'reading.hum'), collect);
      await pumpEventQueue();
      final c = made.single;
      expect(made, hasLength(1));
      expect(c.subscribeCalls.toSet(), {cloudTopic});
      expect(c.unsubscribeCalls, isEmpty);

      c.send(cloudEvent, reading(20, 41));
      await pumpEventQueue();
      expect(temp.value, 20);
      expect(got.map((e) => e.$1), [20, 41]);

      view.release();
      raw.release();
      expect(c.subscribed, {cloudTopic});
      expect(c.disconnectCalls, 0);
      c.send(cloudEvent, reading(30, 42));
      await pumpEventQueue();
      expect(got.map((e) => e.$1), [20, 41, 42]);

      second.release();
      expect(c.subscribed, isEmpty);
      expect(c.disconnectCalls, 1);
    });

    test('converts to the target characteristic with the formulas of the given concept', () async {
      AppState().concepts['concept-1'] = Concept('concept-1', 'temperature', 'char-c', [],
          [ConceptConversion('char-c', 'char-f', 1, 'x * 9 / 5 + 32', 'x')]);
      live.watchRaw(source(target: 'char-f', concept: 'concept-1'), collect);
      await pumpEventQueue();

      made.single.send(cloudEvent, reading(100, 40));
      await pumpEventQueue();
      expect(got.map((e) => e.$1), [212]);
    });

    test('without a concept id the concept of the function is used; no target keeps the raw value', () async {
      AppState().platformFunctions['fn-temp'] = PlatformFunction('fn-temp', 'temp', 'concept-1', 'Temperature');
      AppState().concepts['concept-1'] = Concept('concept-1', 'temperature', 'char-c', [],
          [ConceptConversion('char-c', 'char-f', 1, 'x * 9 / 5 + 32', 'x')]);
      live.watchRaw(source(target: 'char-f'), collect);
      live.watchRaw(source(), collect);
      await pumpEventQueue();

      made.single.send(cloudEvent, reading(100, 40));
      await pumpEventQueue();
      expect(got.map((e) => e.$1).toSet(), {212, 100});
    });

    test('a value that cannot be converted, or is not finite after it, is not delivered', () async {
      live.watchRaw(source(target: 'char-nowhere'), collect);
      AppState().concepts['concept-1'] = Concept('concept-1', 'temperature', 'char-c', [],
          [ConceptConversion('char-c', 'char-inf', 1, 'x * x', 'x')]);
      live.watchRaw(source(target: 'char-inf', concept: 'concept-1'), collect);
      live.watchRaw(source(), collect);
      await pumpEventQueue();

      made.single.send(cloudEvent, jsonEncode({'body': '{"temp": 1e999, "hum": 40}'}));
      made.single.send(cloudEvent, reading(1e200, 2));
      await pumpEventQueue();
      expect(got.map((e) => e.$1), [1e200], reason: 'only the plain source, and not the infinite message');
    });

    test('another service of the device is ignored', () async {
      live.watchRaw(source(service: 'sX'), collect);
      await pumpEventQueue();
      made.single.send(cloudEvent, reading(1, 2));
      await pumpEventQueue();
      expect(got, isEmpty);
    });

    test('a release before the device is resolved subscribes nothing', () async {
      deviceGate = Completer<void>();
      final handle = live.watchRaw(source(), collect);
      await pumpEventQueue();
      handle.release();
      deviceGate!.complete();
      await pumpEventQueue();

      expect(made, isEmpty);
      expect(live.hasConnection(LiveValues.cloudRoute), isFalse);
    });

    test('an unknown device subscribes nothing', () async {
      knownDevices.clear();
      live.watchRaw(source(), collect);
      await pumpEventQueue();
      expect(made, isEmpty);
    });

    test('a release after the subscription ends it, twice does not count twice', () async {
      final a = live.watchRaw(source(), collect);
      final b = live.watchRaw(source(), collect);
      await pumpEventQueue();
      a.release();
      a.release();
      expect(made.single.disconnectCalls, 0);
      b.release();
      expect(made.single.disconnectCalls, 1);
    });
  });

  group('gateway messages', () {
    test('the raw payload is the segment "data"', () async {
      live.watch(gatewayDevice);
      await pumpEventQueue();

      made.single.send('event/dev-gw-local/svcB', '230');
      await pumpEventQueue();

      expect(power.value, '230');
      expect(power.lastMessageTime, now);
    });

    test('with several segments, as the standard connector has, only the "data" output is read', () async {
      final meta = state('sD', 'fn-meta', 'meta', device: gatewayDevice);
      gatewayDevice.states.add(meta);
      live.watch(gatewayDevice);
      await pumpEventQueue();

      made.single.send('event/dev-gw-local/svcD', 'x-value');
      await pumpEventQueue();

      expect(extra.value, 'x-value');
      expect(meta.valueWrites, 0);
    });
  });

  group('gateway login', () {
    test('a stored login reconnects the gateway connection at once with it', () async {
      var login = (username: 'user', password: 'old');
      live.accountChanged();
      live = LiveValues(
        gatewayLogin: (_) async => login,
        clientId: ([suffix = '']) async => 'optimise-app-test',
        cloudEndpoint: () => null,
      );
      outcomeOfNew = LiveConnectionState.refusedNotAuthorized;
      live.watch(gatewayDevice);
      await pumpEventQueue();
      final conn = made.single;
      expect((conn.connectCalls, conn.password), (1, 'old'));

      login = (username: 'user', password: 'new');
      live.gatewayLoginChanged('pair-1');
      await pumpEventQueue();
      expect((conn.connectCalls, conn.password), (2, 'new'));

      // A connection that is up keeps running.
      conn.current = LiveConnectionState.connected;
      live.gatewayLoginChanged('pair-1');
      await pumpEventQueue();
      expect(conn.connectCalls, 2);

      // Another gateway's login leaves this connection alone.
      live.gatewayLoginChanged('pair-2');
      await pumpEventQueue();
      expect(conn.connectCalls, 2);
    });
  });

  group('outages', () {
    const platform = (routeKey: LiveValues.cloudRoute, gatewayName: null);
    final gateway = (routeKey: LiveValues.gatewayRoute('pair-1'), gatewayName: 'svc');

    testWidgets('a connection that does not come up is an outage after 10 s, and none once it is up', (tester) async {
      outcomeOfNew = LiveConnectionState.disconnected;
      live.watch(cloudDevice);
      await tester.pump(const Duration(seconds: 9));
      expect(live.outages.value, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(live.outages.value, [platform]);

      made.single.stateEvents.add(LiveConnectionState.connected);
      await tester.pump();
      expect(live.outages.value, isEmpty);
    });

    testWidgets('a drop that is over within 10 s is no outage', (tester) async {
      live.watch(cloudDevice);
      await tester.pump();
      made.single.stateEvents.add(LiveConnectionState.disconnected);
      await tester.pump(const Duration(seconds: 6));
      made.single.stateEvents.add(LiveConnectionState.connecting);
      await tester.pump(const Duration(seconds: 3));
      made.single.stateEvents.add(LiveConnectionState.connected);
      await tester.pump(const Duration(seconds: 20));
      expect(live.outages.value, isEmpty);
    });

    testWidgets('a refused login and a missing certificate count as well', (tester) async {
      outcomeOfNew = LiveConnectionState.refusedNotAuthorized;
      live.watch(gatewayDevice);
      await tester.pump(const Duration(seconds: 10));
      expect(live.outages.value, [gateway]);
      live.accountChanged();

      live = LiveValues(
        certificate: () async => null,
        cloudEndpoint: () => (host: 'mqtt.test', port: 28888),
        clientId: ([suffix = '']) async => 'optimise-app-test',
      );
      live.watch(cloudDevice);
      await tester.pump(const Duration(seconds: 10));
      expect(live.outages.value, [platform]);
      live.accountChanged();
      await tester.pump(const Duration(minutes: 5));
    });

    testWidgets('outages of the platform and a gateway are both listed, the platform first', (tester) async {
      outcomeOfNew = LiveConnectionState.disconnected;
      live.watch(gatewayDevice);
      await tester.pump(const Duration(seconds: 5));
      live.watch(cloudDevice);
      await tester.pump(const Duration(seconds: 10));
      expect(live.outages.value, [platform, gateway]);
    });

    testWidgets('the last release ends the outage of its connection', (tester) async {
      outcomeOfNew = LiveConnectionState.disconnected;
      final handle = live.watch(cloudDevice);
      await tester.pump(const Duration(seconds: 10));
      expect(live.outages.value, [platform]);
      handle.release();
      expect(live.outages.value, isEmpty);
    });

    testWidgets('paused ends the outages and starts no wait, resumed starts it again', (tester) async {
      outcomeOfNew = LiveConnectionState.disconnected;
      live.watch(cloudDevice);
      await tester.pump(const Duration(seconds: 10));
      expect(live.outages.value, [platform]);

      live.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(live.outages.value, isEmpty);
      await tester.pump(const Duration(minutes: 1));
      expect(live.outages.value, isEmpty, reason: 'no connection is wanted in the background');

      live.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 9));
      expect(live.outages.value, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(live.outages.value, [platform]);
      live.accountChanged();
    });
  });

  group('lifecycle', () {
    test('paused disconnects, resumed connects again and subscribes again', () async {
      live.watch(cloudDevice);
      await pumpEventQueue();
      final c = made.single;
      expect(c.connectCalls, 1);

      live.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(c.disconnectCalls, 1);
      expect(c.connectCalls, 1);

      c.subscribeCalls.clear();
      live.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(c.connectCalls, 2);
      expect(c.subscribeCalls, [cloudTopic]);
      expect(made, hasLength(1));

      // Still delivering after the resume.
      c.send(cloudEvent, reading(3, 4));
      await pumpEventQueue();
      expect(temp.value, 3);
    });

    test('a device released while paused is not connected on resume', () async {
      final handle = live.watch(cloudDevice);
      await pumpEventQueue();
      live.didChangeAppLifecycleState(AppLifecycleState.paused);
      handle.release();

      live.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(made.single.connectCalls, 1);
    });

    test('an account change drops the connections, and the old handle does nothing', () async {
      final old = live.watch(cloudDevice);
      await pumpEventQueue();
      final first = made.single;

      await Settings.setAccount('account-2');
      final handle = live.watch(device('dev-3'));
      await pumpEventQueue();

      expect(first.disconnectCalls, 1);
      expect(made, hasLength(2));
      expect(made.last.subscribed, {'event/owner-1/dev-3-local/+'});
      old.release();
      expect(made.last.disconnectCalls, 0);
      handle.release();
      expect(made.last.disconnectCalls, 1);
    });
  });

  group('connection helpers', () {
    test('backoff doubles from 2 s up to 60 s', () {
      expect([for (var i = 0; i < 8; i++) LiveConnection.backoff(i).inSeconds], [2, 4, 8, 16, 32, 60, 60, 60]);
    });

    test('LIVE_MQTT_URL gives host and port or nothing', () {
      expect(parseLiveMqttUrl('ssl://certconnector.senergy.infai.org:28888'),
          (host: 'certconnector.senergy.infai.org', port: 28888));
      expect(parseLiveMqttUrl(''), isNull);
      expect(parseLiveMqttUrl(null), isNull);
      expect(parseLiveMqttUrl('ssl://host'), isNull);
      expect(parseLiveMqttUrl('nonsense'), isNull);
    });

    test('a gateway stored with its port is reached on the broker port of its host', () async {
      final network = AppState().networks.single;
      network.localGateways = [
        MGW('host', 'svc', 'core', '10.0.0.5:8081', networkId: 'net-1', pairingId: 'pair-1')
      ];
      live.watch(gatewayDevice);
      await pumpEventQueue();

      expect(made.single.host, '10.0.0.5');
      expect(made.single.port, 1883);

      LiveConnection.factory = () {
        final c = FakeConnection();
        made.add(c);
        return c;
      };
      await probeMgwBroker(MGW('host', 'svc', 'core', '[fd00::5]:8081', pairingId: 'pair-9'));
      expect(made.last.host, 'fd00::5');
    });

    test('gateway broker logins are stored per pairing', () async {
      expect(await loadMgwBrokerCredentials('pair-1'), isNull);
      final changed = <String>[];
      final sub = mgwBrokerLoginChanges.listen(changed.add);
      await saveMgwBrokerCredentials('pair-1', 'user', 'secret');
      await pumpEventQueue();
      await sub.cancel();
      expect(changed, ['pair-1'], reason: 'a stored login is announced');
      expect(await loadMgwBrokerCredentials('pair-1'), (username: 'user', password: 'secret'));
      expect(await loadMgwBrokerCredentials('pair-2'), isNull);
      await deleteMgwBrokerCredentials('pair-1');
      expect(await loadMgwBrokerCredentials('pair-1'), isNull);
    });

    test('the probe connects once, reports the answer and disconnects', () async {
      final mgw = MGW('host', 'svc', 'core', '10.0.0.7', pairingId: 'pair-9');
      LiveConnection.factory = () {
        final c = FakeConnection()..outcome = LiveConnectionState.refusedNotAuthorized;
        made.add(c);
        return c;
      };

      expect(await probeMgwBroker(mgw), LiveConnectionState.refusedNotAuthorized);
      expect(await probeMgwBroker(mgw, username: 'u', password: 'p'), LiveConnectionState.refusedNotAuthorized);

      expect(made, hasLength(2));
      expect(made.first.host, '10.0.0.7');
      expect(made.first.port, 1883);
      expect(made.first.username, isNull);
      expect(made.last.username, 'u');
      expect(made.every((c) => c.disconnectCalls == 1), isTrue);
      // A probe must not take over the id of the live connection of the gateway.
      expect(made.first.clientId, startsWith('optimise-app-'));
      expect(made.first.clientId, contains('-probe'));
      String install(String id) => id.substring(0, id.lastIndexOf('-probe'));
      expect(install(made.last.clientId!), install(made.first.clientId!),
          reason: 'the install id is made once');
      // Nor the id of another probe running at the same time.
      expect(made.last.clientId, isNot(made.first.clientId));
    });
  });
}
