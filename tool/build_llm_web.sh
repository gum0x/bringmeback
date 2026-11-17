#!/usr/bin/env bash
# Adds what the multilingual category model needs to run in the browser to web/: the llama.cpp WebGPU bridge assets the
# installed llamadart pins, checked against that release's manifest, and the script that loads them
# in web/index.html. Run it before `flutter build web`. The model itself is downloaded by the app,
# only when the user turns it on.
#
# The browser runs it only on a page served with cross-origin isolation
# (Cross-Origin-Opener-Policy: same-origin, Cross-Origin-Embedder-Policy: require-corp), as
# docker/nginx.conf does. Elsewhere the app keeps categorising with its word vectors.
set -euo pipefail
cd "$(dirname "$0")/.."
dart run llamadart:web_setup
