#!/usr/bin/env bash
# Builds the browser version of the port into dist/: index.html plus the wasm bundle, ready to
# serve from any static host (GitHub Pages serves it at the URL in the README).
#   scripts/build-web.sh [--debug]
# Needs the Swift toolchain and wasm SDK named in .swift-version (see README, "Building"),
# and the vendor/swiftui-web submodule checked out.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/vendor/swiftui-web"
[[ -f "$LIB/Package.swift" ]] || { echo "vendor/swiftui-web is empty: git submodule update --init"; exit 1; }
DEBUG=0; [[ "${1:-}" == "--debug" ]] && DEBUG=1
SDK="swift-$(cat "$ROOT/.swift-version")-RELEASE_wasm"
# The library's environment: the swiftly toolchain first on PATH and, on macOS, the SDK and
# linker the wasm SDK's host tools can use.
# shellcheck disable=SC1091
. "$LIB/scripts/env.sh"
cd "$ROOT"
if [[ $DEBUG == 1 ]]; then
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path .build/wasm js --use-cdn --debug-info-format dwarf
else
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path .build/wasm -c release -Xswiftc -Osize js --use-cdn
fi
BUNDLE="$ROOT/.build/wasm/plugins/PackageToJS/outputs/Package"
# The asset catalog (the app icon) as the library's host reads catalogs: a manifest plus files.
rm -rf "$BUNDLE/assets"
python3 "$LIB/scripts/assets.py" "$ROOT/SwiftUI2048" --js "$BUNDLE/assets/manifest.js" --out "$BUNDLE/assets"
# The site: the bundle under a name unique to this build so a browser that cached the previous
# index.js and wasm fetches the new ones; the page's loading bar measures against the wasm size.
DIST="$ROOT/dist"
rm -rf "$DIST" && mkdir -p "$DIST"
NAME="bundle-$(git -C "$ROOT" rev-parse --short HEAD)-$(date +%Y%m%d%H%M)"
cp -R "$BUNDLE" "$DIST/$NAME"
WASM="$DIST/$NAME/SwiftUI2048.wasm"
BYTES=$(stat -f%z "$WASM" 2>/dev/null || stat -c%s "$WASM")
sed -e "s|./.build/wasm/plugins/PackageToJS/outputs/Package/|./$NAME/|g" -e "s|data-wasm-bytes=\"\"|data-wasm-bytes=\"$BYTES\"|" \
  "$ROOT/Web/index.html" > "$DIST/index.html"
touch "$DIST/.nojekyll"
echo "Site: $DIST ($(du -sh "$DIST" | cut -f1), wasm $BYTES bytes); serve with: python3 -m http.server --directory $DIST"
