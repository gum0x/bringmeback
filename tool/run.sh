#!/usr/bin/env bash
# `flutter run` with the commit and its time (see tool/build_info.sh), so the app shows which code
# it runs: tool/run.sh -d chrome
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC2046 # the flags are meant to split into words
exec flutter run $(bash tool/build_info.sh defines) "$@"
