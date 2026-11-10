# Device commands

How a batch of device commands is split between paired gateways and the
platform, when a command is handed from one to the other, and what a caller
gets back for each command.

## Scope

Covers `lib/services/device_commands.dart`: `DeviceCommandsService`, the
gateway path `DeviceCommandPath` with its endpoint cache, and the platform
path `DeviceCommandCloud`. Not about what a command carries (the aspect fields
are in `docs/aspect-lists.md`), and not about how gateways are paired and
probed; that is `NetworkMixin`, which fills `Network.localGateways`.

## One batch per network

`DeviceCommandsService.runCommands` groups the commands by the network of
their device or group. A group whose network has a reachable gateway goes to
that gateway's device-command module, every other group goes to the platform.
All groups are sent at once.

The gateway is the first stored entry in `Network.localGateways`, not an
address: each pairing has its own credentials and session, and two entries can
share an address in different networks. Only the entry whose own network
answered the status check is listed there.

The result holds one `DeviceCommandResponse` per command, at the command's
index, always. A command with neither device nor group, and a command its
batch did not answer, comes back as 502 `upstream reply null`.

## The gateway is tried first

`DeviceCommandPath` reads the module's endpoint from the Isar `endpoints`
collection and asks the gateway's core-manager only when none is cached. Rows
are kept per pairing id and module, so each gateway has its own; rows cached
without a pairing id are never read. Any failed gateway request drops that
gateway's cached endpoint, so the next command looks the module up again in
case it has moved.

A command leaves the gateway path in three ways:

- **513 for a command**: the gateway does not serve that device. The command
  joins the platform batch.
- **The gateway took the batch but did not answer in time** (receive
  timeout): the gateway may still run the batch. A control (function id
  under `controllingFunctionPrefix`) is 502
  `gateway took the command but did not answer` and stays there, because
  running it twice is the harm. A read is idempotent and joins the platform
  batch like a 513.
- **Any other failure**: endpoint lookup, connect, send, or an error status.
  The whole group joins the platform batch. The app cannot tell a connection
  dropped after the body was sent, or an error status after a partial run,
  from a gateway that never took the batch, so those two can still run a
  command twice.

The commands collected that way go to the platform in one batch after the
gateway round.

## A platform answer is final

Commands are not idempotent, so a platform batch is never repeated. Its
answers are written as they come, 513 included. A platform request that fails
with a `DioException` answers 502 for each command; the message is
`ErrorReporter.offlineMessage` when the platform could not be reached, which
includes the availability interceptor's rejection in local mode and while the
platform is marked unreachable (`docs/platform-outage.md`), else
`platform answered <status>`.

Any other error from the platform path, such as a reply that is not a list,
propagates out of `runCommands`.

## Answers as they arrive

`runCommands` takes an optional `onAnswers` handler. It gets every index
exactly once, as soon as its answer is final: a gateway answer when the
gateway batch returns, before the platform round, a platform answer when its
batch returns, and the 502 of an unanswered command right before
`runCommands` returns. The first answer for an index is the one returned. A
handler that throws is logged and changes nothing that is sent. When
`runCommands` throws, the answers already passed stand.

## Gateway without the module

A gateway without the `mgw-device-command` module fails the endpoint lookup,
so every read goes to the platform and is missing while the platform is
unreachable (`docs/platform-outage.md`). Device Command also needs
`mgw-last-value-module`; without it, it returns no values for event services.

`MgwStatusPanel` (`lib/widgets/tabs/gateways/mgw_status_panel.dart`) reads the
gateway's module list once its status is ok and shows a notice when Device
Command is missing, or when only Last Value is. It reads the list again on
"Check again". A list that cannot be read shows no notice and no toast; only
`ErrorReporter.log`. The panel is the gateway page and the status sheet of a
network row; the gateway list asks for nothing per row.

## Time of the last message

An answer may carry `time` (RFC 3339), set by device-command only when the
value came from the stored last values; a live device answer and a group
command carry none. `loadStates` puts it on the reading as
`DeviceState.lastMessageTime`; a successful answer of a pure request service
without `time` was just sent by the device and gets the time of the answer.
Writing a value drops its time. Other readings with a value that still have
no time after the load are asked from the platform in one `POST /db/v3/last-values`
(`DbQueryService.lastValues`), after the values are shown and not awaited by
`loadStates`, and skipped while platform calls are off
(`docs/platform-outage.md`). One unknown column fails that whole request with
400 (real device types have them, e.g. a flat output named `value`), so a 400
is followed by one request per reading, at most four at a time; a column
refused on its own is left out until the app restarts. Other errors are only
logged. A time never changes a value or a status.
The detail page and the sensor cards show it (`StateTimeCaption`); a group
shows none.

## Timeouts

The batch endpoint waits up to 10 s for the devices (`commandTimeoutSeconds`,
sent as `timeout=10s`), and both batch requests wait a second longer than
that (`batchReceiveTimeout`), so device-command's own timeout answer arrives
instead of a client-side 502 for a slow device. Every other request of the
two clients keeps its 5 s.

`prefer_event_value` is on by default, so device-command answers a reading
from the last event it saw when the service offers both events and requests.
The read-back after a control command passes `preferEventValue = false` to get
a fresh value from the device.

## What callers see

- `runCommandsSecurely` wraps `runCommands` for the widgets: an exception is
  reported through `ErrorReporter` and the call returns false; a 502 is an
  ordinary response, which the widgets toast as
  `Error running command: <message>`.
- `loadStates` (`lib/mixins/device_mixin.dart`) hands each answer to its
  state's callback as it arrives and notifies that device or group, a 502 as
  null. It reports only an exception, after which the callbacks not yet
  answered get null. The device list and the sensors page load the devices
  behind a gateway once the gateway has given their connection state, and the
  others once the platform has, each in its own `loadStates`; the sensors
  page shows a device or group no card shows yet before its values.
- `toggleDeviceState` (`lib/widgets/tabs/shared/device_state_action.dart`)
  resolves the control from the reading; `toggleThroughControl` takes one the
  caller resolved (the sensors page's group tiles). Both show a spinner, toast
  a non-200 with the backend message, read the value back and return whether
  that read-back succeeded. The device list, the sensors page and the Android
  widget offer a toggle only where `isSwitchableOnOff`
  (`lib/widgets/tabs/sensors/switch_tile.dart`) finds a control for the
  reading: the binary-state function `FUNCTION_GET_ON_OFF_STATE` names also
  reads motion, contacts and button inputs.
- A group's reading holds one value per device. `DeviceGroup.getStateFillFunctions`
  and the read-back in `performDeviceStateAction` unwrap a one-element list,
  so a group of one device holds that device's value, and a list-typed value
  of such a group cannot be told apart from a list per device. The input
  dialog of `performDeviceStateAction` offers a group the value all its
  devices share (`commonValue` in `lib/config/functions/function_config.dart`,
  none when they differ) and leaves list-typed values as they are. The
  configs in `functionConfigs` are shared instances that outlive a dialog, so
  `FunctionConfig.build` sets the start value on every call, `null`
  included; otherwise a dialog would open with the input of the one before.
  The start value is converted from the reading's characteristic into the
  one the dialog works in; without a conversion the dialog starts empty, since
  the number would otherwise be sent in the wrong unit.
- The Android device controls (`lib/native_pipe.dart`) answer a command with
  its responses and the entry as it now is; see below.

Both paths are driven through `FakeBackend` in
`test/device_commands_cloud_fallback_test.dart`; the gateway is served at
`gw.test`.

## Inline controls on the detail page

A reading merged with its control is set in the row when the control's
characteristic allows (`lib/widgets/tabs/shared/detail_page/inline_control.dart`),
else the row keeps the dialog button. Which control follows the characteristic
of the control's function config, the one the dialog works in:

- on/off reading with its controls: `Switch`, toggles through the control as before;
- number with a finite minimum and maximum (`controlRange`): `Slider`, sends on
  release;
- temperature (Celsius, Fahrenheit, Kelvin of a concept that also lists one
  of those) or setpoint (aspect Target) without a range: minus/plus buttons,
  step 1 for an integer and 0.5 for a float, held to the bounds it has, sends
  800 ms after the last tap; any other number without a range keeps the
  dialog button with its value;
- allowed values: `SegmentedButton` up to four, else a dropdown, sends on
  selection; picking the shown value again sends nothing;
- anything else, or a number with no start value: the dialog.

The start value is `inlineStartValue`: `controlStartValue` (the one paired
reading's value, a group's the value all devices share, none when they differ)
converted from the reading's characteristic (its function's preferred one,
else the concept's base) into the control's (`configCharacteristic`), with
`LocalConverter` and the concepts' formulas. A reading shown in °F and a
control in °C steps from the °C value, shown in °C. Without a conversion path
the row keeps the dialog. The value goes through
`performDeviceStateAction(value: ...)`, so the command, the read-back and the
error toast are the dialog's, and the payload has the type the dialog's field
produces.

Commands are not idempotent, so a change is sent once and never queued. While a
reading the control acts on is transitioning the control is disabled; a stepper
change whose window ends then, or an action that finds such a reading, is
dropped and the control shows the reading again. A refresh in the middle of a
window drops the pending change the same way. A stepper change still inside its
window when the row goes away (the page is closed) is sent then, once, unless
the row is busy or disabled.

## Cards on the detail page

`lib/widgets/tabs/shared/detail_page/control_cards.dart` puts states that belong
together in one card at the top of the Control section; the rows a card covers
are not repeated. Both use the inline controls above and send through the same
`performDeviceStateAction(value: ...)`.

- **Light card**, when there is exactly one control of a kind for Set-Brightness,
  Set-Color Temperature (`light_functions.dart`) or Set-Color, each with a
  reading to show: the on/off switch, a brightness slider, a colour temperature
  slider on a warm-to-cold gradient, and a colour wheel that opens on tap. A
  kind that does not fit stays a row with its dialog, as does a group's kind
  whose members disagree and a brightness or colour temperature without a
  start value (`inlineStartValue`, also when it cannot be converted). An on/off
  reading whose value is not on or off stays a row with its Set On/Off rows,
  as an unknown switch does elsewhere. While a reading is loading the card
  keeps it, with its control disabled.
- **Climate card**, for a reading with the aspect Target that a numeric control
  sets and that has a start value: the measured temperature (same function,
  aspect Reading, else the first without Target) large, the read-only heating states as a chip, the setpoint
  with minus/plus in 0.5 steps (1 for whole numbers), 5 to 30 for a Celsius
  characteristic without a maximum (`thermostatSetpointRange`).

Colour temperature is a slider wherever it is set, in a card or in a row:
the characteristic's own range, else 2000 to 6500 K (153 to 500 mired). The
value stays in the control's characteristic and is sent as the dialog would.

Colours (`lib/shared/colour_value.dart`): the layout comes from the
characteristic, h/s/b, r/g/b or the hex characteristic (`colourFormatOf`); a
control or reading in another layout stays a row. The swatch is `colourOf` of
the reading: hue and saturation at full value, since brightness is its own
control. Touching the wheel only moves a draft, shown next to the "Apply"
button; Apply sends it once in the control's layout (`colourPayload`). The
lamp's brightness is read from the reading in the reading's own layout
(`colourBrightnessOf`: b over its scale, or the HSV value of r/g/b and hex) and
put on the control's scale. A lamp in white mode reports no colour; then the
brightness reading, converted into the brightness control's range, stands in,
else full brightness. Example for a control "HS + Brightness (0-254)": the
reading `{h: 30, s: 100, b: 77}` on the same scale shows #FF8000, and hue 120
at half saturation sends `{h: 120, s: 50, b: 77}`; a reading on 0..100 with
`b: 50` sends `b: 127`. The wheel takes any drag that starts on it, so it is
kept at 200 px to leave room to scroll.

## Android device controls

`lib/native_pipe.dart` serves the Android controls (`ControlsProviderService`,
`AppControlsProviderService.kt`) over the `flutter/controlMethodChannel`. It
offers three kinds of control: the on/off reading of a device, that of a group,
and a reading that exactly one control sets within a numeric range (a slider).
The derivation, free of I/O, is in `lib/shared/device_controls.dart`: a device
pairs reading and control as the detail page does, a group by
`resolveGroupControl`, and the range comes from the characteristic of the
control's function when it is a float or integer with a minimum and a maximum
(step 1 for an integer, 0.5 for a float). `RangeTemplate` refuses a value
outside the range and a step of zero, so a characteristic that does not fit is
not offered, and the Kotlin side holds the value to the range.

- **Routing.** A command is built from the states of the device or group read
  from Isar and prepared there, never from the JSON the platform side sends:
  only those states carry `deviceInstance` or `deviceGroup`, which is what
  `runCommands` takes the network and so the gateway from. A group is read
  after the networks are loaded, because it takes its network when it is
  constructed. In the app's engine the pipe loads the networks first if there
  are none; the metadata comes from the cache, the function configs are built
  again after a load.
- **Own engine.** With the app closed the service starts an engine with the
  entrypoint `controlsMain` (`lib/main.dart`), not `main`: dotenv, Settings,
  Isar, `Auth().init()`, the metadata and the networks from the cache, no
  Firebase and no cache refresh, no view. The handler is set at once and holds
  each call until that is done; a failed start is tried again by the next call.
  What is loaded is read from the cache; a fetch happens for what it lacks. The
  Hive boxes are opened as the app opens them. Setting `Auth().init()` up writes
  the account to `settings.box` (`Settings.setAccount`), and constructing
  `AppState` starts the gateway discovery, which stores a moved address in
  `mgw.box`; the engine runs no other Hive write of its own.
- **One engine at a time.** Service and app run in one process, and Hive's
  file lock does not separate two Dart isolates in it: each would keep its own
  copy of a box, read the other's changes only after a restart, and after a
  compaction by one write into the replaced file. So when the app's engine
  attaches the plugin (`MainActivity`), the service destroys its own engine and
  answers through the app's from then on. A call running in the destroyed
  engine fails, and the open controls panel gets no more updates until it is
  opened again. With the app closed again the next call starts a new engine.
- **Thermostats.** Temperature characteristics have no maximum on the
  platform (Degree Celsius: minimum -273.15, no maximum), so a setpoint gets no
  range of its own. A device of the class Thermostat
  (`thermostatDeviceClass` in `lib/shared/device_controls.dart`), or a group
  whose criteria name that class only, takes 5 to 30 °C (278.15 to 303.15 K)
  for the control of the aspect Target (`targetAspect`). The range is a
  constant of the app, not read from the device. A thermostat's other
  temperature controls, such as the Aqara SRTS-A01's external temperature
  input that pairs with its room temperature, get no slider, nor do other
  devices with the same function and characteristic, such as a boiler's water
  temperature. A group pairs a reading with its
  control by aspect as the detail page does; a thermostat group has a
  set-temperature control per aspect. Only when that finds none does the
  group's single control of the function count.
- **Stable ids.** Android stores the id of every control a user added, the
  fields of `DeviceState` without value, `isControlling` and `transitioning`
  (`DeviceState.getId()` in Kotlin). The fields that describe a control (`kind`,
  `min`, `max`, `step`, `unit`, `integer`) are removed from the id as well, and
  an on/off entry of a device carries the same id fields as before.
  `test/device_controls_test.dart` compares them against the payload from
  before. The answer to `getToggleStates` and to a command repeats the id
  fields of the request unchanged.
- **Setting a value.** `setValue` finds the reading and the control as above,
  sends the control's command with the value held to the range (rounded for an
  integer) and reads the reading back; when that fails the value that was set
  stands in. `setToggle` sends the control of the new state and answers with
  that state, as no reading has caught up. For a group an on/off control exists
  only when there is one control for each direction.
- **Updates.** `handleDeviceStateUpdate` passes a changed reading of a device on
  as an event only when the platform side shows a control for it, that is when
  `getToggleStates` was asked for that reading in this process (device id,
  service, function, first aspect). Every reading the app loads or receives
  live passes this hook, the device list's on/off readings of all devices
  included, so the others return before any lookup. Groups send no events.
- **Detail page.** A control of a group puts the group id in the intent extra
  `org.infai.optimise.mobile_app.GroupDetailPage`; `openDetailPage` takes a
  device id or `{groupId: ...}`.

`test/native_pipe_controls_test.dart` (`isar` tag) drives the channel against a
group and a device behind a gateway and checks that the commands go to the
gateway with the group or device id.
