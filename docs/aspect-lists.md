# Aspect lists

How the app handles content variables, group criteria and commands that name
their aspects as a list, and what it does with entries stored before that.

## Scope

Covers `lib/models/aspect_ids.dart`, the aspect parts of `DeviceState`,
`ContentVariable`, `DeviceGroupCriteria`, `DeviceCommand` and `SensorPin`, the
control lookup in `lib/widgets/tabs/shared/device_state_action.dart` and
`NativePipe.controlsForToggle`, and the handling of groups cached before the
lists in `lib/services/device_groups.dart` and `lib/services/cache_helper.dart`.
Not about how the platform evaluates the lists; that is backend behaviour.

## One aspect set per state

The backend sends `aspect_ids` and keeps the deprecated `aspect_id` as the
alphabetically first entry. `effectiveAspectIds(aspect_id, aspect_ids)` is the
single place that folds the two: the list if non-empty, else the single id,
sorted. `DeviceState.aspectIds` holds that list, `aspectId` is its first entry,
`aspectKey` identifies the set.

States are de-duplicated by `aspectKey`, not by the first aspect: outputs
`[air, inside]` and `[air, outside]` are two states. Row keys in the sensor
picker and the detail page use `aspectKey` for the same reason. The sensor
cards label a state with all aspect names (`joinAspectNames`). A group row
without aspects is labelled with the device class its criterion names
(`aspectsLabel`): device-repository gives a controlling function a device-class
criterion next to its aspect criteria.

## Detail page rows

The detail page (`detail_labels.dart`) shows rows with a control, a reading
merged with its control or a control alone, under "Control", and read-only
readings under "Readings". A read-only on/off reading is text ("On", "Off",
"Heat"); an on/off reading with its controls is a switch. How a control is set
in the row: `docs/device-commands.md`.

A title is the function's display name without a leading "Get-" or "Set-". An
on/off reading is titled by its role instead, decided by its aspects and in one
table (`binaryTitles`, `binaryRoleOf`):

| Aspects of the reading | Title |
|---|---|
| Button | Button input |
| Heating, characteristic lists "off" (off/heat) | Heating enabled |
| Heating otherwise (idle/heat) | Heating |
| Lighting, or Device on a reading a Set Device On/Off control switches | Power |

Role titles need no subtitle unless another row has the same one. Otherwise,
when another shown state has the same function and another aspect set, the
subtitle names the difference, first match wins:

1. Role aspects: Target turns the title into "Target <title>", Button gives
   "Button input" as subtitle.
2. The aspects this state has that not all states of the function share, minus
   Device: eight energy values over Electricity, Consumption or Generation and
   Phase 1 to 3 or Total give "Consumption, Phase 2".
3. The variable's name from `DeviceState.path`, e.g. "Running state".

States that differ only by service group get the group's name.

## Sensor cards, picker and list rows

The sensors tab and its picker label a reading with `sensorLabel` (the detail
page's `detailLabel`), so titles, roles and disambiguation are the same as on
the detail page. A control of a "Set-" function is "Set" and its title in
sentence case, "Set target temperature", so its card is not named like its
reading's; an input with the role Reading is "External temperature input". The
picker leaves out a control that a listed reading's card sets, and gives a
control's aspects only when another row has the same title. A card with no
alias shows title and subtitle as "Title · Subtitle". Only the label changes: a
pin is found by function, aspects, service group and kind as before. A read-only
on/off reading on a card is its `binaryValueText`, never a power icon; values go
through `formatValueWithUnit`. A switch keeps its tile.

The quick toggle of a device or group row takes icon and tooltip from the
reading's aspects (`toggleIconOf`, `toggleTooltipOf`): Heating gets a flame and
"Heating on/off", Lighting a bulb and "Light on/off", everything else the power
icon and the control's name.

## Group rows

device-repository adds every subset of a variable's aspects, with each aspect
also replaced by its ancestors, as a criterion of its own, so a group of lamps
on `[device, lighting]` also has `[device]` and `[lighting]`. All of them become
states, and pins and Android controls on any of them keep working.
`DeviceGroup.shownStates` drops a state when another one of the same function,
kind and device class is more specific: each of its aspects is one of the
other's or an ancestor of one (`aspectsCover`), and not the other way round.
States without aspects stay, except a control on a device class next to a
control of its function on aspects, since it would act on all of them at once.
The detail page and the sensor picker list only `shownStates`; values are still
loaded for all states, and the detail page pairs and acts over all of them, so
controls on `[device]` and `[lighting]` without one on the combination stay
with their hidden readings and get rows of their own.

## Finding the controlling state

Each control picks its readings, and `DeviceState.controlsFor` returns the
controls that picked a reading. The readings a control C chooses from are the
non-controlling states of its service group whose function relates to C's:
the special function config's `getAllRelatedControllingFunctions`, else the
controlling functions sharing the function's concept. Among them C picks:

1. all readings with the same aspect set as C, so two readings of one relay
   both pair and two controls on one set still report "more than one
   controlling service";
2. otherwise, if C has aspects, the readings with the smallest aspect set
   containing C's, among readings whose set is not that of another control of
   C's function; all of them if they share one set, none if several sets have
   that size;
3. a control without aspects picks only readings without aspects.

A control that picks no reading gets its own row on the detail page. The rule
lives in `DeviceState.controlsAmong` and `pairedReadings`; `controlsFor` (an
extension in `function_config.dart`) binds it to the function configs.

An input with the value role Reading (`isReadingInput`), such as a
thermostat's external temperature input, is never a reading's control: a value
entered there is fed to the device as the room temperature it regulates on.
`controlsFor` leaves it out, and `controlOfReading` gives the reading it picks
no control, not even a group's single one. It still picks that reading, so no
other control of its function takes the measured value, and keeps a row of its
own titled "External temperature input".

The first-aspect rule from before aspect lists, `legacyMatchAspects` (equal
set, else the unique subset, else the first candidate with the same first
aspect), is used only by the detail page's timestamp lookup and the Android
toggle fallback below.

## Commands

`DeviceState.toCommand` sends `aspect_ids` and `aspect_id` (the first).
`aspect_id` stays for local gateways whose device-command predates the list.

## Entries stored before the lists

- **Sensor pins** store `aspectIds` next to `aspectId`. A pin without
  `aspectIds` resolves through `DeviceState.resolveAspects`: the state whose set
  is exactly `[aspectId]`, else the one state containing it, else none. After a
  tab loads, such pins are upgraded in memory (`SensorPin.upgradedIn`) and
  stored with the next change the user makes; edit and remove recognise a pin
  in either form.
- **Android device controls** keep their ids, which carry only the first
  aspect. `NativePipe.controlsForToggle` finds the reading by service and path
  and pairs it through `controlsFor`; without one the entry picks the control
  through `legacyMatchAspects` on its own aspect.
- **Device groups cached by an earlier version** have criteria without
  `aspect_ids`. While the Settings marker `device_groups_cached_with_aspect_lists`
  is unset, groups served from the cache carry
  `criteriaMayPredateAspectLists`, the group refresh runs at the next start, and
  the marker is set after it succeeds. A flagged group is fetched fresh before
  `saveDeviceGroup` writes it, a favourite tap on it updates only `favorite` in
  Isar, and its pins are not upgraded. The groups in memory are not replaced by
  the refresh; open pages keep their objects for the session.
