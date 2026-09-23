#!/usr/bin/env bash
# Copyright (c) 2026 InfAI (CC SES)
#
# Derives the next release version from the git tags and the commits since the
# last stable release. Usage: release-version.sh stable|prerelease
#
# Prints key=value lines for $GITHUB_OUTPUT: name, build, tag, prerelease and
# skip. See docs/releases-and-versioning.md for the scheme.
set -euo pipefail

channel=${1:?usage: release-version.sh stable|prerelease}
[[ $channel == stable || $channel == prerelease ]] || { echo "unknown channel: $channel" >&2; exit 2; }

first_version=0.1.0
stable_re='^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'

# Stable tags of the current scheme. The 0.0.N+N tags before it were mostly
# prereleases, so they cannot serve as a baseline.
is_stable_tag() {
  [[ $1 =~ $stable_re ]] || return 1
  local v=${1%%+*}
  local major=${v%%.*} rest=${v#*.}
  local minor=${rest%%.*}
  ((major > 0 || minor >= 1))
}

tags=$(git tag -l '*+*')

# The build number is the Android versionCode and what the in-app updater
# compares, so it has to grow across both channels.
max_build=0
for t in $tags; do
  b=${t##*+}
  if [[ $b =~ ^[0-9]+$ ]] && ((10#$b > max_build)); then max_build=$((10#$b)); fi
done
build=$((max_build + 1))

for t in $(git tag --points-at HEAD -l '*+*'); do
  if [[ $channel == stable ]] && is_stable_tag "$t"; then
    echo "skip=true"; exit 0
  fi
  if [[ $channel == prerelease && $t == *-dev.*+* ]]; then
    echo "skip=true"; exit 0
  fi
done

last_stable=""
last_stable_build=-1
for t in $tags; do
  is_stable_tag "$t" || continue
  b=${t##*+}
  if ((10#$b > last_stable_build)); then last_stable=$t; last_stable_build=$((10#$b)); fi
done

if [[ -z $last_stable ]]; then
  next=$first_version
else
  # Types are read from subjects only, a body may quote another commit.
  subjects=$(git log --format='%s' "$last_stable..HEAD")
  bodies=$(git log --format='%b' "$last_stable..HEAD")
  if [[ -z $subjects ]]; then
    echo "skip=true"; exit 0
  fi
  bump=patch
  if grep -qE '^[a-z]+(\([^)]*\))?!:' <<<"$subjects" || grep -qE '^BREAKING[ -]CHANGE:' <<<"$bodies"; then
    bump=breaking
  elif grep -qE '^feat(\([^)]*\))?!?:' <<<"$subjects"; then
    bump=minor
  fi

  v=${last_stable%%+*}
  IFS=. read -r major minor patch <<<"$v"
  # Below 1.0 a breaking change raises the minor version, as semver allows.
  if [[ $bump == breaking ]]; then
    if ((major == 0)); then bump=minor; else bump=major; fi
  fi
  case $bump in
    major) next="$((major + 1)).0.0" ;;
    minor) next="$major.$((minor + 1)).0" ;;
    patch) next="$major.$minor.$((patch + 1))" ;;
  esac
fi

if [[ $channel == stable ]]; then
  name=$next
  prerelease=false
else
  n=0
  for t in $tags; do
    [[ $t =~ ^${next//./\\.}-dev\.([0-9]+)\+ ]] || continue
    if ((BASH_REMATCH[1] > n)); then n=${BASH_REMATCH[1]}; fi
  done
  name="$next-dev.$((n + 1))"
  prerelease=true
fi

echo "name=$name"
echo "build=$build"
echo "tag=$name+$build"
echo "prerelease=$prerelease"
echo "skip=false"
