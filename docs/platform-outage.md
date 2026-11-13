# Platform outage

What the app does when the platform (API and auth server) does not answer,
and how it notices that the platform is back.

## Scope

Covers `ApiAvailableService` (`lib/services/api_available.dart`), the
`ApiAvailableInterceptor`, the bounds on the requests to the auth server in
`Auth` (`lib/services/auth.dart`), the banner in `MyAppBar`, and how the app
keeps the login when the secure storage cannot be read. Not about the
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
- a discovery or token refresh in `Auth` that runs into its bound, likewise
  only after a failed probe, or one that fails with a transport error.

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
- `Auth.getHeaders()` refreshes nothing: it returns the stored token, or no
  header. The same holds in the local mode.
- `ErrorReporter` logs a missing connection without a toast.
- The device list and the sensors page ask the platform for no connection
  state, also not after a failed gateway status request. A device no gateway
  serves keeps the unknown state of a cached device. Its read commands still go
  through `DeviceCommandsService.runCommands`, where the interceptor refuses
  them before any I/O and each is answered with the offline 502
  (`docs/device-commands.md`). A gateway without the Device Command module
  leaves every read to the platform, so none is answered; the gateway panel
  says when the module is missing.
- The app bar shows "Platform not reachable"; in the local mode its own banner
  stands in.

## Live connections

A live MQTT connection that is down never sets the state: it would refuse
every platform request although only the broker is missing. The app bar
shows a banner of its own below this one instead, and leaves the platform out
of it while "Platform not reachable" shows (`docs/live-values.md`).

## Bounds in Auth

The session is one `flutter_secure_storage` entry, the `oauth2` credentials
with their token endpoint, so the start and a refresh need no discovery; login
and logout fetch the discovery document for their endpoints. A refresh is
bounded by `tokenRefreshTimeout` (5 s). Credentials moved from the
openidconnect package lack the token endpoint; the discovery their first
refresh needs is bounded by `clientSetupTimeout` (5 s). For a login the user
starts, the discovery, the refresh and the password grant are each bounded by
`loginTimeout` (30 s). After a failed discovery, the next one waits
`setupRetryInterval` (30 s) unless a login or logout starts it; the wait ends
when the platform is found again. The discovery URL is built from the current
settings on each use, and a result is kept per URL.

A bounded call goes on in the background. A discovery started meanwhile waits
on the running one, as long as that one is younger than `loginTimeout` and uses
the current URL. A refresh of the same credentials waits on the running one
instead of sending the refresh token a second time, as long as that one is
younger than `loginTimeout`; past it a new request goes out. A refresh that
ends late is applied unless a login or logout came between or a newer refresh
replaced its credentials: its credentials are stored, since Keycloak may have
rotated the refresh token. An `invalid_grant` of a refresh replaced by a newer
one that still runs is left to that one. A password grant that ends after its
bound starts no session.

Only `invalid_grant` on a refresh logs out. A transport error, a timeout, a
5xx or another OAuth error keeps the credentials. A storage that cannot be
read, as on an iPhone before its first unlock, deletes nothing: the login
screen shows, and the next `getHeaders()`, login or app resume reads again.
A storage that answers nothing while `Settings.getCredentialsStored()` says
credentials were stored counts as such a read error; flutter_secure_storage
on iOS answers so before the first unlock. Every logout sets
`Settings.getSignedOut()` before it deletes the credentials, and only a login
that stored its credentials clears it. While it is set, a start takes neither
stored nor openidconnect credentials and tries the deletion again, so a
deletion that failed, or that Android reported as done without deleting,
cannot sign the logged-out account back in. A login waits at most
`loginTimeout` for the cleanup of the last logout and fails past it.

A logout while the platform is unreachable logs out without revoking; in local
mode it revokes. A revocation is bounded together with its discovery by
`logoutTimeout` (5 s); past it, or without a discovery, the logout goes on
without it. Every logout then runs the same local cleanup, none of which needs
the network: the stored credentials, the live client certificate, the HTTP and
metadata caches and the state in memory go.

### Sign-in with a code

`Auth.loginWithCode` is the OAuth 2.0 Device Authorization Grant (RFC 8628):
the app shows a code, the user enters it at the server's address on another
device. The discovery is the login's; without `device_authorization_endpoint`
in it the sign-in ends with a message, the button stays. The device
authorization request is bounded by `loginTimeout`. Then the token endpoint is
polled at the server's `interval` (5 s without one, at least 1 s), 5 s slower
after each `slow_down`, until the code's `expires_in` has passed, counted from
before the request. `authorization_pending`, transport errors, timeouts (each
poll bounded by `loginTimeout`) and answers that are no OAuth error go on;
`access_denied`, `expired_token`, `unauthorized_client` and any other OAuth
error end with a message.

The wait does not hold the login lock, so `loggingIn` stays false and
`getHeaders()` is not blocked. Only the start of the session with the tokens
takes it, and it runs the password login's own steps. The tokens are dropped
when the sign-in was cancelled meanwhile or a valid session came first. One
sign-in with a code runs at a time: a new one, a password login, Cancel, Back,
leaving the login screen and a stored session that loads meanwhile end it.
Its wait between polls and its running request end at once; a discovery still
running is not stopped and runs on for at most `loginTimeout`, without
starting a session. An answer that arrives later starts nothing. When it ends
without signing in and without a message to show, the login screen shows the
password form again.

## Secure storage on Android

flutter_secure_storage 9.2.4 keeps every store with
`encryptedSharedPreferences` in one file, `FlutterSecureStorage.xml`, so no
store sets `resetOnError`: its reset after any read error deletes the whole
file, the login with it. A read error leaves the value in place, and its
caller treats it as not available for now: Auth as above, the queued push
messages stay for the next resume, the live install id and certificate are not
replaced and the connection retries, the gateway secrets and sessions fail the
request as `storageFailed`.

`AppInitializer.checkSecureStorage` resets the file only when it stays
unreadable. It reads an entry of its own, written at the first start. An
error that recurs on every read (an entry that does not decrypt) resets at
once; any other failure, also the entry reading as absent after it was
written, resets after three starts in a row, since a Keystore can fail for a
while and the plugin answers nothing for every entry when it cannot open the
file. The main case is a restore from a backup: the manifest leaves
`allowBackup` at its default, which backs the file up without its Keystore
key.
