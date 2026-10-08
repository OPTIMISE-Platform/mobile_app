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
picker and the detail page use `aspectKey` for the same reason. Labels join all
aspect names (`joinAspectNames`). A group row without aspects is labelled with
the device class its criterion names (`aspectsLabel`): device-repository gives
a controlling function a device-class criterion next to its aspect criteria.

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
