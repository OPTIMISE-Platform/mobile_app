# Platform outage

What the app does when the platform (API and auth server) does not answer,
and how it notices that the platform is back.

## Scope

Covers `ApiAvailableService` (`lib/services/api_available.dart`), the
`ApiAvailableInterceptor`, the bounds on the OIDC client in `Auth`
(`lib/services/auth.dart`) and the banner in `MyAppBar`. Not about the
gateways: requests to a paired gateway (`ApiAvailableService.servedLocally`)
are never refused and never mark the platform unreachable.

## The state

`ApiAvailableService.isPlatformUnreachable`, observable through
`ApiAvailableService.platformUnreachable` (a `ValueListenable`). `AppState`
and `Auth` notify their listeners on every change.

Set by:

- a platform request of a `DioFactory` instance that fails without an answer
  (`connectionError`, `connectionTimeout`, a socket error);
- a receive or send timeout or a 502, 503 or 504, but only if a probe then
  fails as well (`confirmUnreachable`): the ingress answers 502 or 504 for a
  single dead service too, and one such endpoint must not cut the app off;
- a client setup or token refresh in `Auth` that runs into its bound, likewise
  only after a failed probe, or a setup that fails with a transport error.

A 4xx or another answer from the platform never sets it.

Cleared only by a successful probe: the auth server's discovery document
answers 200 and the API host answers anything but 502, 503 or 504. The probe
runs every 60 s while the state is set, on resume, and when the local mode is
switched off. There is no timer while the platform is reachable or the local
mode is on, and no probe in the local mode. A failure of a request that left before the last successful
probe is dropped (`reachabilityEpoch`).

A probe that clears the state fires `ApiAvailableService.platformFound`. On it
`AppState` runs the refreshes of a resume (`docs/cache-freshness.md`), and the
screen on top reloads through `ResumeRefreshMixin.onResumed`, as on a resume.
Both only in the foreground; in the background the next resume does it.

## While it is set

- The interceptor refuses platform requests at once, as in the local mode.
  The navigation re-evaluates its locked tabs.
- `Auth.getHeaders()` sets up no client and refreshes nothing: it returns the
  stored token, or no header. The same holds in the local mode.
- `ErrorReporter` logs a missing connection without a toast.
- The device list and the sensors page ask the platform for no connection
  state, also not after a failed gateway status request. A device no gateway
  serves keeps the unknown state of a cached device. Its read commands still go
  through `DeviceCommandsService.runCommands`, where the interceptor refuses
  them before any I/O and each is answered with the offline 502
  (`docs/device-commands.md`).
- The app bar shows "Platform not reachable"; in the local mode its own banner
  stands in.

## Bounds in Auth

`OpenIdConnectClient.create` fetches the discovery document through
`httpRetry` without a timeout, so a dropped connection held every caller of
`getHeaders()` behind the auth mutex. The setup is bounded by
`clientSetupTimeout` (5 s) and a refresh by `tokenRefreshTimeout` (5 s); for a
login the user starts both are `loginTimeout` (30 s), and so is the password
grant; a grant that runs into it abandons its client, and the identity it
stores late is cleared unless a session began meanwhile. After a failed setup,
the next one waits `setupRetryInterval` (30 s) unless the user starts it
(login, logout, app start); the wait ends when the platform is found again.
The discovery URL is built from the current settings on each use.

A bounded call goes on in the background. A setup started meanwhile waits on
the running one instead of starting a second, as long as that one is younger
than `loginTimeout` and uses the current discovery URL; a connection that
never answers would otherwise hold every later setup. A setup that ends late is
adopted when the session still has no client and no login or logout came
between, and disposed of otherwise. A refresh that runs into its bound
abandons its client, so the client's late events reach neither the session
nor the next client. When an abandoned call ends, the stored identity is made
to match the session again: after a login or logout in between it is replaced
by the current one or cleared, otherwise an identity the call cleared on a
failure is put back and one it refreshed is kept.

From a logout until a login with credentials completes, an identity found in
the storage or in a new client is not trusted but cleared, and the client's
`Success`, `Refresh` and `NotLoggedIn` events are ignored. A refresh abandoned
before an offline logout can still store the signed-out account's identity;
the next login's setup would load it and end in "Old token still valid", with
the next user signed in as the previous one.

A logout sets up no client while platform calls are off, and one without a
client logs out like the offline path of the client's own logout event. The
revocation of a logout is bounded by `logoutTimeout` (5 s); past it the
logout ends the same way, dropping the client so that its late clear finds no
identity left.
