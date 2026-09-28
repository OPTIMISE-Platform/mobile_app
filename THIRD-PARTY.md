# Third-party code

Code taken over into this repository rather than pulled in as a dependency.

## openidconnect_android

| | |
|---|---|
| Path | `third_party/openidconnect_android/` |
| Source | https://github.com/4D-Technologies/openidconnect_flutter/tree/main/openidconnect_android, published as `openidconnect_android` 2.0.4 on pub.dev |
| Version | 2.0.4 (archive sha256 `9eac146a…6161`, as listed by the pub.dev API) |
| License | Apache-2.0, see `third_party/openidconnect_android/LICENSE` |
| Taken over | 2026-09-28 |

Wired in through `dependency_overrides` in `pubspec.yaml`, in place of the
published package that `openidconnect` depends on.

Why: the published package stores each identity value with its own Android
Keystore key and makes these keys StrongBox-backed wherever the device supports
it. A StrongBox read costs about 350 ms, the identity has six values, and the app
reads it twice at start, which held the login screen and the first backend call
for more than four seconds on a StrongBox device. No published version offers a
way to turn this off.

### Changes

Modified files carry a notice line at the top.

- `AndroidSecureStorage.kt`: new keys are never StrongBox-backed (TEE only).
  On API 31+, a read whose key is StrongBox-backed deletes that key after
  decrypting, re-encrypts the value with a new TEE key and rewrites the file;
  each value migrates once. Below API 31 `KeyInfo` cannot tell StrongBox from
  TEE, so old keys stay until the next logout or login replaces them.
- `CryptographyManager.kt`: adds `isStrongBoxBacked()`, based on
  `KeyInfo.getSecurityLevel()`.

Failure mode: the key has to be deleted before the rewrite, because the new key
uses the same alias. If the rewrite then fails, the current read still returns
the value, but the next start cannot decrypt it; `OpenIdIdentity.load()` clears
the identity and the user logs in again. A token refresh in between rewrites the
value and avoids that.
