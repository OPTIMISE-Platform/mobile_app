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

import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/config/functions/light_functions.dart';
import 'package:mobile_app/live/conversion/casts.dart' show Characteristics;
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/shared/characteristic_conversion.dart';
import 'package:mobile_app/shared/colour_value.dart';
import 'package:mobile_app/shared/device_controls.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_labels.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

/// Controls the detail page offers in the row itself instead of the dialog.
/// What none of them fits (structures, text, a start value that is no number)
/// keeps the dialog button.
enum InlineControlKind { slider, stepper, choice, dropdown }

/// A segmented button holds at most this many values, a dropdown more.
const inlineChoiceLimit = 4;

/// The stepper sends this long after its last tap.
const inlineControlDebounce = Duration(milliseconds: 800);

class InlineControlSpec {
  final InlineControlKind kind;
  final bool integer;

  /// Both set for a slider; a stepper holds to those that exist.
  final double? min, max;

  /// The values of a choice or dropdown, as the characteristic lists them.
  final List<dynamic> options;

  /// A slider whose track is a gradient (colour temperature), left to right.
  final List<Color>? gradient;

  /// How a slider shows its value when that is not the number itself.
  final String Function(num value)? display;

  const InlineControlSpec(this.kind,
      {this.integer = false, this.min, this.max, this.options = const [], this.gradient, this.display});

  double get step => integer ? 1 : 0.5;
}

/// The characteristic of [control]'s function config, the one the dialog works
/// in and a command of it is sent in; null when there is none.
Characteristic? controlCharacteristic(DeviceState control) {
  try {
    return configCharacteristic(control.functionId);
  } catch (_) {
    // A config without a base characteristic of its concept.
    return null;
  }
}

/// The unit an inline control of [control] shows its value in.
String controlUnit(DeviceState control) => controlCharacteristic(control)?.display_unit ?? '';

/// The value an inline control of [control] starts from: [controlStartValue],
/// which is in the reading's characteristic ([readingCharacteristicId]),
/// converted into [controlCharacteristic], since a step or a slider position
/// is sent in that. Null (not wrapped) when there is no conversion; the row
/// then keeps the dialog. A missing start value is `(value: null)`.
({dynamic value})? inlineStartValue(DeviceState control, List<DeviceState> states, {required bool isGroup}) {
  final start = controlStartValue(control, states, isGroup: isGroup);
  if (start == null) return (value: null);
  final readings = readingsOfControl(control, states, isGroup: isGroup);
  // controlStartValue has a value only for exactly one reading.
  if (readings.length != 1) return (value: null);
  final reading = readings.single;
  final from = readingCharacteristicId(reading.functionId);
  final to = controlCharacteristic(control)?.id;
  if (from == null || to == null) return null;
  final functions = AppState().platformFunctions;
  return convertCharacteristic(start, from, to,
      conceptIds: [functions[reading.functionId]?.concept_id, functions[control.functionId]?.concept_id]);
}

const _celsiusIds = {Characteristics.celsius, 'urn:infai:ses:characteristic:a49a48fc-3a2c-4149-ac7f-1a5482d4c6e1'};

bool _isCelsiusOrFahrenheit(Characteristic c) {
  if (_celsiusIds.contains(c.id)) return true;
  final unit = c.display_unit.replaceAll(' ', '');
  return unit == '°C' || unit == '°F' || c.name.toLowerCase().contains('fahrenheit');
}

/// Whether [c] is a temperature: Celsius or Fahrenheit, or Kelvin when the
/// concept of [functionId] also lists one of those, which a colour temperature
/// in Kelvin does not.
bool isTemperatureCharacteristic(Characteristic c, String functionId) {
  if (_isCelsiusOrFahrenheit(c)) return true;
  if (c.id != Characteristics.kelvin) return false;
  final concept = AppState().concepts[AppState().platformFunctions[functionId]?.concept_id];
  return concept?.characteristics.any(_isCelsiusOrFahrenheit) ?? false;
}

/// The inline control for [control], or null for the dialog. [start] is
/// [inlineStartValue]'s value, in the characteristic the dialog works in (the
/// control function's config), so the value sent is the one the dialog would
/// send; the slider range is [controlRange]. [reading] is the row's reading.
///
/// A number without a range gets minus and plus only for a temperature or a
/// setpoint (aspect Target), where small steps from the current value are what
/// one wants; any other such number keeps the dialog.
InlineControlSpec? inlineControlSpec(DeviceState control, dynamic start, {DeviceState? reading}) {
  final c = controlCharacteristic(control);
  if (c == null) return null;
  final integer = c.type == ContentVariable.integer;
  final numeric = integer || c.type == ContentVariable.float;
  if (control.functionId == setColourTemperatureFunctionId && numeric) {
    return start is num ? colourTemperatureSpec(c) : null;
  }
  final options = c.allowed_values ?? const [];
  if (numeric) {
    final range = controlRange(control);
    if (range != null) {
      return start is num ? InlineControlSpec(InlineControlKind.slider, integer: integer, min: range.min, max: range.max) : null;
    }
  }
  if (options.isNotEmpty && (numeric || c.type == ContentVariable.string)) {
    return InlineControlSpec(options.length <= inlineChoiceLimit ? InlineControlKind.choice : InlineControlKind.dropdown,
        integer: integer, options: options);
  }
  final setpoint = hasAspectNamed(control, 'target') || (reading != null && hasAspectNamed(reading, 'target'));
  if (numeric && start is num && (setpoint || isTemperatureCharacteristic(c, control.functionId))) {
    final min = c.min_value, max = c.max_value;
    return InlineControlSpec(InlineControlKind.stepper,
        integer: integer, min: min != null && min.isFinite ? min : null, max: max != null && max.isFinite ? max : null);
  }
  return null;
}

/// The warm-to-cold slider of colour temperature in the characteristic [c]: its
/// own range when it has one, else 2000 to 6500 K (153 to 500 mired). The value
/// stays in [c], so what is sent is what the dialog would send; mired is
/// shown as Kelvin and its track runs cold to warm, as the numbers do.
InlineControlSpec colourTemperatureSpec(Characteristic c) {
  final mired = c.id == miredCharacteristicId;
  final fallback = mired ? colourTemperatureMiredRange : colourTemperatureKelvinRange;
  var min = c.min_value, max = c.max_value;
  if (min == null || max == null || !min.isFinite || !max.isFinite || max <= min) (min, max) = fallback;
  double kelvinAt(double v) => mired ? 1e6 / v : v;
  final lo = kelvinAt(min), hi = kelvinAt(max);
  final colours = [for (var i = 0; i <= 4; i++) kelvinToColour(lo + (hi - lo) * i / 4)];
  return InlineControlSpec(InlineControlKind.slider,
      integer: c.type == ContentVariable.integer,
      min: min,
      max: max,
      gradient: colours,
      display: (v) => '${kelvinAt(v.toDouble()).round()} K');
}

/// A slider track painted as a gradient; the value shows on the thumb alone.
class _GradientTrackShape extends RoundedRectSliderTrackShape {
  final List<Color> colors;

  const _GradientTrackShape(this.colors);

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
        parentBox: parentBox, offset: offset, sliderTheme: sliderTheme, isEnabled: isEnabled, isDiscrete: isDiscrete);
    final paint = Paint()..shader = LinearGradient(colors: colors).createShader(rect);
    if (!isEnabled) paint.color = paint.color.withValues(alpha: .4);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    context.canvas.drawRRect(shape, paint);
    // The cold end is near white, which would vanish on a light card.
    context.canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black26);
  }
}

/// The row of a control that is set in place. [value] is the reading it starts
/// from and falls back to; [onSend] runs the command and completes after the
/// read-back.
///
/// Commands are not idempotent: a slider sends once on release, a stepper once
/// per [inlineControlDebounce] window, a choice on selection. While the row is
/// [busy] the control is disabled; a change that gets there anyway is dropped
/// and the control shows the reading again.
///
/// A [compact] stepper is a bare row for a sensor card: [label] and the value,
/// then minus and plus. It shows a value not yet read back muted instead of
/// a spinner.
class InlineControl extends StatefulWidget {
  final InlineControlSpec spec;
  final dynamic value;
  final String unit;
  final bool busy;
  final bool enabled;
  final Future<void> Function(dynamic value) onSend;

  /// The row's list tile around [trailing]; unused when [compact].
  final ListTile Function(Widget? trailing)? tile;

  final bool compact;

  /// Before the value of a [compact] stepper, such as "Target".
  final String? label;

  /// The value's style in a [compact] stepper.
  final TextStyle? valueStyle;

  const InlineControl({
    required this.spec,
    required this.value,
    required this.unit,
    required this.busy,
    required this.enabled,
    required this.onSend,
    this.tile,
    this.compact = false,
    this.label,
    this.valueStyle,
    super.key,
  }) : assert(compact || tile != null);

  @override
  State<InlineControl> createState() => _InlineControlState();
}

class _InlineControlState extends State<InlineControl> {
  Timer? _timer;

  /// What the user chose and has not been read back yet.
  dynamic _draft;
  bool _sending = false;

  bool get _active => widget.enabled && !widget.busy;

  /// The draft while it is ours (not left over from a refresh), else the reading.
  dynamic get _shown => _draft != null && (!widget.busy || _sending) ? _draft : widget.value;

  @override
  void dispose() {
    final pending = _timer?.isActive == true ? _draft : null;
    _timer?.cancel();
    // A stepper change still inside its window is sent, not lost, when the row
    // goes away (the page closes); a busy or disabled row drops it as [_send] does.
    // Sent after the frame: the send notifies listeners, which is not allowed
    // while the tree is locked.
    if (pending != null && _active) {
      final send = widget.onSend;
      scheduleMicrotask(() => unawaited(send(pending)));
    }
    super.dispose();
  }

  Future<void> _send(dynamic value) async {
    _timer?.cancel();
    if (!_active) {
      setState(() => _draft = null);
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(value);
    } finally {
      if (mounted) {
        setState(() {
          _draft = null;
          _sending = false;
        });
      }
    }
  }

  num _clamp(num v) {
    final spec = widget.spec;
    if (spec.min != null && v < spec.min!) v = spec.min!;
    if (spec.max != null && v > spec.max!) v = spec.max!;
    return v;
  }

  /// [next] held to the bounds a step from [base] crosses. A [base] outside
  /// them (a value the device took from elsewhere) moves by the step towards
  /// them instead of jumping onto the bound.
  num _clampFrom(num base, num next) {
    final spec = widget.spec;
    if (spec.max != null && next > spec.max! && base <= spec.max!) return spec.max!;
    if (spec.min != null && next < spec.min! && base >= spec.min!) return spec.min!;
    return next;
  }

  void _step(int direction) {
    final spec = widget.spec;
    final base = _shown;
    if (base is! num) return;
    // A value off the step grid (a converted reading) first goes to the next
    // multiple of the step in the direction; rounded so repeated half steps do
    // not collect binary noise.
    final ratio = base / spec.step;
    final onGrid = (ratio - ratio.round()).abs() < 1e-6;
    final target = onGrid ? base + direction * spec.step : (direction > 0 ? ratio.floor() + 1 : ratio.floor()) * spec.step;
    final next = _clampFrom(base, double.parse(target.toStringAsFixed(4)));
    setState(() => _draft = spec.integer ? next.round() : next.toDouble());
    _timer?.cancel();
    _timer = Timer(inlineControlDebounce, () {
      final draft = _draft;
      if (draft != null && mounted) _send(draft);
    });
  }

  Widget get _spinner => const SizedBox.square(dimension: 24, child: DelayedCircularProgressIndicator());

  /// A [InlineControl.compact] stepper.
  Widget _compactStepper(bool atMin, bool atMax) {
    final theme = Theme.of(context);
    // Chosen and not read back yet: still in its window, or being sent.
    final pending = _draft != null && (!widget.busy || _sending);
    final style = (widget.valueStyle ?? theme.textTheme.titleMedium)
        ?.copyWith(color: pending ? theme.colorScheme.onSurfaceVariant : null, fontStyle: pending ? FontStyle.italic : null);
    final label = widget.label;
    Widget button(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
          tooltip: tooltip,
          icon: Icon(icon),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onPressed: onPressed,
        );
    // Takes the taps on the row, so one on a disabled button at a bound does
    // not reach the card around it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: widget.busy && !pending
              ? _spinner
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(children: [
                      if (label != null) TextSpan(text: '$label ', style: theme.textTheme.bodySmall),
                      TextSpan(text: formatValueWithUnit(_shown, widget.unit), style: style),
                    ]),
                    key: const Key('stepperValue'),
                    maxLines: 1,
                  ),
                ),
        ),
        button(Icons.remove, 'Decrease', _active && !atMin ? () => _step(-1) : null),
        button(Icons.add, 'Increase', _active && !atMax ? () => _step(1) : null),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final tile = widget.tile ?? (Widget? trailing) => ListTile(trailing: trailing);
    switch (spec.kind) {
      case InlineControlKind.slider:
        final shown = _shown;
        final value = shown is num ? _clamp(shown).toDouble() : spec.min!;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          tile(widget.busy ? _spinner : null),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 16),
            child: Row(children: [
              Expanded(
                child: SliderTheme(
                  data: spec.gradient == null
                      ? SliderTheme.of(context)
                      : SliderTheme.of(context).copyWith(trackShape: _GradientTrackShape(spec.gradient!), trackHeight: 8),
                  child: Slider(
                    value: value,
                    min: spec.min!,
                    max: spec.max!,
                    onChanged: _active
                        ? (v) => setState(() => _draft = spec.integer ? v.round() : v)
                        : null,
                    onChangeEnd: _active ? (v) => _send(spec.integer ? v.round() : v) : null,
                  ),
                ),
              ),
              Text(shown is num && spec.display != null ? spec.display!(shown) : formatValueWithUnit(shown, widget.unit),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
        ]);
      case InlineControlKind.stepper:
        final shown = _shown;
        final atMin = shown is num && spec.min != null && shown <= spec.min!;
        final atMax = shown is num && spec.max != null && shown >= spec.max!;
        if (widget.compact) return _compactStepper(atMin, atMax);
        return tile(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Decrease',
            icon: const Icon(Icons.remove),
            onPressed: _active && !atMin ? () => _step(-1) : null,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: Center(
              child: widget.busy
                  ? _spinner
                  : Text(formatValueWithUnit(shown, widget.unit), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          IconButton(
            tooltip: 'Increase',
            icon: const Icon(Icons.add),
            onPressed: _active && !atMax ? () => _step(1) : null,
          ),
        ]));
      case InlineControlKind.choice:
        final selected = spec.options.indexWhere((o) => o == _shown);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          tile(widget.busy ? _spinner : null),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                emptySelectionAllowed: true,
                segments: [
                  for (var i = 0; i < spec.options.length; i++)
                    ButtonSegment(
                        value: i, label: Text(formatValue(spec.options[i]), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                selected: selected < 0 ? <int>{} : {selected},
                onSelectionChanged: _active
                    ? (s) {
                        if (s.isEmpty) return;
                        setState(() => _draft = spec.options[s.first]);
                        _send(spec.options[s.first]);
                      }
                    : null,
              ),
            ),
          ),
        ]);
      case InlineControlKind.dropdown:
        final selected = spec.options.indexWhere((o) => o == _shown);
        return tile(widget.busy
            ? _spinner
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .5 - 12),
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: selected < 0 ? null : selected,
                  hint: const Text('-'),
                  items: [
                    for (var i = 0; i < spec.options.length; i++)
                      DropdownMenuItem(value: i, child: Text(formatValue(spec.options[i]), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _active
                      ? (i) {
                          // Picking the shown value again is no change to send.
                          if (i == null || i == selected) return;
                          setState(() => _draft = spec.options[i]);
                          _send(spec.options[i]);
                        }
                      : null,
                ),
              ));
    }
  }
}
