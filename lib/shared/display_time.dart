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

import 'package:flutter/foundation.dart';

/// Set only by golden tests: the device's own time zone would otherwise make
/// the rendered goldens depend on where and when they were generated.
@visibleForTesting
bool useUtcForDisplayTime = false;

/// Converts [t] to the zone a display site should render it in. Production
/// behaviour is unchanged ([t.toLocal]); tests can switch every display site
/// to UTC at once via [useUtcForDisplayTime].
DateTime toDisplayTime(DateTime t) =>
    useUtcForDisplayTime ? t.toUtc() : t.toLocal();
