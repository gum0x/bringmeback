#!/usr/bin/env bash
# Builds Symbolon's JavaScript binding into web/symbolon/, from the same commit that rust/Cargo.toml
# pins for the native build, so the web app and the other builds run the same code.
# Needs rustup with the wasm32-unknown-unknown target, and the wasm-bindgen CLI version that
# Symbolon's wasm/Cargo.toml pins (the script installs it if missing).
set -euo pipefail
cd "$(dirname "$0")/.."

rev=$(sed -n 's/^symbolon = .*rev = "\([0-9a-f]*\)".*/\1/p' rust/Cargo.toml)
[ -n "$rev" ] || { echo "No Symbolon rev in rust/Cargo.toml" >&2; exit 1; }

src=build/symbolon-src
if [ "$(git -C "$src" rev-parse HEAD 2>/dev/null)" != "$rev" ]; then
  rm -rf "$src"
  git init -q "$src"
  git -C "$src" fetch -q --depth 1 https://github.com/common-sec/symbolon "$rev"
  git -C "$src" checkout -q FETCH_HEAD
fi

bindgen=$(sed -n 's/^wasm-bindgen = "=\(.*\)"/\1/p' "$src/wasm/Cargo.toml")
if [ "$(wasm-bindgen --version 2>/dev/null | cut -d' ' -f2)" != "$bindgen" ]; then
  cargo install wasm-bindgen-cli --version "$bindgen" --locked
fi

rustup target add wasm32-unknown-unknown >/dev/null
(cd "$src" && cargo build --locked --release -p symbolon-wasm --target wasm32-unknown-unknown)
rm -rf web/symbolon
wasm-bindgen --target web --no-typescript --out-dir web/symbolon \
  "$src/target/wasm32-unknown-unknown/release/symbolon_wasm.wasm"
echo "Built web/symbolon from Symbolon $rev"
