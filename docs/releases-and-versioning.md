# Releases and versioning

How a commit becomes a build, a tag and a GitHub release, and where the version
comes from. The short version: the branch decides the channel, the tags and
commits decide the version, and nothing in the tree is bumped by hand.

## Scope

Covers `.github/workflows/android-release.yml`, the script
`.github/scripts/release-version.sh` it calls, the iOS build it runs next
to the APK, the release topics the app subscribes to, and the Google Play
build. Not about the
signing material itself — the keystore, `key.properties` and the iOS
certificate and profile are reconstructed from repository secrets at build
time and exist nowhere in the tree.

## The branch decides the channel

| Push to | Result |
|---|---|
| `dev` | APK and ad hoc IPA, tag `0.1.0-dev.3+412`, GitHub release with `prerelease: true` |
| `master` | APK and ad hoc IPA, tag `0.1.0+420`, GitHub release marked latest |
| pull requests | `checks.yml`: analyzer, `flutter test`, the versioning script's tests |

On `dev` and `master`, the release workflow runs `checks.yml` as its first job
and goes on only when it passes:

```
checks ─▶ version ─┬─▶ release (APK, GitHub release, notification) ─┬─▶ ios-attach
                   └─▶ ios (IPA, install manifest) ─────────────────┘
```

A failing check therefore reserves no tag and uses up no build number.

A merge from `dev` to `master` builds and releases on its own, with a new build
number, so stable users get an update. Prerelease users get it too, because its
build number is higher than every prerelease before it.

`workflow_dispatch` on any other branch does nothing, and a run on a commit that
already carries a tag of its channel is skipped.

## The version comes from the tags

`release-version.sh` computes three things:

- **Build number**: the highest `+N` of all tags plus one. It is the Android
  `versionCode` and what the in-app updater compares
  (`lib/services/app_update.dart`), so it has to grow across both channels.
  The `version` job runs one at a time and pushes the tag right away, which
  reserves the number before the ten-minute build starts.
- **Version**: the last stable tag, raised by the Conventional Commits since
  then — `fix` and everything else raise the patch, `feat` the minor, `!` or a
  `BREAKING CHANGE:` footer the major. Below 1.0 a breaking change raises the
  minor. Without a stable tag of this scheme yet, it is `0.1.0`; the older
  `0.0.N+N` tags are ignored as a baseline because most of them were
  prereleases.
- **Prerelease suffix**: `-dev.K`, counting up per target version.

The tag is `<version>+<build>`, and the workflow passes the parts to
`flutter build --build-name --build-number`. The app reads them back from the
installed package (`lib/shared/app_version.dart`), not from `.env`. The
`version:` in `pubspec.yaml` is a placeholder for local builds and stays as it
is.

## When a run fails

A failure in `checks` ends the run before any tag exists; fix it and push
again. The tag exists from the moment the `version` job is done, so:

- **Build or notification failed**: use "Re-run failed jobs". It keeps the
  reserved version, and the release step leaves an existing release alone.
- **"Re-run all jobs" does nothing**: the commit already carries its tag and is
  skipped. To start over with a new number, delete the tag first.
- **A tag without a release** still counts. Its build number is used up, and a
  stable one is the baseline for the next version.

## iOS

The `ios` job builds an ad hoc IPA and a `manifest.plist` for installing it
over the air, next to the Android build. `ios-attach` attaches both to the
release as `mobile_app.ipa` and `manifest.plist`, the manifest last. It runs
after the release job, also when that job failed, because a failed device
notification leaves a complete release behind. Until it is done, a release has
no IPA yet, and the app on iOS does not offer it. A failed iOS build does not
hold up the Android release.

The iOS version is the tag's version without `-dev.K`, since
`CFBundleShortVersionString` only takes numbers; the build number is the same
as on Android.

Signing comes from three secrets: `IOS_P12` (distribution certificate with its
key, base64), `IOS_P12_PASSWORD`, and `IOS_PROVISIONING_PROFILE` (the ad hoc
profile, base64). The Xcode project names the profile `optimise_25`, so a
renewed profile has to keep that name. An ad hoc build only installs on the
devices listed in the profile; adding a device means a new profile and a new
`IOS_PROVISIONING_PROFILE`.

An iPhone installs a release by opening
`itms-services://?action=download-manifest&url=<manifest asset URL, percent-encoded>`.
The app does this from its update dialog (`AppUpdater.showUpdateDialog`); iOS
then asks, downloads and replaces the app itself. The asset URLs redirect to
`release-assets.githubusercontent.com`, which the installer follows for both
files, so nothing besides GitHub has to serve them.

A local build uses the same export options:

```bash
flutter build ipa --release --no-tree-shake-icons --build-name 0.2.0 --build-number 422 --export-options-plist ios/ExportOptions-adhoc.plist
```

## Release topics

Both release kinds send a `release_info` message over Firebase Cloud Messaging.
The app subscribes every Android install to `android` and, while "Get
Pre-Releases" is on, to `android-prerelease` (`NotificationMixin.syncReleaseTopics`).

Stable releases go to `android`. Prereleases go to the topic in
`PRERELEASE_TOPIC` at the top of the workflow, which is still `android`: builds
from before the prerelease topic existed listen on nothing else. Switching it to
`android-prerelease` stops prerelease notices from reaching stable users, and
is safe once the installed base carries the subscription.

## Google Play

A Play build is the same app with `DISTRIBUTOR=play` in `.env` instead of the
`DISTRIBUTOR=github` the workflow writes. Every value other than `github`
leaves out two things:

- the in-app updater with its release topics and the "Get Pre-Releases" switch
  (`AppUpdater.updateSupported`);
- `REQUEST_INSTALL_PACKAGES`, which `android/app/build.gradle.kts` merges from
  `android/app/src/github/AndroidManifest.xml` only for `github`.

Google Play does not allow an app to update itself, and rejects the permission
when it serves that purpose. A local build without `DISTRIBUTOR` set is
therefore already a Play build.

Play takes an App Bundle, built with the version of a tag:

```bash
flutter build appbundle --release --no-tree-shake-icons --build-name 0.3.0 --build-number 460
```

Play App Signing signs with the key from `sepl.keystore`, uploaded once, so a
Play install and a GitHub APK carry the same signature and install over each
other. Play accepts each `versionCode` once and only above the last upload;
taking it from a tag keeps it unique across both channels.

## Keeping the Flutter version in step

The SDK version is pinned in five places, and they have drifted apart before:

- `.fvmrc`
- `pubspec.yaml` (`environment: flutter:`)
- `.vscode/settings.json` (`dart.flutterSdkPath`, rewritten by `fvm use`)
- the `flutter-version` inputs in both workflows (the release workflow has two)

A CI version older than what `pubspec.yaml` requires fails in `flutter pub get`,
which is why the workflows carry a comment at that input.
