#!/usr/bin/env bash
# Which build this is, for the version shown in the app (lib/version/build_info.dart):
#   tool/build_info.sh defines      prints the --dart-define flags for `flutter build`
#   tool/build_info.sh json DIR     writes DIR/build-info.json, which the web app checks for updates
#
# A released build is a commit tagged vX.Y.Z (or APP_VERSION set in the environment): it shows that
# number and the commit. Any other build shows the time of its last commit and the commit. With
# changes not yet committed, the commit gets -dirty and the time is when it was built, so two local
# builds of the same commit can still be told apart (a stale cache shows the earlier time). Without git (or outside a checkout) nothing is printed or written beyond {}.
# BUILD_COMMIT and BUILD_TIME in the environment take precedence, for builds without .git.
set -euo pipefail
cd "$(dirname "$0")/.."

commit=${BUILD_COMMIT:-}
time=${BUILD_TIME:-}
version=${APP_VERSION:-}
if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
  if [ -z "$commit" ]; then
    commit=$(git rev-parse --short=10 HEAD)
    # Only what goes into the app counts, so a Docker context (which leaves out other folders) or a
    # Windows checkout (CRLF line endings, no file modes) isn't marked dirty.
    git -c core.fileMode=false diff --quiet --ignore-cr-at-eol HEAD -- lib web assets pubspec.yaml \
      pubspec.lock 2>/dev/null || commit="$commit-dirty"
  fi
  if [ -z "$time" ]; then
    case "$commit" in
      *-dirty) time=$(date -u +%Y-%m-%dT%H:%M:%SZ) ;;
      *) time=$(git log -1 --format=%cI HEAD) ;;
    esac
  fi
  if [ -z "$version" ]; then
    tag=$(git describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null || true)
    version=${tag#v}
  fi
fi

case "${1:-}" in
  defines)
    out=""
    [ -z "$version" ] || out+=" --dart-define=APP_VERSION=$version"
    [ -z "$commit" ] || out+=" --dart-define=BUILD_COMMIT=$commit"
    [ -z "$time" ] || out+=" --dart-define=BUILD_TIME=$time"
    echo "${out# }"
    ;;
  json)
    dir=${2:?usage: $0 json DIR}
    fields=()
    [ -z "$version" ] || fields+=("\"version\":\"$version\"")
    [ -z "$commit" ] || fields+=("\"commit\":\"$commit\"")
    [ -z "$time" ] || fields+=("\"time\":\"$time\"")
    (IFS=,; echo "{${fields[*]}}") > "$dir/build-info.json"
    ;;
  *) echo "usage: $0 defines|json DIR" >&2; exit 2 ;;
esac
