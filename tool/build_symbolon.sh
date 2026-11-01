#!/usr/bin/env bash
# Builds Symbolon from the symbolon_flutter package that pubspec.yaml pins:
#   tool/build_symbolon.sh native   the native library for `flutter test`, in build/symbolon-native
#   tool/build_symbolon.sh web      the JavaScript binding for the web app, in web/symbolon
# App builds for phones and desktop don't need this: cargokit builds the native library then.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .dart_tool/package_config.json ] || flutter pub get
pkg=$(python3 -c 'import json, os, urllib.parse as u
c = json.load(open(".dart_tool/package_config.json"))
p = next(p for p in c["packages"] if p["name"] == "symbolon_flutter")
print(os.path.normpath(os.path.join(".dart_tool", u.unquote(u.urlparse(p["rootUri"]).path))))')

case "${1:-}" in
  native) cargo build --release --manifest-path "$pkg/rust/Cargo.toml" --target-dir build/symbolon-native ;;
  web) "$pkg/tool/build_web.sh" web/symbolon ;;
  *) echo "usage: $0 native|web" >&2; exit 2 ;;
esac
