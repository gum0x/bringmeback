#!/usr/bin/env bash
# Gets the Symbolon pieces that `flutter build` doesn't fetch on its own:
#   tool/build_symbolon.sh native   compiles the native library for `flutter test` from the
#                                   symbolon_flutter package pubspec.yaml pins, into build/symbolon-native
#   tool/build_symbolon.sh web      downloads the JavaScript binding from that version's Symbolon release
#                                   into web/symbolon, after checking it against tool/symbolon-web.sha256
# App builds for phones and desktop don't need this: cargokit downloads the signed prebuilt library.
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
  web)
    # The checksum file names the release, and it must be the version pubspec.yaml pins.
    file=$(awk '{print $2}' tool/symbolon-web.sha256)
    version=${file#symbolon-web-}; version=${version%.tar.gz}
    pinned=$(sed -n 's/^ *ref: *//p' pubspec.yaml | head -1)
    [ "$version" = "$pinned" ] || { echo "tool/symbolon-web.sha256 is for $version, pubspec.yaml pins $pinned" >&2; exit 1; }
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/$file" "https://github.com/common-sec/symbolon/releases/download/$version/$file"
    cp tool/symbolon-web.sha256 "$tmp/"
    (cd "$tmp" && if command -v sha256sum >/dev/null; then sha256sum -c symbolon-web.sha256; else shasum -a 256 -c symbolon-web.sha256; fi)
    rm -rf web/symbolon
    tar -xzf "$tmp/$file" -C web
    ;;
  *) echo "usage: $0 native|web" >&2; exit 2 ;;
esac
