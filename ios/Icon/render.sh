#!/bin/sh
# Render the app icon from the game's own shapes (Marks.swift, Grid.swift) and
# colours (skins.json).
#
#   Icon/render.sh [output.png]   the iPhone icon: the app's icon set, or a preview elsewhere
#   Icon/render.sh tv             the Apple TV's layered icons and Top Shelf images,
#                                 into DialhexTV/Assets.xcassets
set -e
here="$(cd "$(dirname "$0")" && pwd)"
ios="$here/.."
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# Marks.swift imports DialhexCore; here Grid.swift is compiled alongside instead
sed '/^import DialhexCore$/d' "$ios/Dialhex/Marks.swift" > "$build/Marks.swift"
cp "$ios/DialhexCore/Sources/DialhexCore/Grid.swift" "$build/Grid.swift"
cp "$here/IconRenderer.swift" "$build/main.swift"

xcrun swiftc -O -o "$build/render" "$build/main.swift" "$build/Marks.swift" "$build/Grid.swift"
render() { "$build/render" "$ios/../skins.json" "$@"; }

if [ "$1" != tv ]; then
  render "${1:-$ios/Dialhex/Assets.xcassets/AppIcon.appiconset/AppIcon.png}"
  exit 0
fi

brand="$ios/DialhexTV/Assets.xcassets/App Icon & Top Shelf Image.brandassets"

# Home screen icon (400×240 pt) and the App Store's (1280×768): the dial floats over the lattice
for pair in Back:back Front:front; do
  name="${pair%%:*}" layer="${pair#*:}"
  set="$brand/App Icon.imagestack/$name.imagestacklayer/Content.imageset"
  render "$set/$layer.png" 400 240 "$layer"
  render "$set/$layer@2x.png" 800 480 "$layer"
  render "$brand/App Icon - App Store.imagestack/$name.imagestacklayer/Content.imageset/$layer.png" 1280 768 "$layer"
done

# Top Shelf, flat
render "$brand/Top Shelf Image.imageset/top-shelf.png" 1920 720
render "$brand/Top Shelf Image.imageset/top-shelf@2x.png" 3840 1440
render "$brand/Top Shelf Image Wide.imageset/top-shelf-wide.png" 2320 720
render "$brand/Top Shelf Image Wide.imageset/top-shelf-wide@2x.png" 4640 1440
