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

The order inside the switch is load-bearing in two directions:

1. `FavoritesMigration.run()` — while the outgoing account is still the one in
   `account`, because the migration keys by it and the rows it reads are about
   to be deleted.
2. `CacheHelper.clearForAccountChange()` — drops the cached entities and the
   `cacheUpdated_*` timestamps, so the next account does not see the previous
   one's devices.
3. `Settings.setAccount(sub)` — **last**. If the wipe throws, the old key stays
   in place and the whole switch is retried on the next sign-in. Writing the
   new key first would leave the previous account's rows in the cache with no
   record that they were never cleared.

Logout and a transient `NotLoggedIn` deliberately do not trigger any of this.
Logout clears the cache through its own path, and a transient event must not
destroy the offline database of the account that is still signed in.

## Verification

The test suite cannot cover any of this — it needs a real identity. Re-run
these by hand after changing the storage, the migration or the switch:

- Star an entity, restart, star still set.
- Sign in as A, then B, then A again: B sees neither A's devices nor A's
  favorites, and A's list is unchanged on return. The log line is
  `Account changed, dropped the previous account's cache`.
- The migration path only exists on an installation that has favorites on its
  cached rows, so it needs an upgrade over an existing install rather than a
  fresh one.
