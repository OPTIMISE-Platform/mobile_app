#!/usr/bin/env bash
# Runs the tests tagged `isar` in an Ubuntu 24.04 container, whose glibc the
# Isar core binary needs. SDK, pub cache and repository are mounted at their
# host paths, so .dart_tool stays valid for the host toolchain.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$(readlink -f "$repo/.fvm/flutter_sdk")"
pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"
image="mobile-app-test-isar"

docker build -q -t "$image" - >/dev/null <<'DOCKERFILE'
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE

exec docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e PUB_CACHE="$pub_cache" \
  -e CI=true \
  -v "$sdk:$sdk" \
  -v "$pub_cache:$pub_cache" \
  -v "$repo:$repo" \
  -w "$repo" \
  "$image" \
  "$sdk/bin/flutter" test --run-skipped --tags isar "$@"
