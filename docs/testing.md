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
  `.env.example` (`.env` is not in the repository), Settings in a temp Hive,
  mocked secure storage and toast channel, silenced `ErrorReporter`, Roboto and
  MaterialIcons loaded from the Flutter SDK, and UTC as display time zone.
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

Light and dark captures of one screen stay in one `testWidgets`: Dio instances
are memoized for the process, and a memoized future created in an earlier test
may not resolve in a later one.

## Test hooks in `lib/`

All are `@visibleForTesting` and never set by production code.

| Hook | Effect |
|---|---|
| `AppHttpClientAdapter.testOverride` (`lib/shared/http_client_adapter.dart`) | Answers every request of every Dio built by `DioFactory`, including instances created before it was set, because it is checked on each fetch |
| `Auth.headersOverride` (`lib/services/auth.dart`) | Returned by `getHeaders()` instead of running the OpenID refresh |
| `useUtcForDisplayTime` (`lib/shared/display_time.dart`) | Makes `toDisplayTime()` return UTC instead of local time, so rendered times are the same on every host |
| `DeviceTypesService.listDio` / `listHeaders` (`lib/services/device_types.dart`) | The Dio and headers of the device-type list requests only |
| `DeviceMixin.fetchDeviceTypes` (`lib/mixins/device_mixin.dart`) | Replaces the device-type loader, for tests of the reload logic without HTTP |
| `ErrorReporter.present` / `clock` / `resetForTest()` (`lib/shared/error_reporter.dart`) | Silence or capture toasts; move time past the window in which a repeated toast is suppressed |

Rendered times go through `toDisplayTime()`. A new widget that shows a local
time and calls `.toLocal()` directly produces goldens that differ between a
developer machine and CI.

## Known gaps

- Five places build their own `Dio` instead of using `DioFactory`, so
  `testOverride` does not reach them and a test there would go to the real
  network: `lib/services/app_update.dart` and, under `lib/services/mgw/`,
  `advertisements.dart`, `auth.dart`, `reachability.dart` and `restricted.dart`.
- No goldens for `pv_forecast` (overflows its fixed height when rendered
  outside a scrollable), `pv_flow` (a ticker that never stops) and
  `bar_chart_estimate`, and none for the app bar's default actions, which start
  network calls for notifications and updates.
- The sensor values golden is served no sparkline data: points generated
  relative to `DateTime.now()` shift the sparkline's fill edge by a sub-pixel
  amount between runs.
- The shell, dashboard and line-chart goldens show sparse states (an empty
  dashboard widget, axis labels from points within one hour); they check the
  frame, not the content.
