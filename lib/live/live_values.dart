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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/live/client_certificate.dart';
import 'package:mobile_app/live/conversion/converter.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/live/raw_output.dart';
import 'package:mobile_app/live/raw_value_source.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/protocol.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/native_pipe.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/protocols.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';

/// What [LiveValues.watch] returns; [release] gives the device back.
class LiveHandle {
  final void Function() _release;
  bool _released = false;

  LiveHandle._(this._release);

  /// A handle that runs [release] once, for tests of the views.
  @visibleForTesting
  LiveHandle.forTest(void Function() release) : _release = release;

  /// Releasing twice does nothing.
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// Keeps the readings of the watched devices current from MQTT events.
///
/// A device behind a paired gateway is read from that gateway's broker
/// (`event/<local_id>/+`), every other from the platform
/// (`event/<owner_id>/<local_id>/+`). Subscriptions are counted per device, a
/// connection exists while one of its devices is watched, and all of them are
/// closed while the app is in the background.
class LiveValues with WidgetsBindingObserver {
  static final instance = LiveValues();

  static final _logger = Logger(printer: SimplePrinter());

  /// Metadata key of a cloud event that carries the time the platform received it.
  static const timestampKey = 'timestamp_rfc3339nano';

  /// The protocol segment a gateway event's payload belongs to.
  static const mgwPayloadSegment = 'data';

  final DateTime Function() _now;
  final Future<({String certPem, String keyPem})?> Function() _certificate;
  final SecurityContext Function(String certPem, String keyPem) _contextOf;
  final Future<({String username, String password})?> Function(String pairingId) _gatewayLogin;
  final Future<String> Function([String suffix]) _clientId;
  final ({String host, int port})? Function() _cloudEndpoint;
  final Future<Protocol?> Function(String id) _protocol;
  final Future<DeviceInstance?> Function(String id) _deviceById;

  /// The parameters are the seams of the tests; the app uses [instance].
  @visibleForTesting
  LiveValues({
    DateTime Function()? now,
    Future<({String certPem, String keyPem})?> Function()? certificate,
    SecurityContext Function(String certPem, String keyPem)? contextOf,
    Future<({String username, String password})?> Function(String pairingId)? gatewayLogin,
    Future<String> Function([String suffix])? clientId,
    ({String host, int port})? Function()? cloudEndpoint,
    Future<Protocol?> Function(String id)? protocol,
    Future<DeviceInstance?> Function(String id)? deviceById,
  })  : _now = now ?? DateTime.now,
        _certificate = certificate ?? ClientCertificates.current,
        _contextOf = contextOf ?? _realContext,
        _gatewayLogin = gatewayLogin ?? loadMgwBrokerCredentials,
        _clientId = clientId ?? liveClientId,
        _cloudEndpoint = cloudEndpoint ?? (() => parseLiveMqttUrl(dotenv.maybeGet('LIVE_MQTT_URL'))),
        _protocol = protocol ?? ProtocolsService.getProtocol,
        _deviceById = deviceById ?? _loadDevice;

  /// From the loaded devices, else fetched once by id.
  static Future<DeviceInstance?> _loadDevice(String id) async {
    for (final device in AppState().devices) {
      if (device.id == id) return device;
    }
    final result = await DevicesService.getDevices(1, 0, DeviceSearchFilter('', deviceIds: [id]), null);
    for (final device in result.devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  static SecurityContext _realContext(String certPem, String keyPem) => SecurityContext(withTrustedRoots: true)
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));

  final _converter = LocalConverter();
  final Map<String, _Watch> _watches = {};
  final Map<String, _Conn> _conns = {};
  final Map<String, Protocol> _protocols = {};
  final Map<String, Future<Protocol?>> _protocolLoads = {};
  final Map<String, DateTime> _protocolFailures = {};
  bool _observing = false;
  bool _paused = false;
  String? _account;


  /// Whether a connection of [routeKey] exists; for tests and diagnostics.
  @visibleForTesting
  bool hasConnection(String routeKey) => _conns.containsKey(routeKey);

  /// Route key of the cloud connection.
  static const cloudRoute = 'cloud';

  /// Route key of the connection to the gateway [pairingId].
  static String gatewayRoute(String pairingId) => 'gateway:$pairingId';

  /// Counts one more view of [device]; the first one subscribes, as soon as
  /// the device can be reached (a paired gateway, or the cloud with
  /// `LIVE_MQTT_URL`).
  LiveHandle watch(DeviceInstance device) {
    _checkAccount();
    final watch = _acquire(device);
    watch.objects[device] = (watch.objects[device] ?? 0) + 1;
    return LiveHandle._(() {
      final left = (watch.objects[device] ?? 1) - 1;
      if (left > 0) {
        watch.objects[device] = left;
        return;
      }
      watch.objects.remove(device);
      _unwatch(watch);
    });
  }

  /// Calls [onValue] with every reading of the value that [source] names, as
  /// the platform's `raw-value` endpoint would return it (converted to the
  /// source's target characteristic), and the time of the message.
  ///
  /// The device is looked up and its type ensured first, which takes a moment;
  /// releasing the handle before that is done subscribes nothing. The device
  /// shares the subscription of [watch].
  LiveHandle watchRaw(RawValueSource source, void Function(dynamic value, DateTime time) onValue) {
    _checkAccount();
    var released = false;
    _Watch? watch;
    _RawListener? listener;
    unawaited(() async {
      try {
        final device = await _deviceById(source.deviceId);
        if (released || device == null) return;
        await AppState().ensureDeviceTypes([device.device_type_id]);
        if (released) return;
        _checkAccount();
        final acquired = _acquire(device);
        watch = acquired;
        listener = _RawListener(source, onValue);
        acquired.raws.add(listener!);
      } catch (e) {
        _logger.d('Live: raw value source not watched (${e.runtimeType})');
      }
    }());
    return LiveHandle._(() {
      released = true;
      final w = watch, l = listener;
      if (w == null || l == null) return;
      w.raws.remove(l);
      _unwatch(w);
    });
  }

  /// The watch of [device], created and routed when it is the first. A device
  /// without a route (no paired gateway yet, cloud off) is watched anyway and
  /// subscribed once [_rerouteAll] finds one.
  _Watch _acquire(DeviceInstance device) {
    final existing = _watches[device.id];
    if (existing != null) return existing;
    _ensureObserver();
    final watch = _Watch(device);
    _watches[device.id] = watch;
    _route(watch);
    return watch;
  }

  /// Ends [watch] when nothing uses it any more.
  void _unwatch(_Watch watch) {
    // A watch that is gone (account change) has nothing to give back.
    if (_watches[watch.deviceId] != watch) return;
    if (watch.objects.isNotEmpty || watch.raws.isNotEmpty) return;
    _watches.remove(watch.deviceId);
    _leaveRoute(watch);
  }

  /// Subscribes [watch] where its device can be reached now, leaving the
  /// route it had: the paired gateways are only known a while after start, and
  /// a gateway can become reachable or unreachable while a view is open.
  void _route(_Watch watch) {
    final route = _routeOf(watch.device);
    if (route?.key == watch.routeKey && route?.topic == watch.topic) return;
    _leaveRoute(watch);
    if (route == null) return;
    watch.routeKey = route.key;
    watch.topic = route.topic;
    final conn = _conns[route.key] ?? _open(route);
    conn.connection.subscribe(route.topic);
  }

  void _leaveRoute(_Watch watch) {
    final key = watch.routeKey, topic = watch.topic;
    watch.routeKey = null;
    watch.topic = null;
    if (key == null || topic == null) return;
    final conn = _conns[key];
    if (conn == null) return;
    conn.connection.unsubscribe(topic);
    if (!_watches.values.any((w) => w.routeKey == key)) _close(conn);
  }

  void _rerouteAll() {
    for (final watch in _watches.values.toList()) {
      _route(watch);
    }
  }

  /// Drops every connection and subscription; call when the signed-in account
  /// changes. The next [watch] uses the new account's certificate.
  void accountChanged() {
    for (final conn in _conns.values.toList()) {
      _close(conn);
    }
    _watches.clear();
    _account = null;
  }

  void _checkAccount() {
    final account = Settings.getAccount();
    if (_account != null && account != _account) accountChanged();
  }

  void _ensureObserver() {
    if (_observing) return;
    WidgetsBinding.instance.addObserver(this);
    // AppState notifies when networks and their paired gateways change.
    AppState().addListener(_rerouteAll);
    _observing = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _paused = true;
        for (final conn in _conns.values) {
          conn.retry?.cancel();
          conn.retry = null;
          conn.connection.disconnect();
        }
      case AppLifecycleState.resumed:
        _paused = false;
        _checkAccount();
        _rerouteAll();
        for (final conn in _conns.values.toList()) {
          _connect(conn);
        }
      default:
        break;
    }
  }

  _Route? _routeOf(DeviceInstance device) {
    final gateway = device.network?.localGateways?.firstOrNull;
    if (gateway != null && gateway.ip.isNotEmpty) {
      return _Route(gatewayRoute(gateway.pairingId), 'event/${device.local_id}/+', gateway);
    }
    if (_cloudEndpoint() == null) return null;
    return _Route(cloudRoute, 'event/${device.owner_id}/${device.local_id}/+', null);
  }

  _Conn _open(_Route route) {
    _account ??= Settings.getAccount();
    final conn = _Conn(route, LiveConnection.factory());
    conn.messageSub = conn.connection.messages.listen((m) => _onMessage(conn, m.$1, m.$2));
    conn.stateSub = conn.connection.states.listen((s) => _logger.d('Live ${route.key}: ${s.name}'));
    _conns[route.key] = conn;
    if (!_paused) _connect(conn);
    return conn;
  }

  void _close(_Conn conn) {
    conn.closed = true;
    conn.retry?.cancel();
    conn.messageSub?.cancel();
    conn.stateSub?.cancel();
    conn.connection.disconnect();
    if (identical(_conns[conn.route.key], conn)) _conns.remove(conn.route.key);
  }

  /// Parameters for the next attempt of [route]; null when the cloud
  /// certificate is not available.
  Future<LiveConnectParams?> _paramsOf(_Route route) async {
    final gateway = route.gateway;
    if (gateway != null) {
      final login = await _gatewayLogin(gateway.pairingId);
      return (context: null, username: login?.username, password: login?.password);
    }
    final cert = await _certificate();
    if (cert == null) return null;
    return (context: _contextOf(cert.certPem, cert.keyPem), username: null, password: null);
  }

  Future<void> _connect(_Conn conn) async {
    conn.retry?.cancel();
    conn.retry = null;
    try {
      final params = await _paramsOf(conn.route);
      if (conn.closed || _paused) return;
      if (params == null) {
        _logger.d('Live ${conn.route.key}: no client certificate yet');
        conn.retry = Timer(LiveConnection.backoff(conn.failures++), () => _connect(conn));
        return;
      }
      final endpoint = conn.route.gateway != null
          ? (host: conn.route.gateway!.ip, port: mgwBrokerPort)
          : _cloudEndpoint();
      if (endpoint == null) return;
      final clientId = await _clientId(conn.route.gateway?.pairingId ?? '');
      if (conn.closed || _paused) return;
      conn.failures = 0;
      // Subscribed before connecting: the connection takes them along on every
      // reconnect of its own.
      for (final watch in _watches.values) {
        final topic = watch.topic;
        if (watch.routeKey == conn.route.key && topic != null) conn.connection.subscribe(topic);
      }
      await conn.connection.connect(
        endpoint.host,
        endpoint.port,
        context: params.context,
        username: params.username,
        password: params.password,
        clientId: clientId,
        refresh: () async => (await _paramsOf(conn.route)) ?? (throw StateError('no certificate')),
      );
    } catch (e) {
      _logger.d('Live ${conn.route.key}: could not connect (${e.runtimeType})');
      // A failing context or store is retried like a missing certificate.
      if (!conn.closed && !_paused) {
        conn.retry?.cancel();
        conn.retry = Timer(LiveConnection.backoff(conn.failures++), () => _connect(conn));
      }
    }
  }

  // ---- messages ----------------------------------------------------------

  Future<void> _onMessage(_Conn conn, String topic, Uint8List payload) async {
    try {
      await _handle(conn, topic, payload);
    } catch (e) {
      _logger.d('Live ${conn.route.key}: message dropped (${e.runtimeType})');
    }
  }

  Future<void> _handle(_Conn conn, String topic, Uint8List payload) async {
    final parts = topic.split('/');
    final cloud = conn.route.gateway == null;
    if (parts.isEmpty || parts.first != 'event' || parts.length != (cloud ? 4 : 3)) return;
    final localId = cloud ? parts[2] : parts[1];
    final serviceLocalId = parts.last;

    _Watch? watch;
    for (final w in _watches.values) {
      if (w.routeKey != conn.route.key || w.localId != localId) continue;
      if (cloud && w.ownerId != parts[1]) continue;
      watch = w;
      break;
    }
    if (watch == null) return;
    final type = AppState().deviceTypes[watch.typeId];
    if (type == null) return;
    Service? service;
    for (final s in type.services) {
      if (s.local_id == serviceLocalId) {
        service = s;
        break;
      }
    }
    if (service == null) return;

    final protocol = _protocols[service.protocol_id] ?? await _loadProtocol(service.protocol_id);
    if (protocol == null) return;
    // The view may have gone while the protocol loaded.
    if (_watches[watch.deviceId] != watch) return;

    final decoded = _decode(cloud, protocol, payload);
    if (decoded == null) return;
    final time = decoded.time ?? _now();
    for (final object in watch.objects.keys.toList()) {
      _apply(object, service, protocol, decoded.segments, time);
    }
    for (final raw in watch.raws.toList()) {
      if (raw.source.serviceId != service.id) continue;
      _applyRaw(raw, service, protocol, decoded.segments, time);
    }
  }

  Future<Protocol?> _loadProtocol(String id) {
    final failed = _protocolFailures[id];
    if (failed != null && _now().difference(failed) < const Duration(seconds: 30)) {
      return Future.value(null);
    }
    return _protocolLoads.putIfAbsent(id, () async {
      try {
        final protocol = await _protocol(id);
        if (protocol == null) {
          _protocolFailures[id] = _now();
        } else {
          _protocols[id] = protocol;
        }
        return protocol;
      } catch (e) {
        _protocolFailures[id] = _now();
        return null;
      } finally {
        _protocolLoads.remove(id);
      }
    });
  }

  ({Map<String, String> segments, DateTime? time})? _decode(bool cloud, Protocol protocol, Uint8List payload) {
    if (!cloud) {
      // A gateway event is what the platform receives as the segment "data":
      // the cloud connector forwards it as {"data": <payload>}
      // (mgw-device-cloud-connector, handler/message_hdl/device_event.go).
      return (
        segments: {mgwPayloadSegment: utf8.decode(payload, allowMalformed: true)},
        time: null,
      );
    }
    final json = jsonDecode(utf8.decode(payload));
    if (json is! Map) return null;
    DateTime? time;
    final segments = <String, String>{};
    json.forEach((key, value) {
      if (key == timestampKey) {
        time = value is String ? _parseTime(value) : null;
      } else if (key is String) {
        segments[key] = value is String ? value : jsonEncode(value);
      }
    });
    return (segments: segments, time: time);
  }

  /// RFC 3339 with up to nanoseconds; Dart reads microseconds.
  static DateTime? _parseTime(String value) =>
      DateTime.tryParse(value.replaceFirstMapped(RegExp(r'(\.\d{6})\d+'), (m) => m.group(1)!));

  void _apply(DeviceInstance device, Service service, Protocol protocol, Map<String, String> segments, DateTime time) {
    var changed = false;
    for (final state in device.states) {
      if (state.serviceId != service.id) continue;
      if (state.isControlling || state.transitioning || SwitchCommands.isRunning(state)) continue;
      final path = state.path;
      if (path == null) continue;
      final extracted = extractValue(service, protocol, segments, path);
      if (extracted == null) {
        _logger.d('Live: no value at $path');
        continue;
      }
      final value = _toPreferred(state, extracted.value, extracted.characteristicId);
      if (value == null) continue;
      // The setter first: it bumps valueWrites, which keeps a time that arrives
      // late from a load (device_mixin.loadMissingStateTimes) off this value,
      // and it clears the time that belonged to the old value.
      state.value = value.value;
      state.lastMessageTime = time;
      NativePipe.handleDeviceStateUpdate(state);
      changed = true;
    }
    if (changed) device.notifyStateChanged();
  }

  void _applyRaw(_RawListener raw, Service service, Protocol protocol, Map<String, String> segments, DateTime time) {
    final source = raw.source;
    final extracted = extractValue(service, protocol, segments, source.column);
    if (extracted == null) return;
    var value = extracted.value;
    if (!_finite(value)) return;
    final target = source.targetCharacteristicId;
    if (target != null && target.isNotEmpty && target != extracted.characteristicId) {
      final from = extracted.characteristicId;
      if (from == null) return;
      final conceptId = source.conceptId ?? AppState().platformFunctions[extracted.functionId]?.concept_id;
      final converted = _convert(value, from, target, conceptId);
      if (converted == null) return;
      value = converted.value;
      if (!_finite(value)) return;
    }
    try {
      raw.onValue(value, time);
    } catch (e) {
      _logger.d('Live: raw value listener failed (${e.runtimeType})');
    }
  }

  static bool _finite(dynamic value) => value is! num || value.isFinite;

  /// The value in the characteristic the user chose for the function of
  /// [state]; null (not wrapped) when it cannot be converted, or when the
  /// result is NaN or infinite.
  ({dynamic value})? _toPreferred(DeviceState state, dynamic value, String? from) {
    if (!_finite(value)) return null;
    final preferred = Settings.getFunctionPreferredCharacteristicId(state.functionId);
    if (preferred == null || preferred == from) return (value: value);
    if (from == null) {
      _logger.d('Live: ${state.functionId} has no characteristic to convert from');
      return null;
    }
    final conceptId = AppState().platformFunctions[state.functionId]?.concept_id;
    final converted = _convert(value, from, preferred, conceptId);
    if (converted == null || !_finite(converted.value)) return null;
    return converted;
  }

  ({dynamic value})? _convert(dynamic value, String from, String to, String? conceptId) {
    final conversions = conceptId == null ? null : AppState().concepts[conceptId]?.conversions;
    try {
      return (
        value: _converter.convert(
          value,
          from,
          to,
          extensions: [
            for (final c in conversions ?? const [])
              ConversionEdge(
                  from: c.from, to: c.to, distance: c.distance, formula: c.formula, placeholderName: c.placeholder_name),
          ],
        ),
      );
    } on ConversionException catch (e) {
      _logger.d('Live: not converted to $to ($e)');
      return null;
    }
  }
}

class _Route {
  final String key;
  final String topic;

  /// Null for the cloud.
  final MGW? gateway;

  _Route(this.key, this.topic, this.gateway);
}

class _RawListener {
  final RawValueSource source;
  final void Function(dynamic value, DateTime time) onValue;

  _RawListener(this.source, this.onValue);
}

/// The views of one device. Views can hold different [DeviceInstance] objects
/// of it, since a reload replaces them, so each object is counted on its own
/// and every one of them gets the live values. Raw listeners
/// ([LiveValues.watchRaw]) share the subscription.
class _Watch {
  /// The object the watch was made for; it answers the route questions.
  final DeviceInstance device;
  final String deviceId;
  final String localId;
  final String ownerId;
  final String typeId;

  /// The current route; null while the device cannot be reached live.
  String? routeKey;
  String? topic;
  final Map<DeviceInstance, int> objects = Map.identity();
  final List<_RawListener> raws = [];

  _Watch(this.device)
      : deviceId = device.id,
        localId = device.local_id,
        ownerId = device.owner_id,
        typeId = device.device_type_id;
}

class _Conn {
  final _Route route;
  final LiveConnection connection;
  StreamSubscription<(String, Uint8List)>? messageSub;
  StreamSubscription<LiveConnectionState>? stateSub;
  Timer? retry;
  int failures = 0;
  bool closed = false;

  _Conn(this.route, this.connection);
}
