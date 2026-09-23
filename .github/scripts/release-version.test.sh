#!/usr/bin/env bash
# Copyright (c) 2026 InfAI (CC SES)
#
# Tests release-version.sh against throwaway repositories.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/release-version.sh"
failures=0

repo() {
  dir=$(mktemp -d)
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config tag.gpgsign false
}
commit() { git -C "$dir" commit -q --allow-empty -m "$1"; }
tag() { git -C "$dir" tag "$1"; }
field() { (cd "$dir" && "$script" "$1") | sed -n "s/^$2=//p"; }

expect() {
  local desc=$1 channel=$2 key=$3 want=$4 got
  got=$(field "$channel" "$key")
  if [[ $got == "$want" ]]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc: $key=$got, want $want"
    failures=$((failures + 1))
  fi
}

repo
commit "fix: old scheme"; tag "0.0.392+392"
commit "fix: first under the new scheme"
expect "old tags are no baseline" stable tag "0.1.0+393"
expect "first prerelease" prerelease tag "0.1.0-dev.1+393"
tag "0.1.0-dev.1+393"
expect "tagged head is skipped" prerelease skip "true"
commit "fix: second"
expect "prerelease counter grows" prerelease tag "0.1.0-dev.2+394"
tag "0.1.0-dev.2+394"
commit "Merge branch 'dev'"
expect "stable after prereleases" stable tag "0.1.0+395"
tag "0.1.0+395"
expect "stable head is skipped" stable skip "true"
commit "fix(mgw): patch"
expect "fix bumps patch" stable tag "0.1.1+396"
expect "prerelease targets next version" prerelease tag "0.1.1-dev.1+396"
commit "feat: minor"
expect "feat bumps minor" stable tag "0.2.0+396"
commit "refactor!: drop api"
expect "breaking below 1.0 bumps minor" stable tag "0.2.0+396"

repo
commit "fix: base"; tag "1.4.2+500"
commit "feat(ui): x"
commit "chore: y

BREAKING CHANGE: removed z"
expect "breaking footer bumps major" stable tag "2.0.0+501"

repo
commit "fix: base"; tag "0.1.0+394"
commit "docs: x

feat: quoted from another commit
refactor!: also quoted"
expect "types in a body are ignored" stable tag "0.1.1+395"
tag "weird+0999"
expect "leading zeros count as decimal" stable build "1000"

repo
commit "fix: base"; tag "0.3.0+10"
expect "no commits since stable" stable skip "true"

((failures == 0)) || { echo "$failures failure(s)"; exit 1; }
echo "all passed"
