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
aspect names (`joinAspectNames`).

## Finding the controlling state

`DeviceState.controlsFor` pairs a reading with its controls through
`matchAspects`, in three tiers:

1. controls with the same aspect set (all of them, so two still report "more
   than one controlling service");
2. otherwise the one control whose non-empty set is a subset of the reading's;
3. otherwise the first control with the same first aspect, which is what the
   app picked before aspect lists.

A reading without aspects pairs only with a control without aspects. The
detail page's timestamp lookup uses the same tiers.

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
  first; without one it uses only the tier-3 rule.
- **Device groups cached by an earlier version** have criteria without
  `aspect_ids`. While the Settings marker `device_groups_cached_with_aspect_lists`
  is unset, groups served from the cache carry
  `criteriaMayPredateAspectLists`, the group refresh runs at the next start, and
  the marker is set after it succeeds. A flagged group is fetched fresh before
  `saveDeviceGroup` writes it, a favourite tap on it updates only `favorite` in
  Isar, and its pins are not upgraded. The groups in memory are not replaced by
  the refresh; open pages keep their objects for the session.
