# Testing

How the test suite is organised, which tests need something beyond a plain
`flutter test`, and the hooks in `lib/` that let a test replace the network,
the auth headers and the time zone.

## Scope

Covers the files under `test/`, `dart_test.yaml`, `tool/test-isar.sh` and the
test hooks listed below. Not about the release pipeline or the checks it runs
besides the tests; that is `docs/releases-and-versioning.md`.

Goldens are compared pixel by pixel and are only generated and checked on
Linux x64. A golden produced on another operating system renders text
differently and will not match; that case has not been set up.

## Running

| What | Command |
|---|---|
| Everything that runs on this host | `fvm flutter test` |
| Goldens only | `fvm flutter test --tags golden` |
| Regenerate goldens | `fvm flutter test --update-goldens --tags golden` |
| Isar-backed tests | `tool/test-isar.sh` |

CI runs `flutter test --run-skipped`, which includes the `isar` tag.

### Tags

- **`golden`** — screenshot tests, one file per screen family
  (`test/golden_*_test.dart`), images under `test/goldens/`. Never skipped.
- **`isar`** — tests that open a real Isar database. `dart_test.yaml` skips
  them by default, because the Isar core binary needs glibc 2.38 and hosts with
  an older one cannot load it. `--run-skipped` in CI works only as long as this
  tag is the only thing that skips: a test marked `skip:` for another reason
  would run there too. Skip through a tag, not per test.

`tool/test-isar.sh` runs the `isar` tests in an Ubuntu 24.04 container. It
mounts the Flutter SDK from `.fvm/flutter_sdk`, the pub cache and the
repository at their host paths and runs as the host user, so `.dart_tool`
stays valid for the host afterwards. The first run needs network access for the
image and the binary; the binary is kept under `.dart_tool/isar/`, and CI caches
that directory.

Golden diffs of a failed run land in `test/failures/`, which is ignored.

## Harness

`test/test_helper.dart`:

- `setUpTestEnvironment()` — test binding plus a fake `path_provider` pointing
  at a temp directory, so Hive and Isar write real files.
- `openTestIsar(schemas)` — opens a fresh Isar instance and makes it the app's
  global `isar`. Only for tests tagged `isar`.

`test/golden_helper.dart`:

- `setUpGoldenEnvironment()` — once per file: dotenv from the keys of
  `.env.example` (`.env` is not in the repository), Settings in a temp Hive
  with the account `test-account` (sensor tabs, dashboards and favorites are
  per account), mocked secure storage and toast channel, silenced
  `ErrorReporter`, Roboto and MaterialIcons loaded from the Flutter SDK, and
  UTC as display time zone.
- `pumpGolden(tester, widget, dark: ...)` — mounts the widget under the app's
  providers and themes on a 412×915 surface at device pixel ratio 1. It mounts
  each variant **fresh**: pumping light and then dark into the same tree would
  capture the theme cross-fade half done.
- `serveGoldenBackend(backend)` / `resetGoldenBackend()` — route all HTTP
  through a `FakeBackend` and fix the auth headers; reset in `tearDown`.
- `warmUpMgwStorage(tester)` — opens the gateway storage once outside the fake
  test zone, before a screen that reaches it is pumped.
- `resetAppStateForGolden()` — clears what a test filled into `AppState`.

`test/fake_backend.dart` holds `FakeBackend`, a Dio `HttpClientAdapter`.
`serveJson(method, path, status, body)` registers a route; any route not
registered answers 404 and is recorded in `requests`, which also documents what
a screen fetches.

- `stopServing(method, path)` removes a route again, for a test that lets a
  second load fail after a first one succeeded.
- `holds["METHOD path"] = Completer()` delays the answer of a `serveJson` route
  until the completer finishes; `holdDevices` does the same for
  `serveDevicesPaged`. Both let a test act while a request is in flight, for
  example a second search or an upgrade tap during a reload.
- `failures["METHOD path"] = DioExceptionType.receiveTimeout` makes the route
  throw a `DioException` of that type instead of answering, for the code that
  decides on the type of a failure rather than on a status.
- `serveDevicesPaged(devices)` slices by offset/limit and honours `ids`,
  `device-type-ids` and `search` (substring of the name) like the real
  endpoint, with `X-Total-Count` set to the count before client-side hiding.

Light and dark captures of one screen stay in one `testWidgets`: Dio instances
are memoized for the process, and a memoized future created in an earlier test
may not resolve in a later one.

A second `testWidgets` in the same file whose screen makes requests may never
get its answers, for the same reason; the tests for the device filter, the
sensor picker, group and location editing and the sensor grid therefore sit in
files of their own, or run several cases inside one `testWidgets`.

Real I/O started from a gesture hangs as well: `tester.longPress` on a row that
writes a favourite to Hive starts the write inside the fake zone, and no later
`pump` or `runAsync` sees it complete. Take the resolved callback from the
widget and call it inside `runAsync` instead
(`test/device_list_item_interactions_test.dart`).

Chart tooltips show only while the pointer is down, so a tooltip golden holds
the gesture: `startGesture` on a data point, capture, then `up()`
(`golden_smart_service_charts_test.dart`, `golden_detail_chart_test.dart`).

Goldens run without a system inset and at text scale 1.0. Layout under a bottom
inset and at larger text sizes is covered by plain widget tests that set
`tester.view.viewPadding` or a `TextScaler` and assert no overflow
(`detail_page_scroll_test.dart`, `device_list_item_layout_test.dart`,
`detail_page_header_layout_test.dart`, `sensor_values_overflow_test.dart`).

The switch tile tests share `test/sensor_switch_fixture.dart` (`PlugBackend`,
which answers command batches like real plugs): `switch_tile_test.dart`,
`sensor_switch_tile_{device,group,connection,layout,readback}_test.dart`,
`sensor_picker_on_off_test.dart`, `detail_page_unknown_switch_test.dart` and
`golden_sensor_switch_tiles_test.dart`. A test whose last step toasts must pump
3 s at the end: the fluttertoast plugin leaves a 2 s timer pending.

## Test hooks in `lib/`

All are `@visibleForTesting` and never set by production code.

| Hook | Effect |
|---|---|
| `AppHttpClientAdapter.testOverride` (`lib/shared/http_client_adapter.dart`) | Answers every request of every Dio that carries an `AppHttpClientAdapter` (all built by `DioFactory` and the hand-built ones under Known gaps), including instances created before it was set, because it is checked on each fetch |
| `Auth.headersOverride` (`lib/services/auth.dart`) | Returned by `getHeaders()` instead of running the OpenID refresh |
| `useUtcForDisplayTime` (`lib/shared/display_time.dart`) | Makes `toDisplayTime()` return UTC instead of local time, so rendered times are the same on every host |
| `DeviceTypesService.listDio` / `listHeaders` (`lib/services/device_types.dart`) | The Dio and headers of the device-type list requests only |
| `DeviceMixin.fetchDeviceTypes` (`lib/mixins/device_mixin.dart`) | Replaces the device-type loader, for tests of the reload logic without HTTP; its `serveStale` argument is the stale-serving report of `docs/cache-freshness.md` |
| `DeviceMixin.fetchDeviceClasses` (`lib/mixins/device_mixin.dart`) | Replaces the device-class loader, with the same arguments as `fetchDeviceTypes` |
| `CacheHelper.afterDeviceChunkForTest` (`lib/services/cache_helper.dart`) | Called after each chunk the device refresh writes, so a test can change the account between two chunks; awaited, so it can run a whole wipe there |
| `CacheHelper.afterDevicePruneForTest` (`lib/services/cache_helper.dart`) | Called right after the device refresh prunes, before it marks the collection refreshed; awaited like the chunk hook |
| `Auth.cleanupForTest()` (`lib/services/auth.dart`) | Runs the logout cleanup without a signed-in client; the identity package's secure-storage channel (`plugins.concerti.io/openidconnect_secure_storage`) needs a mock handler |
| `Auth.serverAvailableOverride` / `onLogoutForTest()` (`lib/services/auth.dart`) | Replace the server check of the logout and run the logout that follows a client event, so a test can log out offline |
| `Auth.rememberAccountForTest(identity)` (`lib/services/auth.dart`) | Records a sign-in as every sign-in path does, switching the account when the identity's `sub` differs; an `OpenIdIdentity` with an unsigned id token carrying `sub` is enough |
| `Auth.clientListenerRegistered` / `listenToClientEventsForTest(events)` (`lib/services/auth.dart`) | Whether the OIDC client's events have a listener, and a stream to listen to in place of a real client's, which only a real setup provides |
| `CacheHelper.beforeAccountWipeForTest` / `afterAccountKeyForTest` (`lib/services/cache_helper.dart`) | Called before the cache clear of an account wipe, where throwing fails that part, and right after a switch wrote the new key |
| `AppInitializer.openCache(open)` (`lib/app_initializer.dart`) | Opens Isar through `open` and retries a pending account wipe, as the start does |
| `NotificationMixin.releaseTopicsSupported` (`lib/mixins/notification_mixin.dart`) | Whether the release topics are synced; Android only by default, so a test sets it to drive them |
| `NotificationMixin.fcmTokenDeletionTimeout` / `fcmTokenDeletionsForTest` (`lib/mixins/notification_mixin.dart`) | How long a token request waits for the token deletions, and the chain of those deletions, which a `tearDown` awaits so none runs into the next test |
| `NotificationMixin.messagingOverride` (`lib/mixins/notification_mixin.dart`) | Replaces `FirebaseMessaging.instance`, which throws without a Firebase app; a `Fake implements FirebaseMessaging` answers `requestPermission` through `noSuchMethod` (`account_change_memory_test.dart`) |
| `DeviceMixin.readCachedDeviceIndex` (`lib/mixins/device_mixin.dart`) | Replaces the Isar read that seeds the device index (type and inactive flag per device, and whether a full refresh filled the cache), so the counters can be tested without the Isar container |
| `DeviceMixin.deviceTypesAreAll` (`lib/mixins/device_mixin.dart`) | Replaces the read of `DeviceTypesService.userListIsAllTypes`, so the fallback to the platform's type list can be tested without its backend |
| `MgwReachability.probeOverride` (`lib/services/mgw/reachability.dart`) | Replaces the network probe behind `check`/`statusOf`, given the stored entry; the cache, the `forget()` epochs, the sequence guard and the `revision` signal still run |
| `MgwStorage.restartForTest()` (`lib/services/mgw/storage.dart`) | Forgets that the shared gateway secrets were moved to the pairings, so the next credential read runs that migration again, as a new start would |
| `MgwStorage.beforeListWriteForTest` (`lib/services/mgw/storage.dart`) | Called before each write of the gateway list; throwing from it fails the write, for the cleanup after a pairing that could not be stored |
| `MgwDiscoveryService.discoverOverride` (`lib/services/mgw/discovery.dart`) | Replaces the mDNS scan; receives the `onUpdate` callback, so a test can report gateways while the scan runs |
| `ErrorReporter.present` / `clock` / `resetForTest()` (`lib/shared/error_reporter.dart`) | Silence or capture toasts; move time past the window in which a repeated toast is suppressed |
| `loadPinnedDevices` (`lib/widgets/tabs/sensors/sensor_values.dart`) | Replaces the sensors page's fetch of pinned devices, so a test can mark them `fromCache` |
| `SwitchCommands.resetForTest()` (`lib/widgets/tabs/sensors/switch_commands.dart`) | Clears the static in-flight guard and the stored read-backs of the switch tiles |
| `sparklineClock` (`lib/widgets/tabs/sensors/sensor_sparkline.dart`) | Fixes `loadSparklineValues`' "now", so a fixture's history points land inside its 2h window on every run |

Rendered times go through `toDisplayTime()`. A new widget that shows a local
time and calls `.toLocal()` directly produces goldens that differ between a
developer machine and CI.

## Known gaps

- Five places build their own `Dio` instead of using `DioFactory`:
  `lib/services/app_update.dart` and, under `lib/services/mgw/`,
  `advertisements.dart`, `auth.dart`, `reachability.dart` and `restricted.dart`.
  They carry `AppHttpClientAdapter.plain()`, so `testOverride` reaches them,
  but they get neither DioFactory's interceptor set nor its memoization. The
  four MGW clients are driven through the seam (`http_client_adapter_seam_test`,
  `mgw_session_retry_test`, `mgw_session_storage_failure_test`,
  `mgw_pairings_test`); for
  `app_update.dart` nothing fails if the adapter line goes missing. The update
  check itself still cannot be driven on the test host, because it returns
  before its request on any platform but Android.
- Text painted directly on a canvas without a font family renders as boxes,
  because the test binding's default font is not Roboto. Affects the value
  labels in `smart_service_pv_flow`; the golden still checks layout and colours.
- The shell golden (`device_tabs_shell`) shows an empty-lists state, and the
  `stacked_bar_chart` and `pie_chart` fixtures are two points one hour apart;
  they check the frame, not the content.
