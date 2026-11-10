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

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// The platform functions of a lamp that the Light card of the detail page
/// groups, from the environment like the other function ids: they differ
/// between platforms. A missing key means no card for that kind.
String? get setBrightnessFunctionId => dotenv.env['FUNCTION_SET_BRIGHTNESS'];
String? get setColourTemperatureFunctionId => dotenv.env['FUNCTION_SET_COLOR_TEMPERATURE'];

String? get setColourFunctionId => dotenv.env['FUNCTION_SET_COLOR'];

/// The characteristic that carries colour temperature in mired; Kelvin is the
/// concept's base characteristic.
const miredCharacteristicId = 'urn:infai:ses:characteristic:e51a6555-e9b1-4000-8058-d450fc543e08';

/// The range a colour temperature slider covers when the characteristic gives
/// none: what lamps offer, 2000 to 6500 K, which is 153 to 500 mired.
const colourTemperatureKelvinRange = (2000.0, 6500.0);
const colourTemperatureMiredRange = (153.0, 500.0);
