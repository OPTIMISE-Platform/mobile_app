# Cache freshness

When the app serves a cached copy, when it refreshes one, and what makes a
screen wait for the backend.

## Scope

Covers the metadata byte cache (`lib/shared/metadata_cache.dart`), the metadata
and device-class loaders in `lib/mixins/data_mixin.dart` and
`lib/mixins/device_mixin.dart`, `AppState.init` and its resume handler
(`lib/app_state.dart`), and the entity refresh in
`lib/services/cache_helper.dart`. Not about the Hive HTTP cache behind
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
| Device types, functions, aspects, concepts, characteristics | `metadataMaxAge`, 7 days | Isar `CachedMetadata` |
| Devices, device groups, networks, locations | `CacheHelper.entityMaxAge`, 1 day | Isar entity collections, refresh time in Settings (`cacheUpdated_*`) |
| Device classes | none: refetched at every resume, and at start when the stored copy was served | Isar `CachedMetadata`, key `device-class-uses` |

Device classes carry which devices belong to a class, so a newly added device
has to show up under its class without waiting a week.

A time stamp in the future counts as expired for every cache. It comes from a
clock that ran ahead and would otherwise hold off the refresh until the clock
caught up.

## At start

`AppState.init` loads every metadata set with `serveStale`: a stored entry of
any age is decoded and returned, and the loader reports when it was stored.
Only a set with no usable entry is fetched, and only that blocks. Device
classes come from their stored copy the same way. The native widget channel
(`lib/native_pipe.dart`) loads device types through the same call,
`AppState.loadStoredDeviceTypes`, so an `init` joining it records the set too.

After the first frame (`SchedulerBinding.endOfFrame`), one background pass
fetches with `Duration.zero` every set whose stored time is older than
`metadataMaxAge`, then calls `notifyListeners()` and `pushRefresh()` if any of
them succeeded. Device classes are refetched in the same step when they came
from the stored copy.

`AppInitializer` calls `CacheHelper.scheduleCacheUpdates`, which runs the
favorites migration and then starts a refresh of every entity collection that is
due. It arms no timer.

## On resume

`AppState.didChangeAppLifecycleState(resumed)` calls
`CacheHelper.scheduleCacheUpdates()` and the same background pass as at start,
with the device classes always refetched. Both are no-ops while nothing is
due. The pass does nothing before `init` has finished and in local mode.

## Running once

- Metadata: one pass at a time. A pass re-checks for stale sets before it ends
  and clears its flag in the same synchronous step, so a set reported stale
  while it ran is not missed.
- Entities: `scheduleCacheUpdates` skips a collection while any refresh of it
  runs, including one from `refreshCache` (login, Settings).
- Loaders share a running call through `JoinedLoad`, so a call joining a
  running one gets that call's result, whatever `maxAge` or fallback it asked
  for.
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
  list in memory. An
  in-memory swap by a load that outlives a logout is not dropped, except the
  notification list, and a load joined across the change through `JoinedLoad`
  returns the old account's result.
- A notification load that outlives the change neither shows, stores nor falls
  back to the stored set, nor reports its failure; one that waited for it
  fetches for the new account. The stored set is never the fallback while
  nobody is signed in. A created group or location returned after the
  change is not added to the lists on screen.

## Explicit refreshes

The Settings refresh (`RefreshCacheTile`) clears the Hive HTTP cache but keeps
the metadata byte cache, and `AppState.reloadMetadata` fetches with
`Duration.zero` and the device classes without fallback, so a failure still
fails the refresh. A failed fetch leaves the stored copy for the next start.
Logout and the account switch still clear the metadata cache
(`CacheHelper.clearCache`).

The login path (`lib/home.dart`) calls `CacheHelper.refreshCache` in the
background as before.

## Test hooks

| Hook | Effect |
|---|---|
| `DeviceMixin.fetchDeviceTypes(maxAge, serveStale:)` | Replaces the device-type loader; `serveStale` is non-null when a stale copy may be served, and calling it reports the stored time |
| `DeviceMixin.fetchDeviceClasses` / `readCachedDeviceClasses` | Replace the device-class fetch and the read of the stored copy |
| `CacheHelper.refreshDeviceGroupsNow()` | Runs the device group refresh as an explicit one, counted as running like any other |
| `CacheHelper.entityRefreshDue(refreshedAt, now)` | The due check of the entity refresh |
| `CacheHelper.afterDeviceChunkForTest` | Called after each chunk the device refresh writes, to change the account between two chunks |
| `CacheHelper.afterDevicePruneForTest` | Called right after the device refresh prunes, before it marks the collection refreshed |
| `Auth.cleanupForTest()` | Runs the logout cleanup (`_cleanup`) without a signed-in client |

Tests: `metadata_stale_cache_test.dart`, `cache_updates_resume_test.dart` and
`account_change_cache_test.dart` (tag `isar`), `metadata_revalidation_test.dart`,
`device_classes_background_test.dart`, `cache_freshness_rules_test.dart`.
