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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/config/functions/get_on_off_state.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';

/// What the tile of an on/off reading shows.
enum OnOffReading { on, off, mixed, unknown }

/// Why a device cannot be switched right now, the two cases the device list
/// tells apart.
enum Unavailability { offline, notLocal }

/// Whether [functionId] is the on/off reading, which the sensors page shows
/// as a switch tile.
bool isOnOffReading(String functionId) =>
    functionConfigs[functionId] is FunctionConfigGetOnOffState;

/// Whether [state] is an on/off reading that a control among [states] can
/// switch. The binary-state function also reads motion, contacts and button
/// inputs, which are no switch.
///
/// A group pairs by device class, so any control in it counts; a device pairs
/// by service group and aspects, as the toggle does.
bool isSwitchableOnOff(DeviceState state, Iterable<DeviceState> states, {bool isGroup = false}) {
  if (state.isControlling || !isOnOffReading(state.functionId)) return false;
  final controls = functionConfigs[state.functionId]!.getAllRelatedControllingFunctions() ?? const [];
  if (isGroup) {
    return states.any((s) => s.isControlling && controls.contains(s.functionId));
  }
  return controls.any((f) => state.controlsFor(states, f).isNotEmpty);
}

/// Reads a device's boolean or a group's list of member values.
///
/// Members that did not answer (null) are left out as long as one did, so a
/// group with an unreachable member can still be switched both ways. A list
/// with both on and off is mixed; anything that is no on/off value, null
/// included, is unknown.
OnOffReading onOffReadingOf(dynamic value) {
  if (value is bool) return value ? OnOffReading.on : OnOffReading.off;
  if (value is! List) return OnOffReading.unknown;
  if (value.any((v) => v != null && v is! bool)) return OnOffReading.unknown;
  final anyOn = value.contains(true);
  final anyOff = value.contains(false);
  if (anyOn && anyOff) return OnOffReading.mixed;
  if (anyOn) return OnOffReading.on;
  if (anyOff) return OnOffReading.off;
  return OnOffReading.unknown;
}

/// The controlling function a toggle of [reading] sends: off when on, on
/// otherwise, and none while the state is unknown.
String? onOffTargetFunction(OnOffReading reading) => switch (reading) {
  OnOffReading.on => dotenv.env['FUNCTION_SET_OFF_STATE'],
  OnOffReading.off || OnOffReading.mixed => dotenv.env['FUNCTION_SET_ON_STATE'],
  OnOffReading.unknown => null,
};

/// The card colour of a tile that is on: the brand fill laid lightly over the
/// card surface, light enough that the card's text and the switch keep their
/// contrast (`test/switch_tile_test.dart`).
Color switchTileOnColor(ThemeData theme) => Color.alphaBlend(
  theme.colorScheme.primaryContainer.withValues(alpha: switchTileTintAlpha),
  theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow,
);

/// Opacity of the brand fill in [switchTileOnColor].
const double switchTileTintAlpha = 0.14;

/// The bottom row of a switch tile: the state as text and a switch.
///
/// [onToggle] null disables the switch. [unavailable] replaces the state with
/// the device list's unavailability hint; [busy] puts a spinner on the switch.
class SwitchTileFooter extends StatelessWidget {
  final OnOffReading reading;
  final Unavailability? unavailable;
  final bool busy;
  final VoidCallback? onToggle;

  const SwitchTileFooter({
    required this.reading,
    required this.busy,
    required this.onToggle,
    this.unavailable,
    super.key,
  });

  String get _label {
    return switch (unavailable) {
      Unavailability.offline => 'Offline',
      Unavailability.notLocal => 'Not local',
      null => _readingLabel,
    };
  }

  String get _readingLabel {
    return switch (reading) {
      OnOffReading.on => 'On',
      OnOffReading.off => 'Off',
      OnOffReading.mixed => 'Mixed',
      OnOffReading.unknown => 'Unknown',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      _label,
      maxLines: 1,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
    return Row(
      children: [
        Expanded(
          child: Align(
            // Its own height, not the Row's: the footer sits at the card's
            // bottom instead of filling the space left above it.
            heightFactor: 1,
            alignment: Alignment.centerLeft,
            // Scales the label down instead of wrapping it: the switch keeps
            // its size, so a large text scale has to give way here.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: unavailable != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          unavailable == Unavailability.offline
                              ? Icons.error
                              : Icons.lan_outlined,
                          color: context.appColors.warnInk,
                        ),
                        const SizedBox(width: Spacing.xxs),
                        label,
                      ],
                    )
                  : label,
            ),
          ),
        ),
        const SizedBox(width: Spacing.xxs),
        Stack(
          alignment: Alignment.center,
          children: [
            Switch(
              value: reading == OnOffReading.on,
              onChanged: onToggle == null ? null : (_) => onToggle!(),
              // A neutral thumb for a group whose members disagree: neither
              // position is true for all of them.
              thumbIcon: reading == OnOffReading.mixed && unavailable == null
                  ? const WidgetStatePropertyAll(Icon(Icons.remove))
                  : null,
              // The whole card is the tap target, so the switch needs no
              // padding of its own.
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            if (busy)
              const SizedBox.square(
                dimension: 20,
                child: DelayedCircularProgressIndicator(),
              ),
          ],
        ),
      ],
    );
  }
}
