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
#   Tools/macbee.sh release [version]   raise the version (or set it), make the .dmg and post it as a GitHub
#                             Release (needs GitHub's tool once: brew install gh && gh auth login)
#   Tools/macbee.sh updater   (re)make the "Update MacBee" app in /Applications (one click = update)
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
    updater)
        # The "Update MacBee" app: runs `macbee.sh update` and says how it went. Made per Mac (not in Git).
        SCRIPT="$(mktemp -t update-macbee).applescript"
        cat > "$SCRIPT" <<'APPLESCRIPT'
-- Update MacBee: gets the newest version from GitHub and installs it.
display notification "Checking GitHub for a new version. This can take a few minutes." with title "Updating MacBee"
try
	set result to do shell script "L=$HOME/Library/Logs/MacBee-update.log; $HOME/Projects/MacBee/Tools/macbee.sh update > \"$L\" 2>&1 || { tail -5 \"$L\" >&2; exit 1; }; tail -1 \"$L\""
	if result contains "already up to date" then
		display dialog "MacBee is already up to date." buttons {"OK"} default button 1 with title "Update MacBee"
	else
		display dialog "MacBee has been updated and reopened." buttons {"OK"} default button 1 with title "Update MacBee"
	end if
on error errorText
	display dialog "The update didn't work:" & return & return & errorText buttons {"OK"} default button 1 with title "Update MacBee" with icon caution
end try
APPLESCRIPT
        rm -rf "/Applications/Update MacBee.app"
        osacompile -o "/Applications/Update MacBee.app" "$SCRIPT"
        rm -f "$SCRIPT"
        echo "Made /Applications/Update MacBee.app"
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
    release)
        # One step: new version number, .dmg, and a GitHub Release with the .dmg attached.
        GH="$(command -v gh || echo /opt/homebrew/bin/gh)"
        if [ ! -x "$GH" ] || ! "$GH" auth status >/dev/null 2>&1; then
            echo "First install GitHub's tool and sign in (once):  brew install gh && gh auth login" >&2
            exit 1
        fi
        cd "$ROOT"
        if [ -n "$(git status --porcelain)" ]; then
            echo "There are unsaved changes in the project. Commit them first." >&2
            exit 1
        fi
        git pull --rebase -q origin main
        PBX="$ROOT/MacBee.xcodeproj/project.pbxproj"
        CURRENT="$(grep -m1 'MARKETING_VERSION' "$PBX" | sed -E 's/.*= ([^;]+);/\1/')"
        BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBX" | sed -E 's/.*= ([^;]+);/\1/')"
        # Default: 1.0 -> 1.1, 1.2.3 -> 1.2.4.
        NEW="${2:-$(echo "$CURRENT" | awk -F. '{ $NF = $NF + 1; print }' OFS=.)}"
        if git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null; then
            echo "Version $NEW was already released. Give a newer one: $0 release <version>" >&2
            exit 1
        fi
        sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $NEW;/; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $((BUILD + 1));/" "$PBX"
        "$0" dmg
        DMG="$HOME/Desktop/MacBee-$NEW.dmg"
        [ -f "$DMG" ] || { echo "The .dmg wasn't made; version left changed but not released." >&2; exit 1; }
        git commit -qam "MacBee $NEW"
        git tag "v$NEW"
        git push -q origin main "v$NEW"
        "$GH" release create "v$NEW" "$DMG" --title "MacBee $NEW" --generate-notes
        echo "Released MacBee $NEW (was $CURRENT)."
        ;;
    icon)
        swift "$ROOT/Tools/make-icon.swift" "$OUT/AppIcon-1024.png"
        echo "Drawn to $OUT/AppIcon-1024.png; resize into MacBee/Assets.xcassets/AppIcon.appiconset."
        ;;
    *)
        echo "Usage: $0 build|test|run|install|update|dmg|release|updater|icon" >&2
        exit 1
        ;;
esac
