#!/bin/bash
# Build, test and run MacBee.
# The project lives in iCloud Drive, so all build files go to ~/Library/Developer/MacBee on this Mac instead
# (they're large, change constantly, and are recreated automatically).
#
#   Tools/macbee.sh build     build the app
#   Tools/macbee.sh test      run the package tests
#   Tools/macbee.sh run       open the built app
#   Tools/macbee.sh install   build an optimized copy and put it in /Applications (then open it)
#   Tools/macbee.sh icon      redraw the app icon
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HOME/Library/Developer/MacBee"

case "${1:-build}" in
    build)
        xcodebuild -project "$ROOT/MacBee.xcodeproj" -scheme MacBee -configuration Debug \
            -derivedDataPath "$OUT/DerivedData" build
        ;;
    test)
        for package in MacBeeAudio MacBeeLibrary; do
            (cd "$ROOT/Packages/$package" && swift test --scratch-path "$OUT/$package")
        done
        ;;
    run)
        open "$OUT/DerivedData/Build/Products/Debug/MacBee.app"
        ;;
    install)
        xcodebuild -project "$ROOT/MacBee.xcodeproj" -scheme MacBee -configuration Release \
            -derivedDataPath "$OUT/DerivedData-Release" build
        osascript -e 'quit app "MacBee"' 2>/dev/null || true
        sleep 2
        rm -rf /Applications/MacBee.app
        ditto "$OUT/DerivedData-Release/Build/Products/Release/MacBee.app" /Applications/MacBee.app
        open /Applications/MacBee.app
        echo "Installed /Applications/MacBee.app"
        ;;
    icon)
        swift "$ROOT/Tools/make-icon.swift" "$OUT/AppIcon-1024.png"
        echo "Drawn to $OUT/AppIcon-1024.png; resize into MacBee/Assets.xcassets/AppIcon.appiconset."
        ;;
    *)
        echo "Usage: $0 build|test|run|install|icon" >&2
        exit 1
        ;;
esac
