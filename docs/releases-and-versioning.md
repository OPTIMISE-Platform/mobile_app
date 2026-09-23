# Releases and versioning

How a commit becomes a build, a tag and a GitHub release, and where the version
number comes from. The short version: the branch decides whether the release is
a prerelease, `pubspec.yaml` decides the tag, and nothing is triggered by
pushing a tag.

## Scope

Covers the three workflows in `.github/workflows/` and the `version:` field in
`pubspec.yaml`. Not about the signing material itself — the keystore and
`key.properties` are reconstructed from repository secrets at build time and
exist nowhere in the tree; see the README for what a local build needs instead.

## The version lives in pubspec.yaml

Both build workflows read it out of the file and use it for everything
downstream:

```bash
v=$(grep -Po 'version: \K.*' pubspec.yaml)
```

That value becomes the git tag, the release title, and a `VERSION` entry in the
generated `.env`, so the running app knows which build it is. The tags therefore
match the pubspec field exactly, including the build number: `0.0.391+391`.

## The branch decides the release kind

| Push to | Workflow | Result |
|---|---|---|
| `dev` | `android-dev.yml` | APK, tag, GitHub release with `prerelease: true` |
| `master` | `android.yml` | APK, tag, GitHub release with `prerelease: false` |
| either, plus pull requests | `checks.yml` | `flutter analyze --no-fatal-infos` and `flutter test` |

Both build workflows end by publishing a Firebase Cloud Messaging message to the
`android` topic, so installed apps learn that a new release exists. Every push to
either branch reaches users this way — there is no dry run.

## Nothing is triggered by a tag

The tags are an *output* of the build, not its trigger. `marvinpinto/action-automatic-releases`
creates them from `VERSION` after the APK is built. Pushing a tag by hand
therefore builds nothing, and worse, takes the name the next build wants: the
action fails when its target tag already exists.

Two consequences worth knowing before touching the release path:

- **Do not create the tag manually** as part of preparing a release. The push to
  the branch is the whole action.
- **A merge from `dev` to `master` without a version bump collides.** The dev
  build has already published that tag; the master build then tries to create it
  again. Whatever the release process becomes, it has to answer whether the
  master release reuses the dev version or gets its own.

## Bumping is a manual step

The README documents a `pre-commit` hook that increments the version on every
commit. It is not installed in every checkout, and the history does not look
like it ran: the version moves in dedicated `chore: bump version to X` commits
placed immediately before the release-triggering push, not once per commit.

Treat the explicit bump commit as the convention and the hook as optional. What
matters is that `pubspec.yaml` carries a version no previous build has used
before anything is pushed to `dev` or `master`.

## Keeping the Flutter version in step

The SDK version is pinned in six places, and they have drifted apart before:

- `.fvmrc`
- `pubspec.yaml` (`environment: flutter:`)
- `.vscode/settings.json` (`dart.flutterSdkPath`, rewritten by `fvm use`)
- the `flutter-version` input in each of the three workflows

A CI version older than what `pubspec.yaml` requires fails in `flutter pub get`,
which is why `android.yml` carries a comment at that input.
