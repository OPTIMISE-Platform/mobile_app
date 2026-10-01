# Cache freshness

When the app serves a cached copy, when it refreshes one, and what makes a
screen wait for the backend.

## Scope

Covers the metadata byte cache (`lib/shared/metadata_cache.dart`), the metadata
loaders in `lib/mixins/data_mixin.dart` and `lib/mixins/device_mixin.dart`,
`AppState.init` and its resume handler (`lib/app_state.dart`), the entity
refresh in `lib/services/cache_helper.dart`, and how device classes, the
device index and the class filter (`lib/models/device_search_filter.dart`)
depend on them. Not about the Hive HTTP cache behind
`DioConfig.cached*`, which dio manages on its own, and not about the per-widget
reload on resume (`lib/mixins/resume_refresh_mixin.dart`).

## The rule

Serve what is cached, whatever its age. If it is older than its freshness
limit, refresh it in the background after the first frame and let the open
screens reload. Check that at start and whenever the app returns to the
foreground. Only an empty cache makes a screen wait.

A background refresh (start, resume) that fails keeps what is on screen and is
logged with `ErrorReporter.log`, without a toast: the user still has a list.
The explicit refreshes (login, Settings) still report their failures.

## Limits

| Cache | Limit | Stored in |
|---|---|---|
| Device types, device classes, functions, aspects, concepts, characteristics | `metadataMaxAge`, 7 days | Isar `CachedMetadata` |
| Devices, device groups, networks, locations | `CacheHelper.entityMaxAge`, 1 day | Isar entity collections, refresh time in Settings (`cacheUpdated_*`) |

Device classes (`/device-repository/v2/device-classes`, key `device-classes`)
are every class of the platform. Which of them the user has devices of follows
from the device types (`device_class_id`), and the count per class from the
device index, see "Device classes" below.

A time stamp in the future counts as expired for every cache. It comes from a
clock that ran ahead and would otherwise hold off the refresh until the clock
caught up.

## At start

`AppState.init` loads every metadata set with `serveStale`: a stored entry of
any age is decoded and returned, and the loader reports when it was stored.
Only a set with no usable entry is fetched, and only that blocks. The native
widget channel (`lib/native_pipe.dart`) loads device types through the same
call, `AppState.loadStoredDeviceTypes`, so an `init` joining it records the set
too.

After the first frame (`SchedulerBinding.endOfFrame`), one background pass
fetches with `Duration.zero` every set whose stored time is older than
`metadataMaxAge`, then calls `notifyListeners()` and `pushRefresh()` if any of
them succeeded.

`AppInitializer` calls `CacheHelper.scheduleCacheUpdates`, which runs the
favorites migration and then starts a refresh of every entity collection that is
due. It arms no timer.

## On resume

`AppState.didChangeAppLifecycleState(resumed)` calls
`CacheHelper.scheduleCacheUpdates()` and the same background pass as at start,
which on resume also loads every set whose last load failed (no stored time
recorded), with `Duration.zero` and `serveStale` so its time is recorded once it
succeeds. Both are no-ops while nothing is due. The pass does nothing before
`init` has finished and in local mode. The Classes list asks for the same retry
(`AppState.retryFailedMetadata`) only when it is opened without classes, not on
resume or `refreshPressed`, so one resume retries a failing set once.

## Running once

- Metadata: one pass at a time. A pass re-checks for due sets before it ends,
  so a set reported stale while it ran is not missed. A retry request carries
  a serial and the account epoch: each request retries a failed set once, also
  one the running pass already tried, and is cleared only when a pass of its
  epoch has covered it, or when a loader of that pass threw. A request the pass
  did not cover, such as one made under the next account while an older pass
  ran, starts a pass of its own when that pass ends.
- Entities: `scheduleCacheUpdates` skips a collection while any refresh of it
  runs, including one from `refreshCache` (login, Settings). An explicit device
  refresh (`refreshCache`, `refreshDevicesNow`) joins a device refresh running
  under the current account instead of starting a second one, whose prune
  could drop rows the other fetched; when the joined one was quiet, the
  explicit caller reports its failure.
- Loaders share a running call through `JoinedLoad`, so a call joining a
  running one gets that call's result, whatever `maxAge` or fallback it asked
  for. Only a call started under the current `AccountEpoch` is joined.
- The device refresh upserts its chunks over the old rows and prunes the rows
  it did not fetch only at the end, so a refresh dropped half-way leaves the
  old rows plus the chunks already written, and stays due.
- The device refresh fetches with `getDevices(store: false)`, so each device
  is stored once, in its chunks; the tabs' paging keeps the write-through.
  Each chunk takes its favourite flags inside its own write
  (`DevicesService.applyFavoriteMirror`), so a star tapped during the refresh
  is kept.
- `AccountEpoch` (`lib/shared/account_epoch.dart`) advances on logout and on an
  account change, before the wipe. Stored copies (`MetadataCache.write`) and
  entity rows (the refreshes and the list fetches of the entity services) are
  dropped for a gone account; that includes the row a save or create stores
  after its request and the persisted notifications, all through
  `AccountEpoch.writeIfCurrent`. An account change also clears the persisted
  notifications, which the notification list falls back to offline, and the
  list in memory. The epoch does not know the account, so a save that returns
  after a logout and a new sign-in of the same account is dropped too; that
  row is missing from Isar until the next refresh or list fetch writes it.
  Accepted: the window is one request long, and the login refresh refills it.
- A load that outlives the change leaves the maps and lists in memory alone
  and logs its failure instead of reporting it; a loader that reports success
  returns `false`. It does not notify, except a network load dropped after its
  gateway merge, which notifies from `mergeGatewaysWithNetworks`. A call made
  after the change does not join it, neither through `JoinedLoad` nor through
  the mutex of the device groups, networks, locations and notifications, but
  loads for the new account. A call made before the change and still waiting
  on that mutex loads nothing. An `init` that outlives the change leaves
  `AppState` uninitialized, so the next account runs its own, and a Settings
  refresh that outlives it neither fails nor announces a reload.
- A notification load that outlives the change neither shows, stores nor falls
  back to the stored set, nor reports its failure; one that waited for it
  fetches for the new account. The stored set is never the fallback while
  nobody is signed in. A created group or location returned after the
  change is not added to the lists on screen.

## Explicit refreshes

The Settings refresh (`RefreshCacheTile`) clears the Hive HTTP cache but keeps
the metadata byte cache, and `AppState.reloadMetadata` fetches every set with
`Duration.zero`, so a failure still fails the refresh. A failed fetch leaves the
stored copy for the next start. Logout and the account switch still clear the
metadata cache (`CacheHelper.clearCache`).

The login path (`lib/home.dart`) calls `CacheHelper.refreshCache` in the
background as before.

Pulling the Classes list (`AppState.reloadDeviceClasses`) fetches the device
classes and the device types with `Duration.zero` and runs the device refresh as
an explicit one (`CacheHelper.refreshDevicesNow`, counted as running), so the
counts follow too. It reports failures; in local mode it does nothing. A class
or type load it joins that was not fresh and reported is followed by one of its
own, so the pull always fetches fresh and reports a failure.

## Device classes

- The Classes list and the filter menu show `DeviceMixin.usedDeviceClasses`:
  the classes with at least one loaded device type. They follow every load of
  the device types, including the reload `ensureDeviceTypes` starts for a type
  it does not know, and `replaceDeviceIndex` starts that reload for the types
  of the refreshed devices once a type load has succeeded.
- On a backend without `/user-device-types` the type list is every type of the
  platform (`DeviceTypesService.userListIsAllTypes`, stored next to the list
  under `user-device-types-all`). Then, once the device index is complete, the
  used types are those of the indexed devices, for the list, the filter and the
  class images; before that no class image is downloaded. A stored list without
  that entry, as an older version stored it, is served but reported stale, so
  the first pass refetches it.
- A class filter is resolved to the loaded device types of its classes when a
  query is built: `device-type-ids` remotely, `device_type_id` in Isar. An
  empty id or type list matches nothing in both.
- A class row counts the indexed devices of its types
  (`visibleDeviceCountOfClass`), hiding inactive ones like `visibleDeviceCount`.
  The device index keeps each device's type next to its inactive flag. It
  counts only once complete, after `replaceDeviceIndex` or a seed from a cache
  a full device refresh has filled (`CacheHelper.devicesRefreshedOnce`); before
  that the row shows no count, since the pages seen so far would undercount.
  A complete index without any device of the class shows no count either: the
  list holds only types of the user's devices, so such a type means the type
  list is behind, and a fresh type load is started under the retry rules of
  `ensureDeviceTypes` (one per such type, none within `deviceTypesRetryDelay`
  of a failure). The account
  change empties the index as incomplete. Counts follow the device refresh, up
  to `entityMaxAge` late for a device added elsewhere unless the list is pulled.
  The device ids per class are built once and dropped when the index or the
  types change; an index change also downloads the images of classes it
  brings onto the list.
- The stored answer of the removed api-aggregator endpoint
  (`device-class-uses`) is migrated at the first class load of a process: with
  no `device-classes` copy, its classes are stored as one dated 1970, so local
  mode keeps them and the next pass refetches them. The old entry is deleted
  only once a `device-classes` copy exists. An old entry that cannot be read
  is logged and kept; the class load goes on as if there were none.

## Test hooks

| Hook | Effect |
|---|---|
| `DeviceMixin.fetchDeviceTypes(maxAge, serveStale:)` | Replaces the device-type loader; `serveStale` is non-null when a stale copy may be served, and calling it reports the stored time |
| `DeviceMixin.fetchDeviceClasses(maxAge, serveStale:)` | Replaces the device-class loader, like `fetchDeviceTypes` |
| `DeviceMixin.readCachedDeviceIndex` | Replaces the Isar read that seeds the device index |
| `DeviceMixin.deviceTypesAreAll` | Replaces the read of `DeviceTypesService.userListIsAllTypes` taken at each type load |
| `CacheHelper.refreshDeviceGroupsNow()` | Runs the device group refresh as an explicit one, counted as running like any other |
| `CacheHelper.refreshDevicesInBackgroundForTest()` | Runs the device refresh quietly, as `scheduleCacheUpdates` does, so an explicit one can join it |
| `DeviceClassesService.resetLegacyMigrationForTest()` | Lets the next class load migrate the `device-class-uses` entry again |
| `CacheHelper.entityRefreshDue(refreshedAt, now)` | The due check of the entity refresh |
| `CacheHelper.afterDeviceChunkForTest` | Called after each chunk the device refresh writes, to change the account between two chunks |
| `CacheHelper.afterDevicePruneForTest` | Called right after the device refresh prunes, before it marks the collection refreshed |
| `Auth.cleanupForTest()` | Runs the logout cleanup (`_cleanup`) without a signed-in client |

Tests: `metadata_stale_cache_test.dart`, `cache_updates_resume_test.dart`,
`account_change_cache_test.dart`, `inactive_device_cache_test.dart`,
`device_types_cache_test.dart` and
`device_search_filter_isar_test.dart` (tag `isar`),
`metadata_revalidation_test.dart`, `device_classes_load_test.dart`,
`visible_device_count_test.dart`, `device_class_list_test.dart`,
`metadata_retry_test.dart`, `device_types_service_test.dart`,
`device_refresh_join_test.dart`, `reload_device_classes_test.dart`,
`device_class_resume_test.dart`,
`cache_freshness_rules_test.dart`.
