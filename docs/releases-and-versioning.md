# Releases and versioning

How a commit becomes a build, a tag and a GitHub release, and where the version
comes from. The short version: the branch decides the channel, the tags and
commits decide the version, and nothing in the tree is bumped by hand.

## Scope

Covers `.github/workflows/android-release.yml`, the script
`.github/scripts/release-version.sh` it calls, and the release topics the app
subscribes to. Not about the signing material itself — the keystore and
`key.properties` are reconstructed from repository secrets at build time and
exist nowhere in the tree.

## The branch decides the channel

| Push to | Result |
|---|---|
| `dev` | APK, tag `0.1.0-dev.3+412`, GitHub release with `prerelease: true` |
| `master` | APK, tag `0.1.0+420`, GitHub release marked latest |
| either, plus pull requests | `checks.yml`: analyzer, `flutter test`, the versioning script's tests |

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
`flutter build apk --build-name --build-number` and writes the tag as `VERSION`
into `.env`. The `version:` in `pubspec.yaml` is a placeholder for local builds
and stays as it is.

## When a run fails

The tag exists from the moment the `version` job is done, so:

- **Build or notification failed**: use "Re-run failed jobs". It keeps the
  reserved version, and the release step leaves an existing release alone.
- **"Re-run all jobs" does nothing**: the commit already carries its tag and is
  skipped. To start over with a new number, delete the tag first.
- **A tag without a release** still counts. Its build number is used up, and a
  stable one is the baseline for the next version.

## Release topics

Both release kinds send a `release_info` message over Firebase Cloud Messaging.
The app subscribes every Android install to `android` and, while "Get
Pre-Releases" is on, to `android-prerelease` (`NotificationMixin.syncReleaseTopics`).

Stable releases go to `android`. Prereleases go to the topic in
`PRERELEASE_TOPIC` at the top of the workflow, which is still `android`: builds
from before the prerelease topic existed listen on nothing else. Switching it to
`android-prerelease` stops prerelease notices from reaching stable users, and
is safe once the installed base carries the subscription.

## Keeping the Flutter version in step

The SDK version is pinned in five places, and they have drifted apart before:

- `.fvmrc`
- `pubspec.yaml` (`environment: flutter:`)
- `.vscode/settings.json` (`dart.flutterSdkPath`, rewritten by `fvm use`)
- the `flutter-version` input in both workflows

A CI version older than what `pubspec.yaml` requires fails in `flutter pub get`,
which is why the workflows carry a comment at that input.
