# Favorites and the account switch

## Scope

Applies to the current favorites implementation: per-account id lists in the
Hive settings box, `favorite` on the Isar rows as an index mirror only. Covers
the interaction between `Settings`, `FavoritesMigration`, `Auth` and
`CacheHelper` from version 0.0.381 onwards.

**Not this if** you are looking at the `app/favorite` device attribute or at a
`setFavorite` call: that was the server-side variant, implemented and removed
again before release. Nothing in the current code reads or writes it, and an
installation that still has such attributes on the backend ignores them.

`geltung: allgemein` for this repository — the ordering constraints below
follow from the code, not from a single observation.

## Where favorites live

Two id sets in the settings box, keyed by the signed-in account:

```
favorite_devices_<sub>   Set<String> of device ids
favorite_groups_<sub>    Set<String> of device group ids
account                  the sub of the account these keys belong to
```

`<sub>` is the `sub` claim of the OIDC id token, which is the stable per-user
identifier — a username can change, this cannot.

The `favorite` column on the cached device and group rows is written from these
sets when rows are stored. It exists so Isar can sort and filter on it; it is
never the source of truth. That distinction is the point of the design: with
favorites living on the cached rows, the entity cache could not be dropped
without losing user data, which is what blocked the account switch below.

Two consequences worth knowing before changing this:

- **No account, no favorites.** The getters return an empty set and the setters
  are a no-op while `account` is unset. Toggling a star before the identity is
  known must not silently write to an unkeyed list, because that list would
  then be inherited by whoever signs in next.
- **Read-modify-write is not safe on its own.** Two toggles in the same frame
  read the same set and the second write loses the first. The setters serialise
  through the settings box write, and a caller that keeps a local mirror has to
  re-read after writing rather than trusting its copy.

## Sensor tabs and dashboards

The sensor tabs and the smart-service dashboards are per account the same way,
under `sensor_tabs_<sub>` and `smart_service_dashboards_<sub>`, with the same
rule: empty and unwritable without an account. Their getters and setters keep
their signatures.

An earlier version stored them unkeyed (`sensor_tabs`,
`smart_service_dashboards`, and before the tabs `pinned_sensors`), while
already recording `account`. They belong to that account: a switch moves them
to the outgoing account's keys before it writes the new key
(`Settings.moveLegacyAccountSettings`), and without a switch the signed-in
account takes them over when it first reads or writes one. The unkeyed keys
are deleted once the account's copy is written, also when the account already
has one. A read without an account leaves them in place.

The sensor page and the dashboard read their configuration only when they
mount; `refreshPressed` reloads their values, not their configuration.
`Home` keys `DeviceTabs` by `AccountEpoch.current`. The switch writes the new
key right after it advances the epoch, with no await between, so tabs mounted
again on the new epoch read the new account's.

## Migration off the rows

`FavoritesMigration.run()` copies favorites that only exist on the cached rows
into the keyed sets, once. It is guarded by `favorites_moved_off_cache` in the
settings box.

It has to run **before** anything drops those rows. Two paths can drop them:
the entity fetch paths, which replace rows wholesale, and the account switch
below. Both call the migration first. An installation upgrading from a version
before 0.0.381 that fetches before migrating loses every favorite it had, which
is the common upgrade path and not an edge case.

## The account switch

`Auth._rememberAccount(identity)` is the only place that sees an account
actually change: it compares the stored `account` against the `sub` of the
identity just obtained. It is called from every path that establishes an
identity — the stored-identity fast path in `init()`, the client setup, the
OIDC `Refresh`/`Success` events and `login()` — always before `loggedIn`
flips.

Keying this on the identity rather than on `loggedIn` is deliberate. On the
login path `loggedIn` is set by the OIDC event listener, so a check hung on the
flag fires after the tabs have already mounted and read the favorites of the
previous account.

The order of a switch is load-bearing. Step 1 runs in `Auth._rememberAccount`,
steps 2 to 6 in `CacheHelper.switchAccount`:

1. Under the outgoing account, while its key is still set:
   `FavoritesMigration.run()`, which keys by it and reads the rows about to be
   deleted, and `Settings.moveLegacyAccountSettings()`. A failure of either is
   logged and the switch goes on, so the next account never keeps the
   previous one's state.
2. `account_wipe_pending` and `fcm_token_deletion_pending` are persisted,
   before anything else changes.
3. `AccountEpoch.advance()`, and right after it `Settings.setAccount(sub)`:
   favorites, sensor tabs, dashboards and the message filter follow the new
   account from here on, also while the wipe is still pending.
4. The reset in memory as a logout does, with the FCM token deletion.
5. The wipe, in parts that each run whatever the others do: the metadata and
   HTTP cache, the entity rows and notifications, then the `cacheUpdated_*`
   timestamps.
6. The flag is cleared, only when every part of step 5 succeeded.

A failed step is logged and the next one runs. While the flag is set, every
sign-in, the next token refresh included, and the app start
(`AppInitializer.openCache`) retry steps 5 and 6 and only those: no reset, no
epoch, no deletion. It may drop rows of the account now signed in. An entity
refresh running across it notices the wipe (a counter bumped inside the wipe's
transaction, checked inside each of its writes and before it marks itself
refreshed) and stops without marking its collection, so the next refresh
refills it; one that marked itself before the rows went loses its timestamp to
the clear after them.

The switch is serialized: the login and the OIDC `Success` event it raises
both report the new identity, and the second call finds the new key already
written.

Logout and a transient `NotLoggedIn` deliberately do not trigger any of this.
Logout clears the cache through its own path, and a transient event must not
destroy the offline database of the account that is still signed in.

A logout that cannot reach the server (`Auth._onLogout`) cannot revoke the
tokens, but clears the stored identity through the client
(`OpenIdConnectClient.clearIdentity`), so the next login signs in with the
credentials it was given instead of resuming the previous account. It keeps
`account` and the favorites, like every logout. It drops the client and
cancels the listener of its events: a late event would otherwise act on the
next client, and the client's own logout, still running, finds no identity
left to clear. `Auth.logout` cleans up after the client's logout only while no
new session has begun.

## Verification

`account_change_memory_test.dart` drives the switch with identities built in
the test, and `settings_test.dart` the keyed settings. The OIDC client itself
and the favorites migration over real rows are not covered; re-run these by
hand after changing the storage, the migration or the switch:

- Star an entity, restart, star still set.
- Sign in as A, then B, then A again: B sees neither A's devices nor A's
  favorites, and A's list is unchanged on return. The log line is
  `Account changed, dropped the previous account's cache`.
- The migration path only exists on an installation that has favorites on its
  cached rows, so it needs an upgrade over an existing install rather than a
  fresh one.
