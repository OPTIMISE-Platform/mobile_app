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
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

enum LiveConnectionState { connecting, connected, disconnected, refusedNotAuthorized, refusedOther }

/// Connection parameters that may change between two attempts: a renewed
/// client certificate, or credentials stored after a refusal.
typedef LiveConnectParams = ({SecurityContext? context, String? username, String? password});

/// One MQTT 3.1.1 connection that keeps itself up while it is wanted.
///
/// [connect] makes it wanted: a lost or failed connection is retried after
/// 2 s, doubling up to 60 s, and every topic of [subscribe] is subscribed again
/// after each reconnect. [disconnect] ends that; the topics are kept, so a
/// later [connect] subscribes them again. Failures are logged and never shown.
/// Tests replace the class through [factory].
class LiveConnection {
  static final _logger = Logger(printer: SimplePrinter());

  /// Replaced by tests.
  static LiveConnection Function() factory = LiveConnection.new;

  /// Delay before retry number [failures] (0 based).
  static Duration backoff(int failures) {
    final seconds = 2 * pow(2, min(failures, 5)).toInt();
    return Duration(seconds: min(seconds, 60));
  }

  static const _attemptTimeout = Duration(seconds: 12);

  final _messages = StreamController<(String topic, Uint8List payload)>.broadcast();
  final _states = StreamController<LiveConnectionState>.broadcast();
  final Set<String> _topics = {};

  MqttServerClient? _client;
  // The client whose connect is in flight: its own failure path decides what
  // happens next, a disconnect callback during it must not schedule a second retry.
  MqttServerClient? _attempting;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  Timer? _retry;
  bool _wanted = false;
  int _failures = 0;
  var _state = LiveConnectionState.disconnected;

  String _host = '';
  int _port = 0;
  String _clientId = '';
  SecurityContext? _context;
  String? _username;
  String? _password;
  Future<LiveConnectParams> Function()? _refresh;

  LiveConnection();

  Stream<(String topic, Uint8List payload)> get messages => _messages.stream;
  Stream<LiveConnectionState> get states => _states.stream;
  LiveConnectionState get state => _state;

  /// Starts the connection and returns the outcome of the first attempt;
  /// retries go on in the background while it is wanted. With [context] the
  /// connection is TLS. [refresh] is asked before every retry for the current
  /// parameters.
  Future<LiveConnectionState> connect(
    String host,
    int port, {
    SecurityContext? context,
    String? username,
    String? password,
    required String clientId,
    Future<LiveConnectParams> Function()? refresh,
  }) {
    _stop();
    _wanted = true;
    _failures = 0;
    _host = host;
    _port = port;
    _clientId = clientId;
    _context = context;
    _username = username;
    _password = password;
    _refresh = refresh;
    return _attempt(first: true);
  }

  /// QoS 0. Subscribed at once when connected, else after the next connect.
  void subscribe(String topic) {
    if (!_topics.add(topic)) return;
    final client = _client;
    if (_state == LiveConnectionState.connected && client != null) {
      _try(() => client.subscribe(topic, MqttQos.atMostOnce));
    }
  }

  void unsubscribe(String topic) {
    if (!_topics.remove(topic)) return;
    final client = _client;
    if (_state == LiveConnectionState.connected && client != null) {
      _try(() => client.unsubscribe(topic));
    }
  }

  void disconnect() {
    _stop();
    _setState(LiveConnectionState.disconnected);
  }

  void _stop() {
    _wanted = false;
    _retry?.cancel();
    _retry = null;
    _updates?.cancel();
    _updates = null;
    final client = _client;
    _client = null;
    if (client != null) _try(client.disconnect);
  }

  Future<LiveConnectionState> _attempt({bool first = false}) async {
    var context = _context, username = _username, password = _password;
    if (!first && _refresh != null) {
      try {
        final params = await _refresh!();
        if (!_wanted) return LiveConnectionState.disconnected;
        context = _context = params.context;
        username = _username = params.username;
        password = _password = params.password;
      } catch (e) {
        _logger.d('Live connection: no fresh parameters (${e.runtimeType})');
      }
    }
    if (!_wanted) return LiveConnectionState.disconnected;

    _setState(LiveConnectionState.connecting);
    final client = MqttServerClient.withPort(_host, _clientId, _port, maxConnectionAttempts: 1)
      ..logging(on: false)
      ..setProtocolV311()
      ..keepAlivePeriod = 30
      ..connectTimeoutPeriod = 8000
      ..autoReconnect = false;
    if (context != null) {
      client
        ..secure = true
        ..securityContext = context;
    }
    client.onDisconnected = () => _dropped(client);
    _client = client;

    var outcome = LiveConnectionState.disconnected;
    _attempting = client;
    try {
      // mqtt_client never completes connect() when the TCP connection is
      // refused, so the attempt is bounded here.
      await client.connect(username, password).timeout(_attemptTimeout);
    } catch (e) {
      _logger.d('Live connection to $_host:$_port failed (${e.runtimeType})');
    } finally {
      if (identical(_attempting, client)) _attempting = null;
    }
    if (!identical(_client, client)) {
      // disconnect() or a newer connect() ran meanwhile.
      _try(client.disconnect);
      return LiveConnectionState.disconnected;
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      _failures = 0;
      for (final topic in _topics) {
        _try(() => client.subscribe(topic, MqttQos.atMostOnce));
      }
      _updates = client.updates?.listen(_onUpdates);
      _setState(LiveConnectionState.connected);
      return LiveConnectionState.connected;
    }

    switch (client.connectionStatus?.returnCode) {
      case MqttConnectReturnCode.notAuthorized:
      case MqttConnectReturnCode.badUsernameOrPassword:
        outcome = LiveConnectionState.refusedNotAuthorized;
      case MqttConnectReturnCode.noneSpecified:
      case null:
        outcome = LiveConnectionState.disconnected;
      default:
        outcome = LiveConnectionState.refusedOther;
    }
    _client = null;
    _try(client.disconnect);
    _setState(outcome);
    _scheduleRetry();
    return outcome;
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is MqttPublishMessage) {
        _messages.add((event.topic, Uint8List.fromList(message.payload.message)));
      }
    }
  }

  void _dropped(MqttServerClient client) {
    if (!identical(_client, client) || !_wanted || identical(_attempting, client)) return;
    _client = null;
    _updates?.cancel();
    _updates = null;
    _setState(LiveConnectionState.disconnected);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_wanted) return;
    _retry?.cancel();
    _retry = Timer(backoff(_failures++), () {
      _retry = null;
      if (_wanted) _attempt();
    });
  }

  void _setState(LiveConnectionState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  static void _try(void Function() action) {
    try {
      action();
    } catch (e) {
      _logger.d('Live connection: ${e.runtimeType}');
    }
  }
}

/// Host and port of `LIVE_MQTT_URL` (`ssl://host:port`); null when [url] is
/// empty or not of that form.
({String host, int port})? parseLiveMqttUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty || !uri.hasPort || uri.port <= 0) return null;
  return (host: uri.host, port: uri.port);
}

// Without resetOnError: on Android every store shares one file, and its reset
// would delete the other stores' values too.
const _liveSecure = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

const _installIdKey = 'live-mqtt-install-id';

/// The id of this installation, made once and kept in the secure store. The
/// app has no other install id: the FCM token changes and is not unique per
/// install.
///
/// Throws when the store cannot be read: a fresh id would replace the stored
/// one, and the certificate issued for it with it.
Future<String> liveInstallId() async {
  final stored = await _liveSecure.read(key: _installIdKey);
  if (stored != null && stored.isNotEmpty) return stored;
  final id = const Uuid().v4();
  try {
    await _liveSecure.write(key: _installIdKey, value: id);
  } catch (_) {
    // Kept for this run only.
  }
  return id;
}

/// `optimise-app-<installId>`: the platform broker takes the id of the cloud
/// login as is; [suffix] tells a second connection of this install apart, since
/// a broker drops the older of two connections that share an id.
Future<String> liveClientId([String suffix = '']) async =>
    'optimise-app-${await liveInstallId()}${suffix.isEmpty ? '' : '-$suffix'}';

/// Secure-storage key of the message broker login of the gateway [pairingId].
String mgwBrokerCredentialsKey(String pairingId) => 'mgw-broker-credentials:$pairingId';

final _brokerLoginChanges = StreamController<String>.broadcast();

/// The pairing id of every gateway whose broker login was just stored.
Stream<String> get mgwBrokerLoginChanges => _brokerLoginChanges.stream;

Future<void> saveMgwBrokerCredentials(String pairingId, String username, String password) async {
  await _liveSecure.write(
    key: mgwBrokerCredentialsKey(pairingId),
    value: jsonEncode({'username': username, 'password': password}),
  );
  _brokerLoginChanges.add(pairingId);
}

/// Null when none is stored or the stored value is unusable; throws when the
/// storage cannot be read.
Future<({String username, String password})?> readMgwBrokerCredentials(String pairingId) async {
  final raw = await _liveSecure.read(key: mgwBrokerCredentialsKey(pairingId));
  if (raw == null) return null;
  try {
    final json = jsonDecode(raw);
    if (json is! Map || json['username'] is! String || json['password'] is! String) return null;
    return (username: json['username'] as String, password: json['password'] as String);
  } on FormatException {
    return null;
  }
}

/// As [readMgwBrokerCredentials], with an unreadable storage as null.
Future<({String username, String password})?> loadMgwBrokerCredentials(String pairingId) async {
  try {
    return await readMgwBrokerCredentials(pairingId);
  } catch (_) {
    return null;
  }
}

Future<void> deleteMgwBrokerCredentials(String pairingId) =>
    _liveSecure.delete(key: mgwBrokerCredentialsKey(pairingId));

/// The gateway's message broker port; the module serves no TLS.
const mgwBrokerPort = 1883;

/// Connects once to the broker of [mgw], reports how it answered and
/// disconnects. [LiveConnectionState.refusedNotAuthorized] means the broker asks for
/// a login; [LiveConnectionState.disconnected], that it did not answer.
var _probes = 0;

Future<LiveConnectionState> probeMgwBroker(MGW mgw, {String? username, String? password}) async {
  final connection = LiveConnection.factory();
  try {
    return await connection.connect(
      gatewaySocketHost(mgw.ip),
      mgwBrokerPort,
      username: username,
      password: password,
      // One id per probe: two probes at once would otherwise drop each other.
      clientId: await liveClientId('probe${_probes++}'),
    );
  } finally {
    connection.disconnect();
  }
}

/// Asks the broker of a gateway whether it takes this phone. A test replaces it.
Future<LiveConnectionState> Function(MGW gateway, {String? username, String? password}) brokerProbe =
    probeMgwBroker;
