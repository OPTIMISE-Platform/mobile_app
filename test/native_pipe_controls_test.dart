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

@Tags(['isar'])
library;

import "dart:async";
import "dart:convert";

import "package:flutter/services.dart";
import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:flutter_test/flutter_test.dart";
import "package:isar_community/isar.dart";
import "package:mobile_app/app_state.dart";
import "package:mobile_app/config/functions/function_config.dart";
import "package:mobile_app/models/aspect.dart";
import "package:mobile_app/models/characteristic.dart";
import "package:mobile_app/models/concept.dart";
import "package:mobile_app/models/content.dart";
import "package:mobile_app/models/content_variable.dart";
import "package:mobile_app/models/device_group.dart";
import "package:mobile_app/models/device_instance.dart";
import "package:mobile_app/models/device_state.dart";
import "package:mobile_app/models/device_type.dart";
import "package:mobile_app/models/exception_log_element.dart";
import "package:mobile_app/models/function.dart";
import "package:mobile_app/models/mgw.dart";
import "package:mobile_app/models/network.dart";
import "package:mobile_app/models/service.dart";
import "package:mobile_app/native_pipe.dart";

import "fake_backend.dart";
import "golden_helper.dart";
import "test_helper.dart";

const _tempGet = "urn:infai:ses:measuring-function:temperature";
const _tempSet = "urn:infai:ses:controlling-function:set-temperature";
const _platformBatch = "/device-command/commands/batch";
const _gatewayEndpoints = "/core/api/core-manager/endpoints";
const _gatewayBatch = "/mgw-dc/commands/batch";

/// Long enough for a group to take its network from the device ids: the
/// group's ids are matched by their first 57 characters.
const _deviceId = "urn:infai:ses:device:01234567-89ab-cdef-0123-456789abcdef";
const _groupMemberId = "$_deviceId-member";

const _codec = StandardMethodCodec();

void main() {
  late Isar db;
  late FakeBackend backend;
  late String onOff;
  late String setOn;
  late String setOff;

  ContentVariable variable(String name, String functionId) => ContentVariable("cv-$name", name, null, null, "air", functionId,
      "https://schema.org/Float", null, null, null, const ["air"]);

  Content content(List<ContentVariable> variables) => Content("content", "json", "segment",
      ContentVariable("root", "root", null, null, null, null, "https://schema.org/StructuredValue", variables, null, null));

  /// A heater: reads whether it is on and the temperature, switches and sets it.
  DeviceType heaterType() => DeviceType("type-heater", "Heater", "", "class-heater", [
        Service("service-1", "local-service-1", "Heating", "", "protocol", "request", "group-1", [
          content([variable("on", setOn)]),
          content([variable("off", setOff)]),
          content([variable("set", _tempSet)]),
        ], [
          content([variable("is-on", onOff), variable("temperature", _tempGet)]),
        ]),
      ], null);

  setUpAll(() async {
    await setUpGoldenEnvironment();
    onOff = dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!;
    setOn = dotenv.env["FUNCTION_SET_ON_STATE"]!;
    setOff = dotenv.env["FUNCTION_SET_OFF_STATE"]!;
    db = await openTestIsar([
      DeviceInstanceSchema,
      DeviceGroupSchema,
      NetworkSchema,
      ExceptionLogElementSchema,
    ]);
    await db.writeTxn(() async {
      await db.deviceInstances.put(DeviceInstance(_deviceId, "$_deviceId-local", "Heater", null, "type-heater", false, "owner", "Heater",
          DeviceConnectionStatus.online));
      await db.deviceGroups.put(DeviceGroup("group-1", "All heaters", [
        for (final f in [onOff, setOn, setOff, _tempGet, _tempSet])
          DeviceGroupCriteria()
            ..function_id = f
            ..device_class_id = "class-heater"
            ..aspect_id = "air"
      ], "", [_groupMemberId], null));
    });
  });

  setUp(() {
    final state = AppState();
    state.platformFunctions[onOff] = PlatformFunction(onOff, "get on", "concept-on-off", "Power");
    state.platformFunctions[setOn] = PlatformFunction(setOn, "on", "concept-on-off", "On");
    state.platformFunctions[setOff] = PlatformFunction(setOff, "off", "concept-on-off", "Off");
    state.platformFunctions[_tempGet] = PlatformFunction(_tempGet, "get temperature", "concept-temp", "Temperature");
    state.platformFunctions[_tempSet] = PlatformFunction(_tempSet, "set temperature", "concept-temp", "Set temperature");
    final celsius = Characteristic("char-temp", "Temperature", ContentVariable.float, 5, 30, null, null, "°C", null);
    state.concepts["concept-temp"] = Concept("concept-temp", "temperature", "char-temp", [celsius]);
    // So the pipe finds nothing missing and fetches nothing.
    state.characteristics["char-temp"] = celsius;
    state.aspects["air"] = Aspect("air", "Air", null);
    state.fetchDeviceTypes = (maxAge, {serveStale}) async => [heaterType()];
    reinit();
    // A gateway serves the network of the heater and of the group.
    state.networks.add(Network("network-1", "Home", false, ["$_deviceId-local"], [_deviceId], DeviceConnectionStatus.online, "", "owner")
      ..localGateways = [MGW("gw.test", "gw.test", "", "gw.test", networkId: "network-1")]);
    backend = FakeBackend()
      ..serveJson("GET", _gatewayEndpoints, 200, {
        "endpoint-1": {"id": "endpoint-1", "location": "/mgw-dc", "ref": "r"}
      });
    serveGoldenBackend(backend);
    NativePipe.init();
    NativePipe.resetWatchedForTest();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  /// Calls [method] as the platform side does and returns what it answers.
  Future<dynamic> call(String method, dynamic arguments) async {
    final answer = Completer<ByteData?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        NativePipe.controlMethodChannel.name, _codec.encodeMethodCall(MethodCall(method, arguments)), answer.complete);
    return _codec.decodeEnvelope((await answer.future)!);
  }

  List<Map<String, dynamic>> gatewayCommands() => [
        for (final r in backend.requests.where((r) => r.method.toUpperCase() == "POST" && r.uri.path == _gatewayBatch))
          for (final c in r.data as List) (jsonDecode(jsonEncode(c)) as Map<String, dynamic>),
      ];

  void serveGateway(dynamic answer) => backend.serveJson("POST", _gatewayBatch, 200, answer);

  Future<List<Map<String, dynamic>>> listed() async =>
      [for (final e in jsonDecode(await call("getToggleStateless", null) as String) as List) e as Map<String, dynamic>];

  Map<String, dynamic> byKind(List<Map<String, dynamic>> entries, {required bool group, required String kind}) =>
      entries.singleWhere((e) => (e["groupId"] != null) == group && e["kind"] == kind);

  test("the list offers the on/off and the value controls of the device and of the group", () async {
    final entries = await listed();

    expect(entries, hasLength(4), reason: "a toggle and a range for the device, a toggle and a range for the group");
    expect(entries.map((e) => e["name"]), ["All heaters", "All heaters", "Heater", "Heater"],
        reason: "sorted by the name shown, the group before the device it was listed after");
    final deviceToggle = byKind(entries, group: false, kind: "toggle");
    expect(deviceToggle["deviceId"], _deviceId);
    expect(deviceToggle["functionId"], onOff);
    expect(deviceToggle["name"], "Heater");
    final deviceRange = byKind(entries, group: false, kind: "range");
    expect(deviceRange["functionId"], _tempGet);
    expect([deviceRange["min"], deviceRange["max"], deviceRange["step"], deviceRange["unit"]], [5.0, 30.0, 0.5, "°C"]);
    final groupToggle = byKind(entries, group: true, kind: "toggle");
    expect(groupToggle["groupId"], "group-1");
    expect(groupToggle["deviceId"], isNull);
    expect(byKind(entries, group: true, kind: "range")["functionId"], _tempGet);
  });

  test("a changed reading reaches the platform side only once it asked for that reading", () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final events = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(NativePipe.controlMethodChannel, (c) async {
      if (c.method == "toggleEvent") events.add(jsonDecode(c.arguments as String) as Map<String, dynamic>);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(NativePipe.controlMethodChannel, null));
    final entries = await listed();
    final toggle = byKind(entries, group: false, kind: "toggle");
    final range = byKind(entries, group: false, kind: "range");
    final onOffReading = DeviceState.fromJson(toggle)..value = true;
    final tempReading = DeviceState.fromJson(range)..value = 21.0;

    NativePipe.handleDeviceStateUpdate(onOffReading);
    NativePipe.handleDeviceStateUpdate(tempReading);
    await pumpEventQueue();
    expect(events, isEmpty, reason: "no control is shown yet");

    final id = {...toggle}..removeWhere((k, _) => ["value", "kind", "min", "max", "step", "unit", "integer", "aspectIds"].contains(k));
    serveGateway([
      {"status_code": 200, "message": [true]}
    ]);
    await call("getToggleStates", jsonEncode([id]));
    NativePipe.handleDeviceStateUpdate(onOffReading);
    NativePipe.handleDeviceStateUpdate(tempReading);
    await pumpEventQueue();

    expect(events, hasLength(1), reason: "only the reading of the shown control");
    expect(events.single["functionId"], onOff);
    expect(events.single["deviceId"], _deviceId);
  });

  test("the states of the ids come back with the fields they were sent with, a value, the kind and the slider", () async {
    final entries = await listed();
    // Ids as the platform side sends them: no value, no kind, no slider.
    final ids = [
      for (final e in entries)
        {...e}..removeWhere((k, _) => ["value", "kind", "min", "max", "step", "unit", "integer", "aspectIds"].contains(k)),
    ];
    // The gateway answers the on/off reading with true and the rest with 21.5,
    // in the order the readings are asked for.
    serveGateway([for (final e in entries) {"status_code": 200, "message": e["kind"] == "toggle" ? [true] : [21.5]}]);

    final answers = [for (final a in jsonDecode(await call("getToggleStates", jsonEncode(ids)) as String) as List) a as Map<String, dynamic>];

    expect(answers, hasLength(4));
    for (var i = 0; i < ids.length; i++) {
      for (final field in ids[i].keys) {
        expect(answers[i][field], ids[i][field], reason: "$field of the control id is unchanged");
      }
      expect(answers[i]["kind"], entries[i]["kind"]);
      expect(answers[i]["value"], entries[i]["kind"] == "toggle" ? true : 21.5);
    }
    expect(answers.where((a) => a["kind"] == "range").every((a) => a["max"] == 30.0), isTrue);
    expect(backend.requests.where((r) => r.uri.path == _platformBatch), isEmpty,
        reason: "readings of a device and a group in a network with a gateway go there");
    final asked = gatewayCommands();
    expect(asked.where((c) => c["group_id"] != null), hasLength(2));
    expect(asked.where((c) => c["device_id"] != null), hasLength(2));
  });

  test("a value set on a group reaches the gateway as a command of the group and returns the value read back", () async {
    serveGateway([
      {"status_code": 200, "message": [22.0]}
    ]);
    final range = byKind(await listed(), group: true, kind: "range");

    final answer = jsonDecode(await call("setValue", jsonEncode({...range, "value": 22.2})) as String) as Map<String, dynamic>;

    final commands = gatewayCommands();
    expect(commands.map((c) => c["function_id"]), [_tempSet, _tempGet], reason: "set it, then read it back");
    expect(commands.first["group_id"], "group-1");
    expect(commands.first["device_id"], isNull);
    expect(commands.first["input"], 22.2);
    expect(backend.requests.where((r) => r.uri.path == _platformBatch), isEmpty);
    expect((answer["responses"] as List).single["status_code"], 200);
    final state = answer["state"] as Map<String, dynamic>;
    expect(state["value"], 22.0);
    expect(state["kind"], "range");
    expect(state["groupId"], "group-1");
  });

  test("a value is held to the range of the control", () async {
    serveGateway([
      {"status_code": 200, "message": [30.0]}
    ]);
    final range = byKind(await listed(), group: false, kind: "range");

    await call("setValue", jsonEncode({...range, "value": 99.0}));

    expect(gatewayCommands().first["input"], 30.0);
    expect(gatewayCommands().first["device_id"], _deviceId);
  });

  test("toggling a group sends the control for the new state to the gateway", () async {
    serveGateway([
      {"status_code": 200, "message": []}
    ]);
    final toggle = byKind(await listed(), group: true, kind: "toggle");

    final answer = jsonDecode(await call("setToggle", jsonEncode({...toggle, "value": true})) as String) as Map<String, dynamic>;

    final commands = gatewayCommands();
    expect(commands.single["function_id"], setOn);
    expect(commands.single["group_id"], "group-1");
    expect((answer["state"] as Map)["value"], true);
    expect((answer["state"] as Map)["kind"], "toggle");
  });

  test("toggling a device off sends the off control to the gateway", () async {
    serveGateway([
      {"status_code": 200, "message": []}
    ]);
    final toggle = byKind(await listed(), group: false, kind: "toggle");

    await call("setToggle", jsonEncode({...toggle, "value": false}));

    final commands = gatewayCommands();
    expect(commands.single["function_id"], setOff);
    expect(commands.single["device_id"], _deviceId);
  });

  test("a failed command is answered with its status, not thrown", () async {
    serveGateway([
      {"status_code": 500, "message": "boom"}
    ]);
    final toggle = byKind(await listed(), group: true, kind: "toggle");

    final answer = jsonDecode(await call("setToggle", jsonEncode({...toggle, "value": true})) as String) as Map<String, dynamic>;

    expect((answer["responses"] as List).single["status_code"], 500);
  });

  test("an id of a device that is gone is an error", () async {
    final toggle = byKind(await listed(), group: false, kind: "toggle");

    await expectLater(call("setToggle", jsonEncode({...toggle, "deviceId": "gone", "value": true})), throwsA(isA<PlatformException>()));
  });
}
