#!/usr/bin/env bash
# Builds the browser version of the port into dist/: index.html plus the wasm bundle, ready to
# serve from any static host (GitHub Pages serves it at the URL in the README).
#   scripts/build-web.sh [--debug] [--harness]
# Needs the Swift toolchain and wasm SDK named in .swift-version (see README, "Building"),
# and the vendor/swiftui-web submodule checked out. `--harness` builds the test harness
# variant (compiled with -DHARNESS: the page's URL may lay out the board through the model's
# test seams, see SwiftUI2048App.makeGameLogic) into dist-harness/ instead of dist/; it is
# for the probe's controlled cases and is never the published page.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/vendor/swiftui-web"
[[ -f "$LIB/Package.swift" ]] || { echo "vendor/swiftui-web is empty: git submodule update --init"; exit 1; }
DEBUG=0; HARNESS=0
for ARG in "$@"; do
  case "$ARG" in
    --debug) DEBUG=1;;
    --harness) HARNESS=1;;
    *) echo "unknown argument $ARG"; exit 1;;
  esac
done
SCRATCH=.build/wasm; DIST_NAME=dist
# The manifest defines HARNESS from this variable (the PackageToJS plugin runs its own build,
# so a -Xswiftc flag on this command line would not reach the compiler).
if [[ $HARNESS == 1 ]]; then SCRATCH=.build/wasm-harness; DIST_NAME=dist-harness; export SWIFTUI2048_HARNESS=1; fi
SDK="swift-$(cat "$ROOT/.swift-version")-RELEASE_wasm"
# The library's environment: the swiftly toolchain first on PATH and, on macOS, the SDK and
# linker the wasm SDK's host tools can use.
# shellcheck disable=SC1091
. "$LIB/scripts/env.sh"
cd "$ROOT"
if [[ $DEBUG == 1 ]]; then
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path "$SCRATCH" js --use-cdn --debug-info-format dwarf
else
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path "$SCRATCH" -c release -Xswiftc -Osize js --use-cdn
fi
BUNDLE="$ROOT/$SCRATCH/plugins/PackageToJS/outputs/Package"
# The asset catalog (the app icon) as the library's host reads catalogs: a manifest plus files.
rm -rf "$BUNDLE/assets"
python3 "$LIB/scripts/assets.py" "$ROOT/SwiftUI2048" --js "$BUNDLE/assets/manifest.js" --out "$BUNDLE/assets"
# The site: the bundle under a name unique to this build so a browser that cached the previous
# index.js and wasm fetches the new ones; the page's loading bar measures against the wasm size.
DIST="$ROOT/$DIST_NAME"
rm -rf "$DIST" && mkdir -p "$DIST"
NAME="bundle-$(git -C "$ROOT" rev-parse --short HEAD)-$(date +%Y%m%d%H%M)"
cp -R "$BUNDLE" "$DIST/$NAME"
WASM="$DIST/$NAME/SwiftUI2048.wasm"
BYTES=$(stat -f%z "$WASM" 2>/dev/null || stat -c%s "$WASM")
sed -e "s|./.build/wasm/plugins/PackageToJS/outputs/Package/|./$NAME/|g" -e "s|data-wasm-bytes=\"\"|data-wasm-bytes=\"$BYTES\"|" \
  "$ROOT/Web/index.html" > "$DIST/index.html"
if [[ $HARNESS == 1 ]]; then sed -i.bak 's|<title>2048 — a SwiftUI game in the browser</title>|<title>2048 — test harness build</title>|' "$DIST/index.html" && rm "$DIST/index.html.bak"; fi
touch "$DIST/.nojekyll"
echo "Site: $DIST ($(du -sh "$DIST" | cut -f1), wasm $BYTES bytes); serve with: python3 -m http.server --directory $DIST"
