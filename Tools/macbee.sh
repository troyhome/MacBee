#!/bin/bash
# Build, test and run MacBee.
# The project lives in iCloud Drive, so all build files go to ~/Library/Developer/MacBee on this Mac instead
# (they're large, change constantly, and are recreated automatically).
#
#   Tools/macbee.sh build     build the app
#   Tools/macbee.sh test      run the package tests
#   Tools/macbee.sh run       open the built app
#   Tools/macbee.sh install   build an optimized copy and put it in /Applications (then open it)
#   Tools/macbee.sh update    get the newest version from GitHub and install it (skips if already installed)
#   Tools/macbee.sh dmg       build an optimized copy and pack it as MacBee-<version>.dmg (drag to Applications)
#   Tools/macbee.sh icon      redraw the app icon
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HOME/Library/Developer/MacBee"

case "${1:-build}" in
    build)
        xcodebuild -project "$ROOT/MacBee.xcodeproj" -scheme MacBee -configuration Debug \
            -derivedDataPath "$OUT/DerivedData" -allowProvisioningUpdates build
        ;;
    test)
        for package in MacBeeAudio MacBeeLibrary MacBeeVideo; do
            (cd "$ROOT/Packages/$package" && swift test --scratch-path "$OUT/$package")
        done
        ;;
    run)
        open "$OUT/DerivedData/Build/Products/Debug/MacBee.app"
        ;;
    install)
        xcodebuild -project "$ROOT/MacBee.xcodeproj" -scheme MacBee -configuration Release \
            -derivedDataPath "$OUT/DerivedData-Release" -allowProvisioningUpdates build
        osascript -e 'quit app "MacBee"' 2>/dev/null || true
        sleep 2
        rm -rf /Applications/MacBee.app
        ditto "$OUT/DerivedData-Release/Build/Products/Release/MacBee.app" /Applications/MacBee.app
        open /Applications/MacBee.app
        echo "Installed /Applications/MacBee.app"
        ;;
    update)
        # Get the newest version from GitHub and install it, unless it's already installed.
        cd "$ROOT"
        git pull --ff-only
        STAMP="$OUT/installed-commit"
        COMMIT="$(git rev-parse HEAD)"
        if [[ -d /Applications/MacBee.app && -f "$STAMP" && "$(cat "$STAMP")" == "$COMMIT" ]]; then
            echo "MacBee is already up to date."
            exit 0
        fi
        "$0" install
        mkdir -p "$OUT"
        echo "$COMMIT" > "$STAMP"
        ;;
    dmg)
        # A disk image with MacBee and an Applications shortcut, for copying MacBee to another Mac.
        xcodebuild -project "$ROOT/MacBee.xcodeproj" -scheme MacBee -configuration Release \
            -derivedDataPath "$OUT/DerivedData-Release" -allowProvisioningUpdates build
        APP="$OUT/DerivedData-Release/Build/Products/Release/MacBee.app"
        VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
        STAGE="$OUT/dmg"
        rm -rf "$STAGE"
        mkdir -p "$STAGE"
        ditto "$APP" "$STAGE/MacBee.app"
        ln -s /Applications "$STAGE/Applications"
        DMG="$HOME/Desktop/MacBee-$VERSION.dmg"
        rm -f "$DMG"
        hdiutil create -volname "MacBee $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
        rm -rf "$STAGE"
        echo "Made $DMG"
        ;;
    icon)
        swift "$ROOT/Tools/make-icon.swift" "$OUT/AppIcon-1024.png"
        echo "Drawn to $OUT/AppIcon-1024.png; resize into MacBee/Assets.xcassets/AppIcon.appiconset."
        ;;
    *)
        echo "Usage: $0 build|test|run|install|update|dmg|icon" >&2
        exit 1
        ;;
esac
