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

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/shared/device_controls.dart';

/// A radiator thermostat as zigbee2mqtt SONOFF TRVZB is modelled: a setpoint
/// and an external temperature input among the inputs, the measured
/// temperature and the setpoint among the outputs.

const getTemperature = 'urn:infai:ses:measuring-function:get-temperature';
const setTemperature = '$controllingFunctionPrefix:set-temperature';
const celsius = 'urn:infai:ses:characteristic:5ba31623-0ccb-4488-bfb7-f73b50e03b5a';

const setpointAspects = ['target', 'air', 'indoor'];
const readingAspects = ['air', 'indoor', 'reading'];

/// The functions, aspects and the temperature concept the thermostat needs.
/// Degree Celsius has no maximum, as on the platform.
void registerThermostatMetadata() {
  final state = AppState();
  state.platformFunctions[getTemperature] =
      PlatformFunction(getTemperature, 'Get-Temperature', 'concept-temperature', 'Get-Temperature');
  state.platformFunctions[setTemperature] =
      PlatformFunction(setTemperature, 'Set-Temperature', 'concept-temperature', 'Set-Temperature');
  final characteristic = Characteristic(celsius, 'Degree Celsius', ContentVariable.float, -273.15, null, null, null, '°C', null);
  state.characteristics[celsius] = characteristic;
  state.concepts['concept-temperature'] = Concept('concept-temperature', 'Temperature', celsius, [characteristic]);
  for (final name in ['Air', 'Indoor', 'Reading', 'Target']) {
    state.aspects[name.toLowerCase()] = Aspect(name.toLowerCase(), name, null);
  }
  // A config built before the concept was there has no characteristic.
  reinit();
}

ContentVariable _variable(String name, String functionId, List<String> aspects) => ContentVariable(
    'cv-$name', name, celsius, null, aspects.first, functionId, 'https://schema.org/Float', null, null, null, aspects);

Service _service(String name, ContentVariable variable, {required bool input}) => Service('svc-$name',
    'local-$name', name, '', 'protocol-1', 'request', 'group-t',
    input ? [Content('c-$name', 'json', 'segment-1', variable)] : null,
    input ? null : [Content('c-$name', 'json', 'segment-1', variable)]);

/// The thermostat's device type, with id [id].
DeviceType trvzbType(String id) => DeviceType(id, 'zigbee2mqtt SONOFF TRVZB', '', thermostatDeviceClass, [
      _service('set_setpoint', _variable('occupied_heating_setpoint', setTemperature, setpointAspects), input: true),
      _service('set_external', _variable('external_temperature_input', setTemperature, readingAspects), input: true),
      _service('get_local', _variable('local_temperature', getTemperature, readingAspects), input: false),
      _service('get_setpoint', _variable('occupied_heating_setpoint', getTemperature, setpointAspects), input: false),
    ], null);

/// The criteria the platform keeps for a group of such thermostats: each
/// variable's aspects, each aspect alone, and the controlling function's
/// device class.
List<DeviceGroupCriteria> trvzbGroupCriteria() {
  Map<String, dynamic> criterion(String functionId, List<String> aspectIds) => {
        'aspect_id': aspectIds.isEmpty ? '' : ([...aspectIds]..sort()).first,
        if (aspectIds.isNotEmpty) 'aspect_ids': aspectIds,
        'device_class_id': aspectIds.isEmpty ? thermostatDeviceClass : '',
        'function_id': functionId,
        'interaction': functionId == setTemperature ? 'request' : 'event',
      };
  const aspectSets = [
    setpointAspects,
    readingAspects,
    ['air'],
    ['indoor'],
    ['reading'],
    ['target'],
  ];
  return [
    for (final a in aspectSets) criterion(getTemperature, a),
    for (final a in aspectSets) criterion(setTemperature, a),
    criterion(setTemperature, const []),
  ].map(DeviceGroupCriteria.fromJson).toList();
}
