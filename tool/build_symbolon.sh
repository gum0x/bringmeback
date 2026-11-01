#!/usr/bin/env bash
# Builds Symbolon from the symbolon_flutter package that pubspec.yaml pins:
#   tool/build_symbolon.sh native   the native library for `flutter test`, in build/symbolon-native
#   tool/build_symbolon.sh web      the JavaScript binding for the web app, in web/symbolon
# App builds for phones and desktop don't need this: cargokit builds the native library then.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .dart_tool/package_config.json ] || flutter pub get
# Where pub put the package. Windows runners have `python`, not `python3`.
py=$(command -v python3 || command -v python)
pkg=$("$py" -c 'import json, os, re, urllib.parse as u
c = json.load(open(".dart_tool/package_config.json"))
p = next(p for p in c["packages"] if p["name"] == "symbolon_flutter")
path = u.unquote(u.urlparse(p["rootUri"]).path)
path = re.sub(r"^/([A-Za-z]:)", r"\1", path)  # file:///C:/... on Windows
print(os.path.normpath(os.path.join(".dart_tool", path)).replace(os.sep, "/"))')

case "${1:-}" in
  native) cargo build --release --manifest-path "$pkg/rust/Cargo.toml" --target-dir build/symbolon-native ;;
  web) "$pkg/tool/build_web.sh" web/symbolon ;;
  *) echo "usage: $0 native|web" >&2; exit 2 ;;
esac
