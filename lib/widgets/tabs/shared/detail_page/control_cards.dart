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
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/config/functions/light_functions.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/shared/characteristic_conversion.dart';
import 'package:mobile_app/shared/colour_value.dart';
import 'package:mobile_app/shared/device_controls.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_tile.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_labels.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/inline_control.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

/// The composite cards at the top of the detail page's Control section: a
/// lamp's controls together, and a thermostat's temperatures. The models decide
/// by function and aspects which states a card takes; the rows it covers are
/// not repeated below it.

/// Sends [value] to [control], as the detail page's rows do.
typedef SendControl = Future<void> Function(DeviceState control, dynamic value);

const _targetAspect = 'target';
const _readingAspect = 'reading';

Characteristic? _characteristicOf(DeviceState control) => controlCharacteristic(control);

/// Whether a card can hold the numeric control [control]: its start value
/// converts into the control's characteristic and is a number, or its reading
/// is still loading (the control is disabled until then). Otherwise the row
/// with its dialog stays, so a value nobody knows is never stepped from.
bool _hasNumericStart(DeviceState control, List<DeviceState> states, List<DeviceState> readings, {required bool isGroup}) {
  final start = inlineStartValue(control, states, isGroup: isGroup);
  if (start == null) return false;
  return start.value is num || readings.any((r) => r.transitioning);
}

/// The single value of [value], for a group's list the one its members share.
dynamic _single(dynamic value) => value is List ? commonValue(value) : value;

/// The states of a lamp the Light card holds: its on/off reading, and the
/// controls for brightness, colour temperature and colour with the readings
/// they act on. A kind with more than one control, without a reading to show,
/// whose group members disagree, or (brightness, colour temperature) without
/// a start value in the control's characteristic stays a row. An on/off
/// reading with no known on/off value stays a row with its Set On/Off rows,
/// as the page shows an unknown switch.
class LightCardModel {
  final DeviceState? power;
  final DeviceState? brightness, temperature, colour;

  /// The readings and controls the card stands for.
  final Set<DeviceState> covered;

  const LightCardModel(this.power, this.brightness, this.temperature, this.colour, this.covered);
}

LightCardModel? lightCardOf(List<DeviceState> rows, List<DeviceState> states, {required bool isGroup}) {
  final covered = <DeviceState>{};

  DeviceState? controlOf(String? functionId, {bool numeric = true}) {
    if (functionId == null) return null;
    final controls = rows.where((s) => s.isControlling && s.functionId == functionId).toList();
    if (controls.length != 1) return null;
    final control = controls.single;
    final readings = readingsOfControl(control, states, isGroup: isGroup).where(rows.contains).toList();
    if (readings.isEmpty) return null;
    // Members that disagree have no value to put on a slider.
    final disagree = readings.any((r) {
      final v = r.value;
      return v is List && v.any((e) => e != null) && commonValue(v) == null;
    });
    if (isGroup && disagree) return null;
    if (numeric && !_hasNumericStart(control, states, readings, isGroup: isGroup)) return null;
    // A colour in a layout the wheel does not know, its control's or its
    // reading's, stays a row.
    if (!numeric && (colourFormatOf(_characteristicOf(control)) == null || _readingColourFormat(readings.first) == null)) {
      return null;
    }
    covered..add(control)..addAll(readings);
    return control;
  }

  final brightness = controlOf(setBrightnessFunctionId);
  final temperature = controlOf(setColourTemperatureFunctionId);
  final colour = controlOf(setColourFunctionId, numeric: false);
  if (brightness == null && temperature == null && colour == null) return null;

  // The page's test for an unknown switch; while loading the switch shows a
  // spinner and cannot be used either way.
  bool known(DeviceState s) => s.transitioning || onOffReadingOf(s.value) != OnOffReading.unknown;
  final switches = rows
      .where((s) =>
          binaryRoleOf(s, states, isGroup: isGroup) == BinaryRole.power &&
          isSwitchableOnOff(s, states, isGroup: isGroup) &&
          known(s))
      .toList();
  DeviceState? power;
  if (switches.length == 1) {
    power = switches.single;
    covered.add(power);
    final switching = relatedControllingFunctionsOf(power.functionId) ?? const <String>[];
    for (final f in switching) {
      covered.addAll(power.controlsFor(states, f));
    }
    // A group's switch is not paired by aspect: every on/off control of it is its.
    if (isGroup) covered.addAll(rows.where((s) => s.isControlling && switching.contains(s.functionId)));
  }
  return LightCardModel(power, brightness, temperature, colour, covered);
}

/// A thermostat: the setpoint reading with its control, the measured
/// temperature next to it, and the read-only heating states.
class ClimateCardModel {
  final DeviceState setpoint, control;
  final DeviceState? measured;
  final List<DeviceState> heating;
  final Set<DeviceState> covered;

  const ClimateCardModel(this.setpoint, this.control, this.measured, this.heating, this.covered);
}

/// One card per reading with the aspect Target that a numeric control sets
/// and that has a start value in the control's characteristic (as the Light
/// card's sliders). The measured temperature is the reading of the same
/// function with the aspect Reading, else the first without Target; the
/// heating states and measurement go to the first card.
List<ClimateCardModel> climateCardsOf(List<DeviceState> rows, List<DeviceState> states, {required bool isGroup}) {
  final cards = <ClimateCardModel>[];
  var measuredTaken = false;
  for (final r in rows.where((s) => !s.isControlling && hasAspectNamed(s, _targetAspect))) {
    final control = controlOfReading(r, states, isGroup: isGroup);
    final type = control == null ? null : _characteristicOf(control)?.type;
    if (control == null || (type != ContentVariable.float && type != ContentVariable.integer)) continue;
    if (!_hasNumericStart(control, states, [r], isGroup: isGroup)) continue;
    final others = rows.where((s) => !s.isControlling && s.functionId == r.functionId && !hasAspectNamed(s, _targetAspect)).toList();
    final measured = measuredTaken
        ? null
        : others.where((s) => hasAspectNamed(s, _readingAspect)).firstOrNull ?? others.firstOrNull;
    final heating = measuredTaken
        ? <DeviceState>[]
        : rows
            .where((s) =>
                const [BinaryRole.heatingRunning, BinaryRole.heatingEnabled].contains(binaryRoleOf(s, states, isGroup: isGroup)) &&
                !isSwitchableOnOff(s, states, isGroup: isGroup) &&
                heatingFlagOf(s.value) != null)
            .toList();
    final covered = <DeviceState>{r, control, if (measured != null) measured, ...heating};
    cards.add(ClimateCardModel(r, control, measured, heating, covered));
    measuredTaken = true;
  }
  return cards;
}

/// The chip text of a thermostat's heating states: "Heating off" when it is not
/// enabled, else "Heating" or "Idle" from the running state, else "Heating on"
/// from an enabled state alone; null when nothing is known.
String? climateChipText({dynamic running, dynamic enabled}) {
  final r = heatingFlagOf(running), e = heatingFlagOf(enabled);
  if (e == false) return 'Heating off';
  if (r != null) return r ? 'Heating' : 'Idle';
  if (e == true) return 'Heating on';
  return null;
}

/// The stepper of a setpoint: 0.5 steps (1 for whole numbers) within the range
/// the characteristic gives, else within a thermostat's 5 to 30 degrees.
InlineControlSpec? climateSetpointSpec(DeviceState control) {
  final c = _characteristicOf(control);
  if (c == null) return null;
  final integer = c.type == ContentVariable.integer;
  if (!integer && c.type != ContentVariable.float) return null;
  var min = c.min_value, max = c.max_value;
  if (min == null || max == null || !min.isFinite || !max.isFinite || max <= min) {
    final range = thermostatSetpointRange(c.id);
    (min, max) = range ?? (null, null);
  }
  return InlineControlSpec(InlineControlKind.stepper, integer: integer, min: min, max: max);
}

/// The layout of a colour reading, from its own characteristic.
ColourFormat? _readingColourFormat(DeviceState reading) => colourFormatOf(readingCharacteristic(reading.functionId));

/// The tone a lamp shows: its colour when that has saturation, else the white
/// of its colour temperature, else its colour (white without one). The colour
/// temperature is read in the reading's characteristic, mired or Kelvin.
Color lightSwatchColour(LightCardModel model, DeviceState? Function(DeviceState control) readingOf) {
  final colourValue = model.colour == null ? null : _single(readingOf(model.colour!)?.value);
  final colour = colourOf(colourValue);
  if (colour != null && HSVColor.fromColor(colour).saturation > .08) return colour;
  final reading = model.temperature == null ? null : readingOf(model.temperature!);
  if (reading != null) {
    final v = _single(reading.value);
    if (v is num && v > 0) {
      final mired = readingCharacteristicId(reading.functionId) == miredCharacteristicId;
      return kelvinToColour(mired ? 1e6 / v : v.toDouble());
    }
  }
  return colour ?? Colors.white;
}

/// The Light card. [readingOf] gives the reading a control acts on.
class LightCard extends StatefulWidget {
  final LightCardModel model;
  final List<DeviceState> states;
  final bool isGroup;
  final bool enabled;
  final SendControl onSend;
  final VoidCallback onTogglePower;

  const LightCard({
    required this.model,
    required this.states,
    required this.isGroup,
    required this.enabled,
    required this.onSend,
    required this.onTogglePower,
    super.key,
  });

  @override
  State<LightCard> createState() => _LightCardState();
}

class _LightCardState extends State<LightCard> {
  bool _wheelOpen = false;

  DeviceState? _readingOf(DeviceState control) =>
      readingsOfControl(control, widget.states, isGroup: widget.isGroup).where(widget.model.covered.contains).firstOrNull;

  bool _busy(DeviceState control) =>
      readingsOfControl(control, widget.states, isGroup: widget.isGroup).any((r) => r.transitioning);

  /// The brightness reading, converted into the brightness control's
  /// characteristic, as a share of that control's range; null when unknown.
  double? _brightnessFraction() {
    final control = widget.model.brightness;
    if (control == null) return null;
    final start = inlineStartValue(control, widget.states, isGroup: widget.isGroup)?.value;
    if (start is! num) return null;
    final spec = inlineControlSpec(control, start);
    final min = spec?.min, max = spec?.max;
    if (min == null || max == null || max <= min) return null;
    return ((start - min) / (max - min)).clamp(0.0, 1.0).toDouble();
  }

  Widget _slider(DeviceState control, String title) {
    final reading = _readingOf(control);
    final start = inlineStartValue(control, widget.states, isGroup: widget.isGroup)?.value;
    // Without a start value (still loading) the slider shows its minimum and stays disabled.
    final spec = inlineControlSpec(control, start is num ? start : 0, reading: reading);
    if (spec == null || spec.kind != InlineControlKind.slider) return const SizedBox.shrink();
    return InlineControl(
      spec: spec,
      value: start,
      unit: controlUnit(control),
      busy: _busy(control),
      enabled: widget.enabled && start is num && reading != null,
      onSend: (value) => widget.onSend(control, value),
      tile: (trailing) => ListTile(dense: true, title: Text(title), trailing: trailing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final power = model.power;
    final reading = power == null ? OnOffReading.unknown : onOffReadingOf(power.value);
    final on = reading == OnOffReading.on || reading == OnOffReading.mixed;
    final swatch = lightSwatchColour(model, _readingOf);
    final theme = Theme.of(context);
    final stateText = power == null
        ? null
        : switch (reading) {
            OnOffReading.on => 'On',
            OnOffReading.off => 'Off',
            OnOffReading.mixed => 'Mixed',
            OnOffReading.unknown => '-',
          };
    final dim = power != null && reading == OnOffReading.off;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: Container(
          key: const Key('lightSwatch'),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: dim ? swatch.withValues(alpha: .3) : swatch,
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.outline),
          ),
        ),
        title: const Text('Light'),
        subtitle: stateText == null ? null : Text(stateText),
        trailing: power == null
            ? null
            : power.transitioning
                ? const SizedBox.square(dimension: 24, child: DelayedCircularProgressIndicator())
                : Switch(
                    value: on,
                    thumbIcon: reading == OnOffReading.mixed ? const WidgetStatePropertyAll(Icon(Icons.remove)) : null,
                    onChanged: widget.enabled && reading != OnOffReading.unknown ? (_) => widget.onTogglePower() : null,
                  ),
      ),
      if (model.brightness != null) _slider(model.brightness!, 'Brightness'),
      if (model.temperature != null) _slider(model.temperature!, 'Color temperature'),
      if (model.colour != null) _colourSection(model.colour!, swatch),
      const SizedBox(height: Spacing.sm),
    ]);
  }

  Widget _colourSection(DeviceState control, Color swatch) {
    final format = colourFormatOf(_characteristicOf(control))!;
    final reading = _readingOf(control);
    final value = _single(reading?.value);
    final readingFormat = reading == null ? null : _readingColourFormat(reading);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        dense: true,
        title: const Text('Color'),
        onTap: () => setState(() => _wheelOpen = !_wheelOpen),
        trailing: Icon(_wheelOpen ? Icons.expand_less : Icons.expand_more),
      ),
      if (_wheelOpen)
        ColourWheel(
          value: value,
          format: format,
          readingFormat: readingFormat,
          // A lamp in white mode reports no colour and can still be given one.
          enabled: widget.enabled && !_busy(control),
          brightness: _brightnessFraction(),
          onSend: (payload) => widget.onSend(control, payload),
        ),
    ]);
  }
}

/// The hue wheel of a colour control. Touching the wheel only moves a draft,
/// shown in the swatch beside the button; "Apply" sends it once, in [format],
/// at the brightness of the reading read in [readingFormat]. The wheel takes
/// a drag that starts on it, so it is kept small enough to leave room to scroll.
class ColourWheel extends StatefulWidget {
  final dynamic value;
  final ColourFormat format;

  /// The layout of the colour reading [value]; null when unknown.
  final ColourFormat? readingFormat;
  final bool enabled;
  final Future<void> Function(dynamic payload) onSend;

  /// The lamp's brightness (0..1) for a payload while it reports no colour.
  final double? brightness;

  const ColourWheel(
      {required this.value,
      required this.format,
      required this.enabled,
      required this.onSend,
      this.readingFormat,
      this.brightness,
      super.key});

  @override
  State<ColourWheel> createState() => _ColourWheelState();
}

/// The side of the colour wheel's square.
const colourWheelSize = 200.0;

class _ColourWheelState extends State<ColourWheel> {
  /// Hue and saturation chosen and not yet sent.
  HSVColor? _draft;
  bool _sending = false;

  HSVColor get _shown {
    final hs = hueSaturationOf(widget.value);
    return _draft ?? HSVColor.fromAHSV(1, hs?.hue ?? 0, hs?.saturation ?? 0, 1);
  }

  Future<void> _apply() async {
    final draft = _draft;
    if (draft == null || !widget.enabled || _sending) return;
    final current = widget.readingFormat == null ? null : colourBrightnessOf(widget.value, widget.readingFormat!);
    setState(() => _sending = true);
    try {
      await widget.onSend(colourPayload(draft.hue, draft.saturation, widget.format, brightness: current ?? widget.brightness));
    } finally {
      if (mounted) {
        setState(() {
          _draft = null;
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canApply = widget.enabled && !_sending && _draft != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
          dimension: colourWheelSize,
          child: IgnorePointer(
            ignoring: !widget.enabled || _sending,
            child: Opacity(
              opacity: widget.enabled ? 1 : .5,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ColorPickerArea(_shown, (c) => setState(() => _draft = c), PaletteType.hueWheel),
              ),
            ),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            key: const Key('colourDraftSwatch'),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _shown.toColor(),
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(width: Spacing.md),
          FilledButton.tonal(
            key: const Key('colourApply'),
            onPressed: canApply ? _apply : null,
            child: const Text('Apply'),
          ),
        ]),
      ]),
    );
  }
}

/// The Climate card: the measured temperature large, the heating state as a
/// chip, and the setpoint with minus and plus.
class ClimateCard extends StatelessWidget {
  final ClimateCardModel model;
  final List<DeviceState> states;
  final bool isGroup;
  final bool enabled;
  final String setpointTitle;
  final SendControl onSend;

  /// Opens the history of the measured value; null for a group.
  final VoidCallback? onOpenMeasured;

  const ClimateCard({
    required this.model,
    required this.states,
    required this.isGroup,
    required this.enabled,
    required this.setpointTitle,
    required this.onSend,
    this.onOpenMeasured,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final measured = model.measured;
    final running = model.heating.where((s) => binaryRoleOf(s, states, isGroup: isGroup) == BinaryRole.heatingRunning).firstOrNull;
    final enabledState = model.heating.where((s) => binaryRoleOf(s, states, isGroup: isGroup) == BinaryRole.heatingEnabled).firstOrNull;
    final chip = climateChipText(running: running?.value, enabled: enabledState?.value);
    final heating = chip == 'Heating';
    final start = inlineStartValue(model.control, states, isGroup: isGroup)?.value;
    final spec = climateSetpointSpec(model.control);
    final busy = model.setpoint.transitioning;

    final Widget value;
    if (measured == null) {
      value = const SizedBox.shrink();
    } else if (measured.transitioning) {
      value = const SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: DelayedCircularProgressIndicator()));
    } else {
      value = Text(formatValueWithUnit(measured.value, readingUnit(measured.functionId)),
          key: const Key('climateMeasured'), style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (measured != null || chip != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: InkWell(
                onTap: measured != null && measured.value is num ? onOpenMeasured : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (measured != null) Text(detailLabel(measured, [measured], null).title, style: theme.textTheme.bodyMedium),
                  value,
                ]),
              ),
            ),
            if (chip != null)
              Chip(
                key: const Key('climateChip'),
                avatar: heating ? Icon(Icons.local_fire_department, size: 18, color: theme.colorScheme.error) : null,
                label: Text(chip),
              ),
          ]),
        ),
      if (spec != null)
        InlineControl(
          spec: spec,
          value: start,
          unit: controlUnit(model.control),
          busy: busy,
          enabled: enabled && start is num,
          onSend: (v) => onSend(model.control, v),
          tile: (trailing) => ListTile(title: Text(setpointTitle), trailing: trailing),
        ),
    ]);
  }
}
